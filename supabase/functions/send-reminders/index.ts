// Edge Function: envia as notificações (Web Push).
//
// Dois modos:
//  1) Agendador (a cada minuto, com o cabeçalho x-cron-secret): dispara os
//     lembretes vencidos da tabela `reminders`.
//  2) App (com o login do usuário): envia um aviso de teste para os aparelhos
//     da própria conta.
//
// Segredos necessários (Edge Functions > Secrets):
//   VAPID_KEYS_JSON  chaves geradas por tools/vapid.html
//   VAPID_SUBJECT    "mailto:seu@email.com"
//   CRON_SECRET      um texto aleatório (o mesmo usado em supabase/cron.sql)
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY já existem automaticamente.
//
// Desligue a verificação de JWT desta função (o agendador não manda JWT):
// a segurança é feita aqui dentro, pelo segredo ou pelo login do usuário.

import { createClient } from "npm:@supabase/supabase-js@2";
import * as webpush from "jsr:@negrel/webpush";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

let serverPromise: Promise<webpush.ApplicationServer> | null = null;
function getServer() {
  if (!serverPromise) {
    serverPromise = (async () => {
      const raw = Deno.env.get("VAPID_KEYS_JSON");
      if (!raw) throw new Error("falta o segredo VAPID_KEYS_JSON");
      const vapidKeys = await webpush.importVapidKeys(JSON.parse(raw));
      return await webpush.ApplicationServer.new({
        contactInformation: Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@example.com",
        vapidKeys,
      });
    })();
  }
  return serverPromise;
}

type Sub = { endpoint: string; p256dh: string; auth: string };

async function pushTo(subs: Sub[], payload: Record<string, unknown>) {
  const server = await getServer();
  let sent = 0, gone = 0, failed = 0;
  const errors: string[] = [];
  for (const s of subs) {
    try {
      const subscriber = server.subscribe({
        endpoint: s.endpoint,
        keys: { p256dh: s.p256dh, auth: s.auth },
      });
      await subscriber.pushTextMessage(JSON.stringify(payload), {});
      sent++;
    } catch (e) {
      if (e instanceof webpush.PushMessageError && e.isGone()) {
        // inscrição expirada ou removida pelo aparelho
        gone++;
        await supabase.from("push_subscriptions").delete().eq("endpoint", s.endpoint);
      } else {
        failed++;
        errors.push(String(e).slice(0, 200));
        console.error("falha ao enviar push:", String(e));
      }
    }
  }
  return { sent, gone, failed, errors };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const cronSecret = Deno.env.get("CRON_SECRET");
    const isCron = !!cronSecret && req.headers.get("x-cron-secret") === cronSecret;

    // ---- Modo app: aviso de teste ----------------------------------------
    if (!isCron) {
      const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
      const { data, error } = await supabase.auth.getUser(jwt);
      if (error || !data.user) return json({ error: "não autorizado" }, 401);

      const { data: subs, error: e2 } = await supabase
        .from("push_subscriptions")
        .select("endpoint,p256dh,auth")
        .eq("user_id", data.user.id);
      if (e2) return json({ error: e2.message }, 500);
      if (!subs || subs.length === 0) {
        return json({ sent: 0, message: "Nenhum aparelho inscrito nesta conta." });
      }
      const r = await pushTo(subs as Sub[], {
        title: "Rotina",
        body: "Teste: as notificações estão funcionando.",
        tag: "teste",
      });
      return json(r.errors.length ? { ...r, message: `Falhou: ${r.errors[0]}` } : r);
    }

    // ---- Modo agendador: lembretes vencidos ---------------------------------
    const now = Date.now();
    const { data: due, error: eDue } = await supabase
      .from("reminders")
      .select("user_id,key,title,body,fire_at")
      .is("sent_at", null)
      .lte("fire_at", new Date(now).toISOString())
      .order("fire_at")
      .limit(200);
    if (eDue) return json({ error: eDue.message }, 500);
    if (!due || due.length === 0) return json({ due: 0 });

    const userIds = [...new Set(due.map((d) => d.user_id as string))];
    const { data: allSubs } = await supabase
      .from("push_subscriptions")
      .select("user_id,endpoint,p256dh,auth")
      .in("user_id", userIds);
    const byUser = new Map<string, Sub[]>();
    for (const s of allSubs ?? []) {
      const list = byUser.get(s.user_id as string) ?? [];
      list.push({ endpoint: s.endpoint, p256dh: s.p256dh, auth: s.auth });
      byUser.set(s.user_id as string, list);
    }

    let sent = 0, skipped = 0;
    for (const d of due) {
      // Marca como enviado antes: no pior caso perde um aviso, mas nunca repete.
      await supabase
        .from("reminders")
        .update({ sent_at: new Date().toISOString() })
        .eq("user_id", d.user_id)
        .eq("key", d.key);

      // Aviso muito atrasado (mais de 10 min) não adianta mais: descarta.
      if (new Date(d.fire_at).getTime() < now - 10 * 60 * 1000) {
        skipped++;
        continue;
      }
      const subs = byUser.get(d.user_id as string) ?? [];
      if (subs.length === 0) continue;
      const r = await pushTo(subs, { title: d.title, body: d.body ?? "", tag: d.key });
      sent += r.sent;
    }
    return json({ due: due.length, sent, skipped });
  } catch (e) {
    console.error(e);
    return json({ error: String(e) }, 500);
  }
});

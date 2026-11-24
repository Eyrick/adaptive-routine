-- Notificações: rode este arquivo uma vez no SQL Editor do Supabase,
-- depois de supabase/schema.sql (veja docs/NOTIFICATIONS.md). Pode repetir.

-- Aparelhos que recebem avisos (um por navegador/aparelho inscrito).
create table if not exists public.push_subscriptions (
  endpoint   text primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  p256dh     text not null,
  auth       text not null,
  device     text,
  created_at timestamptz not null default now()
);

-- Avisos agendados. O app recalcula e envia os dos próximos dias; o servidor
-- dispara os que venceram e marca sent_at.
create table if not exists public.reminders (
  user_id uuid not null references auth.users (id) on delete cascade,
  key     text not null,
  fire_at timestamptz not null,
  title   text not null,
  body    text,
  sent_at timestamptz,
  primary key (user_id, key)
);
create index if not exists reminders_due_idx on public.reminders (fire_at) where sent_at is null;

-- Acesso de quem está logado (como na tabela user_state).
grant select, insert, update, delete on table public.push_subscriptions to authenticated;
grant select, insert, update, delete on table public.reminders to authenticated;

alter table public.push_subscriptions enable row level security;
alter table public.reminders enable row level security;

drop policy if exists "dono le"     on public.push_subscriptions;
drop policy if exists "dono insere" on public.push_subscriptions;
drop policy if exists "dono atualiza" on public.push_subscriptions;
drop policy if exists "dono apaga"  on public.push_subscriptions;
create policy "dono le"      on public.push_subscriptions for select using (auth.uid() = user_id);
create policy "dono insere"  on public.push_subscriptions for insert with check (auth.uid() = user_id);
create policy "dono atualiza" on public.push_subscriptions for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "dono apaga"   on public.push_subscriptions for delete using (auth.uid() = user_id);

drop policy if exists "dono le"     on public.reminders;
drop policy if exists "dono insere" on public.reminders;
drop policy if exists "dono atualiza" on public.reminders;
drop policy if exists "dono apaga"  on public.reminders;
create policy "dono le"      on public.reminders for select using (auth.uid() = user_id);
create policy "dono insere"  on public.reminders for insert with check (auth.uid() = user_id);
create policy "dono atualiza" on public.reminders for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "dono apaga"   on public.reminders for delete using (auth.uid() = user_id);

-- O app chama esta função com a lista completa de lembretes dos próximos dias:
-- apaga os ainda não enviados que saíram da lista e grava/atualiza os demais.
create or replace function public.sync_reminders(items jsonb)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  delete from public.reminders r
   where r.user_id = auth.uid()
     and r.sent_at is null
     and r.key not in (select x ->> 'key' from jsonb_array_elements(items) as x);

  insert into public.reminders (user_id, key, fire_at, title, body)
  select auth.uid(), x ->> 'key', (x ->> 'fire_at')::timestamptz, x ->> 'title', x ->> 'body'
    from jsonb_array_elements(items) as x
  on conflict (user_id, key) do update
     set fire_at = excluded.fire_at,
         title   = excluded.title,
         body    = excluded.body
   where public.reminders.sent_at is null;
end;
$$;

grant execute on function public.sync_reminders(jsonb) to authenticated;

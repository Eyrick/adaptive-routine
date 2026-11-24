# Notificações (iPhone, Android e computador, pelo app web)

Com as notificações ligadas, o app avisa **30 minutos antes de cada compromisso** (da base fixa e do dinâmico) e manda um **resumo da rotina de amanhã às 21h** (e, se amanhã for feriado ou evento, o nome dele aparece no título).

## Como funciona

1. O app calcula os avisos dos próximos 14 dias e envia para a nuvem (tabela `reminders`) **sempre que a agenda muda**. Isso acontece em todo aparelho com conta, então mudar a agenda no computador atualiza os avisos do iPhone mesmo com o app fechado nele.
2. A cada minuto, o agendador do Supabase (`pg_cron`) chama a função `send-reminders`, que pega os avisos vencidos e os entrega pelo serviço de notificações (Web Push).
3. O **aparelho** precisa estar inscrito (botão "Ativar notificações" na tela de conta) e o iPhone precisa ter o app **instalado na Tela de Início**.

Os avisos chegam com até cerca de 1 minuto de diferença.

## Passo 1: gerar as chaves

1. Abra o arquivo `tools/vapid.html` no Chrome ou no Edge (dê dois cliques nele). A página gera as chaves no seu navegador, sem enviar nada pela internet.
2. Clique em **Gerar chaves**. Aparecem dois campos:
   - **VAPID_PUBLIC_KEY** (pode ser pública): vai no `env.json`.
   - **VAPID_KEYS_JSON** (**contém a chave privada**): vai num segredo do Supabase. Não envie, não publique e não coloque no GitHub.
3. Deixe a página aberta (ou copie os dois valores para um bloco de notas) até terminar os passos 3 e 5. Se fechar, é só gerar de novo, mas as chaves mudam e você refaz esses passos.

## Passo 2: criar as tabelas

No Supabase, **SQL Editor > New query**, cole o conteúdo de `supabase/notifications.sql` e clique em **Run**. Deve aparecer sucesso. Pode repetir sem problema.

## Passo 3: criar a função que envia os avisos

1. No Supabase, abra **Edge Functions** e escolha criar uma função nova **pelo editor** ("Via Editor"). Os nomes dos menus mudam, então siga o que mais se parecer.
2. Nome da função: **`send-reminders`** (exatamente assim).
3. Apague o exemplo e cole o conteúdo de `supabase/functions/send-reminders/index.ts`. Clique em **Deploy**.
4. Nas configurações da função, **desligue a verificação de JWT** ("Verify JWT" ou "Enforce JWT verification"). O agendador não envia JWT, e a função se protege sozinha, por um segredo ou pelo login do usuário.
5. Em **Edge Functions > Secrets** (ou "Manage secrets"), acrescente três segredos:

| Nome | Valor |
|---|---|
| `VAPID_KEYS_JSON` | o texto inteiro do campo 2 da página de chaves |
| `VAPID_SUBJECT` | `mailto:` mais o seu e-mail, por exemplo `mailto:voce@gmail.com` |
| `CRON_SECRET` | um texto aleatório longo, que você inventa (guarde: ele volta no passo 4) |

Pela linha de comando (opcional, com o Supabase CLI): `supabase functions deploy send-reminders --no-verify-jwt`.

## Passo 4: ligar o agendador

1. Em **Database > Extensions**, ative **pg_cron** e **pg_net** (o arquivo abaixo também tenta ativá-las).
2. Abra `supabase/cron.sql` num bloco de notas e troque:
   - `SEU-PROJETO` pelo código do seu projeto (o endereço é o *Project URL* da tela de API);
   - `SEU-SEGREDO` pelo mesmo valor que você usou em `CRON_SECRET`.
3. Cole no **SQL Editor** e clique em **Run**.

## Passo 5: ligar no app

1. Acrescente `VAPID_PUBLIC_KEY` ao seu `env.json` (veja `env.example.json`).
2. Gere o site e publique de novo:
   ```
   flutter pub get
   flutter test
   flutter build web --release --no-web-resources-cdn --dart-define-from-file=env.json
   ```
   Suba a pasta `build\web` na Cloudflare e abra o endereço **duas vezes** no iPhone.
3. **No iPhone, abra o app pelo ícone da Tela de Início** (se ele já estava instalado, abra-o e feche por completo uma vez). Se ainda não instalou: Safari, Compartilhar, "Adicionar à Tela de Início".
4. No app: ícone de nuvem, **Conta e sincronização**, bloco **Notificações neste aparelho**, **Ativar notificações**, e **Permitir** quando o iPhone perguntar. O toque tem que ser direto no botão.
5. Toque em **Enviar teste**. Deve chegar uma notificação "Teste: as notificações estão funcionando".

## Conferir se está funcionando

- **Table Editor > push_subscriptions:** uma linha para cada aparelho inscrito.
- **Table Editor > reminders:** os avisos dos próximos dias, com `fire_at`. Depois de enviados, `sent_at` fica preenchido.
- **Agendador:** no SQL Editor, `select status, return_message, start_time from cron.job_run_details order by start_time desc limit 5;` deve mostrar execuções a cada minuto.
- **Respostas da função:** `select status_code, content from net._http_response order by created desc limit 5;`
- **Edge Functions > send-reminders > Logs:** mensagens de erro, se houver.

## Cuidados no iPhone

- Só funciona com o app **instalado na Tela de Início**, no iOS 16.4 ou mais novo. No Safari comum, o app mostra a orientação de instalar.
- A permissão precisa ser pedida por um **toque** no botão. Se você negar, o app mostra como liberar em Ajustes do iPhone e o botão **Verificar de novo**.
- Os **Modos de Foco** (Não Perturbe, Trabalho etc.) e a economia de bateria podem atrasar ou silenciar avisos.
- Se o iPhone receber avisos que não mostram nada, o iOS pode cancelar a inscrição. A função sempre mostra o aviso, então isso não deve acontecer.

## Limites desta versão

- A antecedência é fixa em **30 minutos** e o resumo é às **21h**. Uma tela de configurações para mudar isso é um passo futuro.
- Os avisos cobrem os **próximos 14 dias** e são renovados toda vez que algum aparelho com conta sincroniza. Se ninguém abrir o app por mais de 14 dias, os avisos acabam.
- Um aviso de um compromisso feito (ou não realizado) deixa de ser enviado na próxima sincronização.
- O aviso é **uma vez só**, sem repetição. Se o servidor ficar parado por mais de 10 minutos, avisos atrasados são descartados.

## Problemas comuns

| Sintoma | O que fazer |
|---|---|
| "Enviar teste" diz que nenhum aparelho está inscrito | Toque em **Ativar notificações** de novo, e confira a tabela `push_subscriptions`. |
| "não autorizado" ao testar | A função foi publicada sem o login do app. Confira o nome (`send-reminders`) e que você está logado. |
| "falta o segredo VAPID_KEYS_JSON" | Crie o segredo (passo 3.5) e publique a função de novo. |
| Erro de chaves ao enviar | Gere um par novo em `tools/vapid.html`, atualize o `env.json` **e** o segredo, e publique o app e a função de novo. As duas chaves precisam ser do mesmo par. |
| O teste chega, mas os avisos de compromissos não | Confira o agendador (`cron.job_run_details`), o segredo `CRON_SECRET` igual nos dois lugares e a tabela `reminders`. |
| Nada no iPhone, e a permissão está "negada" | Ajustes do iPhone, Notificações, Rotina: permita; no app, toque em Verificar de novo. |
| "Este navegador não suporta" | No iPhone, use o app instalado pelo ícone. Em outros navegadores, use o Chrome, o Edge ou o Safari atualizados. |

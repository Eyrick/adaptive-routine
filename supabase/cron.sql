-- Agendador: chama a função send-reminders a cada minuto.
-- ANTES de rodar, troque SEU-PROJETO e SEU-SEGREDO abaixo (veja docs/NOTIFICATIONS.md).
-- O segredo é o mesmo valor do segredo CRON_SECRET da Edge Function.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Limpa uma configuração anterior, para este arquivo poder ser rodado de novo.
select cron.unschedule(jobid) from cron.job where jobname = 'send-reminders';
delete from vault.secrets where name in ('project_url', 'cron_secret');

select vault.create_secret('https://bwmhjknxfgzgqfkonjhe.supabase.co', 'project_url');
select vault.create_secret('KJHV1YT3V4KJ1VLJHVFUT1V23OH4B1234F12P34J', 'cron_secret');

select cron.schedule(
  'send-reminders',
  '* * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/send-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 10000
  );
  $$
);

-- Para parar o agendador: select cron.unschedule('send-reminders');

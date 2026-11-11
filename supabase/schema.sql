-- Rode este arquivo uma vez, no SQL Editor do Supabase (veja docs/SYNC.md).

create table if not exists public.user_state (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  data       jsonb       not null,
  version    bigint      not null default 1,
  updated_at timestamptz not null default now(),
  device     text
);

-- Libera a tabela para quem está logado. Sem isto, projetos novos do Supabase
-- respondem "permission denied for table user_state". Quem não tem conta
-- (anon) continua sem acesso nenhum.
grant select, insert, update, delete on table public.user_state to authenticated;

-- Cada conta só enxerga e altera a própria linha.
alter table public.user_state enable row level security;

drop policy if exists "dono le" on public.user_state;
drop policy if exists "dono insere" on public.user_state;
drop policy if exists "dono atualiza" on public.user_state;
drop policy if exists "dono apaga" on public.user_state;

create policy "dono le" on public.user_state
  for select using (auth.uid() = user_id);

create policy "dono insere" on public.user_state
  for insert with check (auth.uid() = user_id);

create policy "dono atualiza" on public.user_state
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "dono apaga" on public.user_state
  for delete using (auth.uid() = user_id);

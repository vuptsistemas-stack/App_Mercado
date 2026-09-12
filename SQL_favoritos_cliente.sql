-- Execute este SQL no Supabase da loja antes de publicar o app.
create table if not exists public.cliente_favoritos (
  id uuid primary key default gen_random_uuid(),
  mercado_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  produto_chave text not null,
  produto_id text,
  ean text,
  nome_produto text not null,
  criado_em timestamptz not null default now(),
  unique (mercado_id, user_id, produto_chave)
);

alter table public.cliente_favoritos enable row level security;

drop policy if exists "cliente le os proprios favoritos" on public.cliente_favoritos;
create policy "cliente le os proprios favoritos" on public.cliente_favoritos
  for select using (auth.uid() = user_id);

drop policy if exists "cliente inclui os proprios favoritos" on public.cliente_favoritos;
create policy "cliente inclui os proprios favoritos" on public.cliente_favoritos
  for insert with check (auth.uid() = user_id);

drop policy if exists "cliente exclui os proprios favoritos" on public.cliente_favoritos;
create policy "cliente exclui os proprios favoritos" on public.cliente_favoritos
  for delete using (auth.uid() = user_id);

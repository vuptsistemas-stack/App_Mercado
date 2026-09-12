-- Execute uma unica vez NO BANCO DA LOJA, onde existem as tabelas
-- cupons_desconto e pedidos. Nao execute no Supabase Central.

alter table public.cupons_desconto
  add column if not exists somente_primeira_compra boolean not null default false;

create index if not exists idx_pedidos_mercado_usuario
  on public.pedidos (mercado_id, user_id);

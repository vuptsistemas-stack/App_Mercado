-- Execute no Supabase da loja. Os termos ficam configurados no banco,
-- sem marcas ou categorias fixas no aplicativo.
create table if not exists public.catalogo_busca_sinonimos (
  id uuid primary key default gen_random_uuid(),
  mercado_id uuid not null,
  termo_base text not null,
  termo_relacionado text not null,
  criado_em timestamptz not null default now(),
  unique (mercado_id, termo_base, termo_relacionado)
);

create index if not exists catalogo_busca_sinonimos_mercado_termo_idx
  on public.catalogo_busca_sinonimos (mercado_id, termo_base);

alter table public.catalogo_busca_sinonimos enable row level security;

drop policy if exists "clientes leem sinonimos do catalogo" on public.catalogo_busca_sinonimos;
create policy "clientes leem sinonimos do catalogo"
  on public.catalogo_busca_sinonimos for select to authenticated using (true);

-- Cadastre pelo painel/admin um registro por termo relacionado.
-- Exemplo para um mercado (substitua o UUID):
-- insert into public.catalogo_busca_sinonimos
--   (mercado_id, termo_base, termo_relacionado)
-- values
--   ('UUID_DO_MERCADO', 'DETERGENTE', 'YPE'),
--   ('UUID_DO_MERCADO', 'DETERGENTE', 'LIMPOL');

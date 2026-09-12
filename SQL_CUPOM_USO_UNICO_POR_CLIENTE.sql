-- Execute uma unica vez NO BANCO DA LOJA que utiliza os cupons.
-- Nao execute no Supabase Central: cupons_desconto pertence a cada loja.

alter table public.cupons_desconto
  add column if not exists uso_unico_por_cliente boolean not null default false;

create table if not exists public.cupom_usos_clientes (
  id uuid primary key default gen_random_uuid(),
  mercado_id uuid not null,
  cupom_id uuid not null references public.cupons_desconto(id) on delete cascade,
  -- O cliente pertence ao Supabase da loja, que e diferente do Central.
  cliente_id uuid not null,
  pedido_id uuid,
  usado_em timestamptz not null default now(),
  constraint cupom_usos_clientes_unico unique (mercado_id, cupom_id, cliente_id)
);

alter table public.cupom_usos_clientes enable row level security;

create index if not exists idx_cupom_usos_clientes_cliente
  on public.cupom_usos_clientes (mercado_id, cliente_id);

-- Esta RPC trava o cupom, registra o cliente e incrementa o uso na mesma
-- transacao. O retorno false significa cupom indisponivel ou ja utilizado.
create or replace function public.consumir_uso_unico_cupom_desconto(
  p_mercado_id uuid,
  p_cupom_id uuid,
  p_cliente_id uuid,
  p_pedido_id uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limite_uso integer;
  v_quantidade_usada integer;
begin
  select
    coalesce(limite_uso, 0),
    coalesce(quantidade_usada, 0)
  into v_limite_uso, v_quantidade_usada
  from public.cupons_desconto
  where id = p_cupom_id
    and mercado_id = p_mercado_id
    and ativo = true
  for update;

  if not found or (v_limite_uso > 0 and v_quantidade_usada >= v_limite_uso) then
    return false;
  end if;

  insert into public.cupom_usos_clientes (
    mercado_id,
    cupom_id,
    cliente_id,
    pedido_id
  )
  values (
    p_mercado_id,
    p_cupom_id,
    p_cliente_id,
    p_pedido_id
  )
  on conflict (mercado_id, cupom_id, cliente_id) do nothing;

  if not found then
    return false;
  end if;

  update public.cupons_desconto
  set quantidade_usada = coalesce(quantidade_usada, 0) + 1,
      atualizado_em = now()
  where id = p_cupom_id
    and mercado_id = p_mercado_id;

  return true;
end;
$$;

revoke all on function public.consumir_uso_unico_cupom_desconto(uuid, uuid, uuid, uuid) from public;
grant execute on function public.consumir_uso_unico_cupom_desconto(uuid, uuid, uuid, uuid) to service_role;

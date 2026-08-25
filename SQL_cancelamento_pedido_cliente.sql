-- Execute este SQL na base Supabase da loja.
-- Ele permite que o cliente cancele o proprio pedido enquanto estiver
-- novo ou em preparacao, devolvendo o estoque dos produtos_app quando
-- o pedido foi baixado no estoque da loja.

alter table public.pedidos
  add column if not exists cancelado_por text,
  add column if not exists cancelado_em timestamp with time zone,
  add column if not exists motivo_cancelamento text;

create or replace function public.cancelar_pedido_cliente_app(
  p_pedido_id uuid,
  p_mercado_id uuid
)
returns table (
  id uuid,
  status text,
  cancelado_por text,
  cancelado_em timestamp with time zone
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido public.pedidos%rowtype;
  v_item record;
  v_quantidade numeric;
begin
  if auth.uid() is null then
    raise exception 'Usuario nao autenticado';
  end if;

  select *
    into v_pedido
    from public.pedidos
   where pedidos.id = p_pedido_id
     and pedidos.mercado_id = p_mercado_id
     and pedidos.user_id = auth.uid()
   for update;

  if not found then
    raise exception 'Pedido nao encontrado';
  end if;

  if lower(coalesce(v_pedido.status, 'novo')) not in (
    'novo',
    'recebido',
    'pedido_recebido',
    'preparando',
    'preparacao',
    'em_preparacao',
    'separando',
    'separacao',
    'em_separacao'
  ) then
    raise exception 'Pedido nao pode mais ser cancelado';
  end if;

  for v_item in
    select *
      from public.pedido_itens
     where pedido_itens.pedido_id = p_pedido_id
       and pedido_itens.mercado_id = p_mercado_id
       and pedido_itens.produto_app_id is not null
       and pedido_itens.produto_app_id::text <> ''
  loop
    v_quantidade := coalesce(
      nullif(v_item.peso_real_kg, 0),
      nullif(v_item.peso_estimado_kg, 0),
      nullif(v_item.quantidade_unidade, 0),
      nullif(v_item.quantidade, 0),
      0
    );

    if v_quantidade > 0 then
      update public.produtos_app
         set estoque = coalesce(estoque, 0) + v_quantidade,
             atualizado_em = now()
       where produtos_app.id::text = v_item.produto_app_id::text
         and produtos_app.mercado_id = p_mercado_id;
    end if;
  end loop;

  return query
  update public.pedidos
     set status = 'cancelado',
         cancelado_por = 'cliente',
         cancelado_em = now(),
         motivo_cancelamento = coalesce(
           nullif(motivo_cancelamento, ''),
           'Cancelado pelo cliente no aplicativo'
         ),
         atualizado_em = now()
   where pedidos.id = p_pedido_id
     and pedidos.mercado_id = p_mercado_id
   returning pedidos.id,
             pedidos.status,
             pedidos.cancelado_por,
             pedidos.cancelado_em;
end;
$$;

grant execute on function public.cancelar_pedido_cliente_app(uuid, uuid)
  to authenticated;

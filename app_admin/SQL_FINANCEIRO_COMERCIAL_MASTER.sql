-- Modulo Financeiro e Comercial - Vupt Sistemas
-- Execute uma unica vez na base Supabase central, que atende todas as lojas.
-- O script e idempotente e protege os dados com a funcao public.is_master().

begin;

-- 1) Estrutura central de contratos, apuracoes, cobrancas e auditoria.
-- Os pedidos ficam na base Supabase de cada loja. A Edge Function
-- financeiro-master consulta cada base com service_role e grava somente o
-- resumo mensal abaixo no banco central.
create table if not exists public.financeiro_apuracoes_loja (
  id uuid primary key default gen_random_uuid(),
  mercado_id uuid not null references public.mercados(id) on delete cascade,
  competencia date not null,
  gmv_elegivel numeric(14,2) not null default 0 check (gmv_elegivel >= 0),
  pedidos_elegiveis integer not null default 0 check (pedidos_elegiveis >= 0),
  pedidos_em_andamento integer not null default 0 check (pedidos_em_andamento >= 0),
  sincronizado_em timestamptz,
  ultima_tentativa_em timestamptz not null default now(),
  sincronizacao_ok boolean not null default false,
  erro_sincronizacao text not null default '',
  detalhes jsonb not null default '{}'::jsonb,
  unique (mercado_id, competencia)
);

create table if not exists public.financeiro_modulos_acesso (
  mercado_id uuid not null references public.mercados(id) on delete cascade,
  modulo_codigo text not null,
  permitido boolean not null default true,
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  primary key (mercado_id, modulo_codigo)
);

create table if not exists public.financeiro_modulos_catalogo (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nome text not null,
  descricao text not null default '',
  preco_padrao numeric(14,2) not null default 10 check (preco_padrao >= 0),
  incluido_plano_base boolean not null default false,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid
);

create table if not exists public.financeiro_contratos (
  id uuid primary key default gen_random_uuid(),
  mercado_id uuid not null unique references public.mercados(id),
  status text not null default 'RASCUNHO'
    check (status in ('RASCUNHO', 'ATIVO', 'CANCELADO')),
  inicio_em date not null,
  cancelado_em date,
  tipo_implantacao text not null default 'SEM_IMPLANTACAO'
    check (tipo_implantacao in (
      'SEM_IMPLANTACAO', 'ERP_INTEGRADO', 'ERP_NOVO', 'SOB_ORCAMENTO'
    )),
  valor_implantacao numeric(14,2) not null default 0
    check (valor_implantacao >= 0),
  desconto_implantacao numeric(14,2) not null default 0
    check (desconto_implantacao >= 0),
  implantacao_competencia date,
  dia_vencimento smallint not null default 10
    check (dia_vencimento between 1 and 28),
  dias_carencia smallint not null default 15
    check (dias_carencia >= 0),
  observacao text not null default '',
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  criado_por uuid,
  atualizado_por uuid,
  constraint financeiro_contrato_desconto_valido
    check (desconto_implantacao <= valor_implantacao)
);

create table if not exists public.financeiro_contrato_periodos (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.financeiro_contratos(id) on delete cascade,
  inicio_em date not null,
  fim_em date,
  motivo text not null default '',
  criado_em timestamptz not null default now(),
  criado_por uuid,
  check (fim_em is null or fim_em >= inicio_em)
);

create table if not exists public.financeiro_contrato_modulos (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.financeiro_contratos(id) on delete cascade,
  modulo_id uuid not null references public.financeiro_modulos_catalogo(id),
  ativo boolean not null default true,
  preco_mensal numeric(14,2) not null check (preco_mensal >= 0),
  vigencia_inicio date not null,
  vigencia_fim date,
  motivo text not null,
  criado_em timestamptz not null default now(),
  criado_por uuid,
  check (vigencia_fim is null or vigencia_fim >= vigencia_inicio)
);

create table if not exists public.financeiro_cobrancas (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.financeiro_contratos(id),
  mercado_id uuid not null references public.mercados(id),
  competencia date not null,
  periodo_inicio date not null,
  periodo_fim date not null,
  dias_ativos integer not null default 0,
  dias_no_mes integer not null,
  gmv_elegivel numeric(14,2) not null default 0,
  pedidos_elegiveis integer not null default 0,
  ticket_medio numeric(14,2) not null default 0,
  faturamento_equivalente numeric(14,2) not null default 0,
  valor_plano_base numeric(14,2) not null default 0,
  valor_modulos numeric(14,2) not null default 0,
  valor_implantacao numeric(14,2) not null default 0,
  valor_ajustes numeric(14,2) not null default 0,
  valor_total numeric(14,2) not null default 0,
  status text not null default 'AGUARDANDO_EMISSAO'
    check (status in (
      'EM_APURACAO', 'AGUARDANDO_EMISSAO', 'EMITIDA', 'PAGA',
      'VENCIDA', 'NEGOCIADA', 'CANCELADA'
    )),
  vencimento_em date not null,
  referencia text not null default '',
  forma_pagamento text not null default '',
  pago_em timestamptz,
  observacao text not null default '',
  fechado_em timestamptz not null default now(),
  criado_por uuid,
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  unique (mercado_id, competencia)
);

create table if not exists public.financeiro_cobranca_itens (
  id uuid primary key default gen_random_uuid(),
  cobranca_id uuid not null references public.financeiro_cobrancas(id) on delete cascade,
  tipo text not null,
  codigo text not null,
  descricao text not null,
  quantidade numeric(14,4) not null default 1,
  valor_unitario numeric(14,2) not null default 0,
  valor_total numeric(14,2) not null default 0,
  detalhes jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now()
);

create table if not exists public.financeiro_auditoria (
  id uuid primary key default gen_random_uuid(),
  mercado_id uuid references public.mercados(id),
  entidade text not null,
  entidade_id uuid,
  acao text not null,
  motivo text not null default '',
  dados_antes jsonb,
  dados_depois jsonb,
  usuario_id uuid,
  usuario_email text,
  criado_em timestamptz not null default now()
);

create index if not exists idx_financeiro_periodos_contrato
  on public.financeiro_contrato_periodos (contrato_id, inicio_em, fim_em);
create index if not exists idx_financeiro_apuracoes_competencia
  on public.financeiro_apuracoes_loja (competencia, mercado_id);
create index if not exists idx_financeiro_apuracoes_sincronizacao
  on public.financeiro_apuracoes_loja (mercado_id, sincronizado_em desc);
create index if not exists idx_financeiro_modulos_contrato
  on public.financeiro_contrato_modulos (contrato_id, modulo_id, vigencia_inicio);
create index if not exists idx_financeiro_cobrancas_status_vencimento
  on public.financeiro_cobrancas (status, vencimento_em);
create index if not exists idx_financeiro_cobrancas_mercado
  on public.financeiro_cobrancas (mercado_id, competencia desc);
create index if not exists idx_financeiro_auditoria_mercado
  on public.financeiro_auditoria (mercado_id, criado_em desc);

-- 3) Somente master central pode ler ou alterar dados financeiros.
alter table public.financeiro_apuracoes_loja enable row level security;
alter table public.financeiro_modulos_acesso enable row level security;
alter table public.financeiro_modulos_catalogo enable row level security;
alter table public.financeiro_contratos enable row level security;
alter table public.financeiro_contrato_periodos enable row level security;
alter table public.financeiro_contrato_modulos enable row level security;
alter table public.financeiro_cobrancas enable row level security;
alter table public.financeiro_cobranca_itens enable row level security;
alter table public.financeiro_auditoria enable row level security;

do $$
declare
  tabela text;
begin
  foreach tabela in array array[
    'financeiro_apuracoes_loja',
    'financeiro_modulos_acesso',
    'financeiro_modulos_catalogo',
    'financeiro_contratos',
    'financeiro_contrato_periodos',
    'financeiro_contrato_modulos',
    'financeiro_cobrancas',
    'financeiro_cobranca_itens',
    'financeiro_auditoria'
  ] loop
    execute format('drop policy if exists financeiro_master_total on public.%I', tabela);
    execute format(
      'create policy financeiro_master_total on public.%I for all to authenticated using (public.is_master()) with check (public.is_master())',
      tabela
    );
  end loop;
end;
$$;

grant select, insert, update, delete on
  public.financeiro_apuracoes_loja,
  public.financeiro_modulos_acesso,
  public.financeiro_modulos_catalogo,
  public.financeiro_contratos,
  public.financeiro_contrato_periodos,
  public.financeiro_contrato_modulos,
  public.financeiro_cobrancas,
  public.financeiro_cobranca_itens,
  public.financeiro_auditoria
to authenticated;

grant select, insert, update, delete on
  public.financeiro_apuracoes_loja,
  public.financeiro_modulos_acesso
to service_role;

-- 4) Catalogo inicial. Cada classificacao corresponde ao proprio modulo.
insert into public.financeiro_modulos_catalogo
  (codigo, nome, descricao, preco_padrao, incluido_plano_base, ativo)
values
  ('pedidos', 'Gestão de pedidos', 'Recebimento e gestão dos pedidos do App Mercado.', 0, true, true),
  ('consulta_preco', 'Consulta de preço', 'Consulta de preço, estoque e dados de compra.', 0, true, true),
  ('consulta_item', 'Consulta visual de item', 'Consulta visual com imagem ampliada.', 0, true, true),
  ('estoque_consumo_interno', 'Consumo interno', 'Registro de consumo interno da loja.', 0, true, true),
  ('loja_configuracoes', 'Configuração da loja', 'Dados, horários, entrega e aparência.', 0, true, true),
  ('cupons', 'Cupons', 'Criação e gestão de cupons de desconto.', 0, true, true),
  ('ofertas', 'Ofertas', 'Ofertas e destaques no App Mercado.', 0, true, true),
  ('peso_variavel', 'Peso variável', 'Produtos vendidos por peso.', 0, true, true),
  ('usuarios', 'Usuários', 'Usuários e permissões da loja.', 0, true, true),
  ('clientes_app', 'Clientes', 'Cadastros e bloqueios de clientes.', 0, true, true),
  ('relatorios', 'Relatórios', 'Indicadores e relatórios operacionais.', 0, true, true),
  ('produtos_inativos', 'Produtos inativos', 'Consulta de produtos inativos.', 10, false, true),
  ('alterar_preco', 'Alterar preço', 'Alteração de preço pela consulta.', 10, false, true),
  ('balanco', 'Coletor/Balanço', 'Coletas operacionais e arquivos TXT.', 10, false, true),
  ('lista_compras', 'Lista de compras', 'Compras por fornecedor e exportação Excel.', 10, false, true),
  ('conferencia_notas', 'Conferência NF-e', 'Conferência de notas fiscais de entrada.', 10, false, true),
  ('estoque', 'Estoque', 'Menu geral de estoque.', 10, false, true),
  ('estoque_entrada', 'Entrada de estoque', 'Registro de entradas.', 10, false, true),
  ('estoque_correcao', 'Correção de estoque', 'Correção de saldos.', 10, false, true),
  ('estoque_transferencia', 'Transferência entre estoques', 'Movimentação entre locais.', 10, false, true),
  ('estoque_baixa_avaria', 'Baixa por avaria', 'Baixa de produtos avariados.', 10, false, true),
  ('estoque_baixa_validade', 'Baixa por validade', 'Baixa de produtos vencidos.', 10, false, true),
  ('estoque_abrir_pacote', 'Abrir pacote / granel', 'Conversão de embalagem para granel.', 10, false, true),
  ('estoque_auditoria', 'Auditoria de estoque', 'Histórico de movimentações de estoque.', 10, false, true),
  ('produtos_app', 'Produtos app', 'Cadastro de produtos na base da loja.', 10, false, true),
  ('receitas', 'Receitas e produção', 'Fichas técnicas e produção.', 10, false, true),
  ('jornal_promocoes', 'Jornal de promoções', 'Criação e publicação de encartes.', 10, false, true),
  ('acoes_validade', 'Ações de validade', 'Descontos e alertas por validade.', 10, false, true)
on conflict (codigo) do update set
  nome = excluded.nome,
  descricao = excluded.descricao,
  incluido_plano_base = excluded.incluido_plano_base,
  ativo = excluded.ativo,
  atualizado_em = now();

-- 5) Funcoes internas de calculo.
create or replace function public.financeiro_exigir_master()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_master() then
    raise exception 'Acesso exclusivo do master central' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.financeiro_mensalidade_cheia(p_gmv numeric)
returns numeric
language sql
immutable
as $$
  select round(
    case
      when greatest(coalesce(p_gmv, 0), 0) <= 15000 then 159.90
      when p_gmv <= 30000 then 189.90
      when p_gmv <= 45000 then 219.90
      when p_gmv <= 60000 then 249.90
      when p_gmv <= 75000 then 279.90
      when p_gmv <= 90000 then 309.90
      when p_gmv <= 100000 then 339.90
      else 339.90 + ((p_gmv - 100000) * 0.0025)
    end,
    2
  );
$$;

create or replace function public.financeiro_dias_ativos(
  p_contrato_id uuid,
  p_competencia date
)
returns integer
language sql
stable
set search_path = public
as $$
  with limites as (
    select
      date_trunc('month', p_competencia)::date as inicio,
      (date_trunc('month', p_competencia) + interval '1 month - 1 day')::date as fim
  )
  select count(*)::integer
  from limites l,
       generate_series(l.inicio, l.fim, interval '1 day') dia
  where exists (
    select 1
    from public.financeiro_contrato_periodos periodo
    where periodo.contrato_id = p_contrato_id
      and dia::date >= periodo.inicio_em
      and dia::date <= coalesce(periodo.fim_em, 'infinity'::date)
  );
$$;

create or replace function public.financeiro_valor_modulos(
  p_contrato_id uuid,
  p_competencia date
)
returns numeric
language sql
stable
set search_path = public
as $$
  with limites as (
    select
      date_trunc('month', p_competencia)::date as inicio,
      (date_trunc('month', p_competencia) + interval '1 month - 1 day')::date as fim,
      extract(day from (date_trunc('month', p_competencia) + interval '1 month - 1 day'))::numeric as dias_mes
  ), valores as (
    select
      modulo.preco_mensal,
      greatest(modulo.vigencia_inicio, limites.inicio) as inicio,
      least(coalesce(modulo.vigencia_fim, limites.fim), limites.fim) as fim,
      limites.dias_mes
    from public.financeiro_contrato_modulos modulo
    cross join limites
    where modulo.contrato_id = p_contrato_id
      and modulo.ativo = true
      and modulo.vigencia_inicio <= limites.fim
      and coalesce(modulo.vigencia_fim, limites.fim) >= limites.inicio
  )
  select coalesce(round(sum(
    preco_mensal * ((fim - inicio + 1)::numeric / dias_mes)
  ), 2), 0)
  from valores;
$$;

create or replace function public.financeiro_situacao_acesso_interna(
  p_mercado_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contrato public.financeiro_contratos%rowtype;
  v_vencida boolean := false;
begin
  select * into v_contrato
  from public.financeiro_contratos
  where mercado_id = p_mercado_id;

  if not found then
    return jsonb_build_object(
      'situacao_acesso', 'SEM_CONTRATO',
      'permitir_pedidos', true,
      'permitir_demais_modulos', true,
      'mensagem', ''
    );
  end if;

  if v_contrato.status = 'CANCELADO' then
    return jsonb_build_object(
      'situacao_acesso', 'CANCELADO',
      'permitir_pedidos', false,
      'permitir_demais_modulos', false,
      'mensagem', 'Contrato cancelado. O acesso da loja está encerrado.'
    );
  end if;

  select exists (
    select 1
    from public.financeiro_cobrancas cobranca
    where cobranca.mercado_id = p_mercado_id
      and cobranca.status in ('EMITIDA', 'VENCIDA', 'NEGOCIADA')
      and cobranca.vencimento_em + v_contrato.dias_carencia <
          (now() at time zone 'America/Sao_Paulo')::date
      and cobranca.valor_total > 0
  ) into v_vencida;

  if v_vencida then
    return jsonb_build_object(
      'situacao_acesso', 'INADIMPLENTE',
      'permitir_pedidos', true,
      'permitir_demais_modulos', false,
      'mensagem', 'Acesso restrito por pendência financeira. O módulo de pedidos permanece disponível.'
    );
  end if;

  return jsonb_build_object(
    'situacao_acesso', v_contrato.status,
    'permitir_pedidos', true,
    'permitir_demais_modulos', true,
    'mensagem', ''
  );
end;
$$;

create or replace function public.financeiro_resumo_loja(
  p_mercado_id uuid,
  p_competencia date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_competencia date := date_trunc('month', p_competencia)::date;
  v_fim date := (date_trunc('month', p_competencia) + interval '1 month - 1 day')::date;
  v_dias_mes integer;
  v_contrato public.financeiro_contratos%rowtype;
  v_cobranca public.financeiro_cobrancas%rowtype;
  v_dias_ativos integer := 0;
  v_gmv numeric := 0;
  v_pedidos integer := 0;
  v_pedidos_andamento integer := 0;
  v_sincronizado_em timestamptz;
  v_sincronizacao_ok boolean := false;
  v_erro_sincronizacao text := '';
  v_ticket numeric := 0;
  v_fracao numeric := 0;
  v_equivalente numeric := 0;
  v_base numeric := 0;
  v_modulos numeric := 0;
  v_implantacao numeric := 0;
  v_total numeric := 0;
  v_proxima_faixa numeric;
  v_situacao jsonb;
begin
  v_dias_mes := extract(day from v_fim)::integer;

  select * into v_contrato
  from public.financeiro_contratos
  where mercado_id = p_mercado_id;

  if found then
    v_dias_ativos := public.financeiro_dias_ativos(v_contrato.id, v_competencia);
  end if;

  select
    coalesce(apuracao.gmv_elegivel, 0),
    coalesce(apuracao.pedidos_elegiveis, 0),
    coalesce(apuracao.pedidos_em_andamento, 0),
    apuracao.sincronizado_em,
    apuracao.sincronizacao_ok,
    coalesce(apuracao.erro_sincronizacao, '')
  into v_gmv, v_pedidos, v_pedidos_andamento,
       v_sincronizado_em, v_sincronizacao_ok, v_erro_sincronizacao
  from public.financeiro_apuracoes_loja apuracao
  where apuracao.mercado_id = p_mercado_id
    and apuracao.competencia = v_competencia;

  if not found then
    v_gmv := 0;
    v_pedidos := 0;
    v_pedidos_andamento := 0;
  end if;

  v_ticket := case when v_pedidos > 0 then round(v_gmv / v_pedidos, 2) else 0 end;
  v_fracao := case when v_dias_mes > 0 then v_dias_ativos::numeric / v_dias_mes else 0 end;
  v_equivalente := case when v_fracao > 0 then round(v_gmv / v_fracao, 2) else 0 end;

  if v_dias_ativos > 0 then
    v_base := round(public.financeiro_mensalidade_cheia(v_equivalente) * v_fracao, 2);
    v_modulos := public.financeiro_valor_modulos(v_contrato.id, v_competencia);
    if v_contrato.implantacao_competencia = v_competencia then
      v_implantacao := greatest(
        v_contrato.valor_implantacao - v_contrato.desconto_implantacao,
        0
      );
    end if;
  end if;

  v_total := round(v_base + v_modulos + v_implantacao, 2);

  select * into v_cobranca
  from public.financeiro_cobrancas
  where mercado_id = p_mercado_id
    and competencia = v_competencia;

  if found then
    v_dias_ativos := v_cobranca.dias_ativos;
    v_gmv := v_cobranca.gmv_elegivel;
    v_pedidos := v_cobranca.pedidos_elegiveis;
    v_ticket := v_cobranca.ticket_medio;
    v_equivalente := v_cobranca.faturamento_equivalente;
    v_base := v_cobranca.valor_plano_base;
    v_modulos := v_cobranca.valor_modulos;
    v_implantacao := v_cobranca.valor_implantacao;
    v_total := v_cobranca.valor_total;
  end if;

  v_proxima_faixa := case
    when v_equivalente < 15000 then 15000
    when v_equivalente < 30000 then 30000
    when v_equivalente < 45000 then 45000
    when v_equivalente < 60000 then 60000
    when v_equivalente < 75000 then 75000
    when v_equivalente < 90000 then 90000
    when v_equivalente < 100000 then 100000
    else null
  end;

  v_situacao := public.financeiro_situacao_acesso_interna(p_mercado_id);

  return jsonb_build_object(
    'competencia', v_competencia,
    'periodo_fim', v_fim,
    'dias_no_mes', v_dias_mes,
    'dias_ativos', v_dias_ativos,
    'gmv_elegivel', v_gmv,
    'pedidos_elegiveis', v_pedidos,
    'pedidos_em_andamento', v_pedidos_andamento,
    'sincronizado_em', v_sincronizado_em,
    'sincronizacao_ok', v_sincronizacao_ok,
    'erro_sincronizacao', v_erro_sincronizacao,
    'ticket_medio', v_ticket,
    'faturamento_equivalente', v_equivalente,
    'mensalidade_base', v_base,
    'modulos_adicionais', v_modulos,
    'implantacao', v_implantacao,
    'total_estimado', v_total,
    'proxima_faixa', v_proxima_faixa,
    'falta_proxima_faixa', case
      when v_proxima_faixa is null then 0
      else greatest(v_proxima_faixa - v_equivalente, 0)
    end,
    'cobranca_id', case when v_cobranca.id is null then null else v_cobranca.id end,
    'status_cobranca', case when v_cobranca.id is null then 'EM_APURACAO' else v_cobranca.status end,
    'situacao_acesso', v_situacao ->> 'situacao_acesso',
    'permitir_pedidos', coalesce((v_situacao ->> 'permitir_pedidos')::boolean, true),
    'permitir_demais_modulos', coalesce((v_situacao ->> 'permitir_demais_modulos')::boolean, true)
  );
end;
$$;

-- 6) RPC de acesso operacional. Somente a Edge Function central usa esta RPC;
-- o aplicativo nunca recebe permissao direta sobre as tabelas financeiras.
create or replace function public.financeiro_acesso_loja(p_mercado_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.financeiro_situacao_acesso_interna(p_mercado_id);
end;
$$;

revoke all on function public.financeiro_acesso_loja(uuid) from public, anon, authenticated;
grant execute on function public.financeiro_acesso_loja(uuid) to service_role;

-- 7) Dashboard e detalhe, sempre exclusivos do master.
create or replace function public.financeiro_master_dashboard(p_competencia date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lojas jsonb;
  v_modulos jsonb;
  v_totais jsonb;
begin
  perform public.financeiro_exigir_master();

  update public.financeiro_cobrancas
     set status = 'VENCIDA',
         atualizado_em = now(),
         atualizado_por = auth.uid()
   where status = 'EMITIDA'
     and vencimento_em < (now() at time zone 'America/Sao_Paulo')::date;

  with resumos as (
    select
      mercado.id as mercado_id,
      mercado.nome as mercado_nome,
      mercado.codigo as mercado_codigo,
      mercado.ativo as mercado_ativo,
      public.financeiro_resumo_loja(mercado.id, p_competencia) as resumo
    from public.mercados mercado
    order by mercado.nome
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'mercado_id', mercado_id,
      'mercado_nome', mercado_nome,
      'mercado_codigo', mercado_codigo,
      'mercado_ativo', mercado_ativo
    ) || resumo
  ), '[]'::jsonb)
  into v_lojas
  from resumos;

  select coalesce(jsonb_agg(to_jsonb(modulo) order by modulo.nome), '[]'::jsonb)
  into v_modulos
  from public.financeiro_modulos_catalogo modulo;

  with itens as (
    select value as loja
    from jsonb_array_elements(v_lojas)
  )
  select jsonb_build_object(
    'gmv_elegivel', coalesce(sum((loja ->> 'gmv_elegivel')::numeric), 0),
    'total_estimado', coalesce(sum((loja ->> 'total_estimado')::numeric), 0),
    'pedidos_elegiveis', coalesce(sum((loja ->> 'pedidos_elegiveis')::integer), 0),
    'lojas_em_atraso', count(*) filter (where loja ->> 'situacao_acesso' = 'INADIMPLENTE')
  )
  into v_totais
  from itens;

  return jsonb_build_object(
    'competencia', date_trunc('month', p_competencia)::date,
    'lojas', v_lojas,
    'modulos', v_modulos,
    'totais', coalesce(v_totais, '{}'::jsonb)
  );
end;
$$;

create or replace function public.financeiro_master_detalhe_loja(
  p_mercado_id uuid,
  p_competencia date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contrato public.financeiro_contratos%rowtype;
  v_contrato_json jsonb;
  v_modulos jsonb;
  v_cobrancas jsonb;
begin
  perform public.financeiro_exigir_master();

  select * into v_contrato
  from public.financeiro_contratos
  where mercado_id = p_mercado_id;

  if found then
    v_contrato_json := to_jsonb(v_contrato) || jsonb_build_object(
      'valor_implantacao_liquido', greatest(
        v_contrato.valor_implantacao - v_contrato.desconto_implantacao,
        0
      )
    );
  else
    v_contrato_json := null;
  end if;

  select coalesce(jsonb_agg(item order by item ->> 'nome'), '[]'::jsonb)
  into v_modulos
  from (
    select to_jsonb(catalogo) || jsonb_build_object(
      'contratado', coalesce(vigente.ativo, false),
      'preco_contratado', vigente.preco_mensal,
      'vigencia_inicio', vigente.vigencia_inicio,
      'vigencia_fim', vigente.vigencia_fim,
      'motivo_contratacao', vigente.motivo
    ) as item
    from public.financeiro_modulos_catalogo catalogo
    left join lateral (
      select historico.*
      from public.financeiro_contrato_modulos historico
      where historico.contrato_id = v_contrato.id
        and historico.modulo_id = catalogo.id
      order by historico.vigencia_inicio desc, historico.criado_em desc
      limit 1
    ) vigente on true
    where catalogo.ativo = true
  ) dados_modulos;

  select coalesce(jsonb_agg(
    to_jsonb(cobranca) || jsonb_build_object(
      'competencia_texto', to_char(cobranca.competencia, 'MM/YYYY')
    ) order by cobranca.competencia desc
  ), '[]'::jsonb)
  into v_cobrancas
  from (
    select *
    from public.financeiro_cobrancas
    where mercado_id = p_mercado_id
    order by competencia desc
    limit 24
  ) cobranca;

  return jsonb_build_object(
    'contrato', v_contrato_json,
    'resumo', public.financeiro_resumo_loja(p_mercado_id, p_competencia),
    'modulos', v_modulos,
    'cobrancas', v_cobrancas
  );
end;
$$;

-- 8) Cadastro de contrato e catalogo.
create or replace function public.financeiro_master_salvar_contrato(
  p_mercado_id uuid,
  p_inicio date,
  p_status text,
  p_tipo_implantacao text,
  p_valor_implantacao numeric,
  p_desconto_implantacao numeric,
  p_observacao text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes jsonb;
  v_contrato public.financeiro_contratos%rowtype;
begin
  perform public.financeiro_exigir_master();

  if p_status not in ('RASCUNHO', 'ATIVO') then
    raise exception 'Status de contrato invalido';
  end if;
  if p_tipo_implantacao not in (
    'SEM_IMPLANTACAO', 'ERP_INTEGRADO', 'ERP_NOVO', 'SOB_ORCAMENTO'
  ) then
    raise exception 'Tipo de implantacao invalido';
  end if;
  if coalesce(p_valor_implantacao, 0) < 0
     or coalesce(p_desconto_implantacao, 0) < 0
     or coalesce(p_desconto_implantacao, 0) > coalesce(p_valor_implantacao, 0) then
    raise exception 'Valores de implantacao invalidos';
  end if;

  select to_jsonb(contrato) into v_antes
  from public.financeiro_contratos contrato
  where mercado_id = p_mercado_id;

  insert into public.financeiro_contratos (
    mercado_id, status, inicio_em, tipo_implantacao,
    valor_implantacao, desconto_implantacao, implantacao_competencia,
    observacao, criado_por, atualizado_por
  ) values (
    p_mercado_id, p_status, p_inicio, p_tipo_implantacao,
    coalesce(p_valor_implantacao, 0), coalesce(p_desconto_implantacao, 0),
    date_trunc('month', p_inicio)::date,
    coalesce(p_observacao, ''), auth.uid(), auth.uid()
  )
  on conflict (mercado_id) do update set
    status = excluded.status,
    inicio_em = excluded.inicio_em,
    tipo_implantacao = excluded.tipo_implantacao,
    valor_implantacao = excluded.valor_implantacao,
    desconto_implantacao = excluded.desconto_implantacao,
    implantacao_competencia = case
      when financeiro_contratos.implantacao_competencia is null
        then excluded.implantacao_competencia
      else financeiro_contratos.implantacao_competencia
    end,
    observacao = excluded.observacao,
    atualizado_em = now(),
    atualizado_por = auth.uid()
  returning * into v_contrato;

  if p_status = 'ATIVO' and not exists (
    select 1
    from public.financeiro_contrato_periodos periodo
    where periodo.contrato_id = v_contrato.id
      and periodo.fim_em is null
  ) then
    insert into public.financeiro_contrato_periodos (
      contrato_id, inicio_em, motivo, criado_por
    ) values (
      v_contrato.id, p_inicio, 'Ativação do contrato', auth.uid()
    );
  end if;

  if p_status = 'RASCUNHO' then
    update public.financeiro_contrato_periodos
       set fim_em = greatest(p_inicio - 1, inicio_em)
     where contrato_id = v_contrato.id
       and fim_em is null;
  end if;

  if p_status = 'ATIVO' then
    update public.mercados set ativo = true where id = p_mercado_id;

    insert into public.financeiro_modulos_acesso (
      mercado_id, modulo_codigo, permitido, atualizado_por
    )
    select p_mercado_id, modulo.codigo, true, auth.uid()
    from public.financeiro_modulos_catalogo modulo
    where modulo.incluido_plano_base = true
      and modulo.ativo = true
    on conflict (mercado_id, modulo_codigo) do update set
      permitido = true,
      atualizado_em = now(),
      atualizado_por = auth.uid();
  end if;

  insert into public.financeiro_auditoria (
    mercado_id, entidade, entidade_id, acao, motivo,
    dados_antes, dados_depois, usuario_id, usuario_email
  ) values (
    p_mercado_id, 'CONTRATO', v_contrato.id, 'SALVAR',
    coalesce(p_observacao, ''), v_antes, to_jsonb(v_contrato),
    auth.uid(), auth.jwt() ->> 'email'
  );

  return jsonb_build_object('contrato', to_jsonb(v_contrato));
end;
$$;

create or replace function public.financeiro_master_salvar_modulo(
  p_id uuid,
  p_codigo text,
  p_nome text,
  p_descricao text,
  p_preco_padrao numeric,
  p_incluido_plano_base boolean,
  p_ativo boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_modulo public.financeiro_modulos_catalogo%rowtype;
  v_antes jsonb;
begin
  perform public.financeiro_exigir_master();

  if trim(coalesce(p_codigo, '')) = '' or trim(coalesce(p_nome, '')) = '' then
    raise exception 'Codigo e nome sao obrigatorios';
  end if;
  if coalesce(p_preco_padrao, 0) < 0 then
    raise exception 'Preco invalido';
  end if;

  if p_id is null then
    insert into public.financeiro_modulos_catalogo (
      codigo, nome, descricao, preco_padrao, incluido_plano_base,
      ativo, atualizado_por
    ) values (
      lower(trim(p_codigo)), trim(p_nome), coalesce(p_descricao, ''),
      coalesce(p_preco_padrao, 0), coalesce(p_incluido_plano_base, false),
      coalesce(p_ativo, true), auth.uid()
    ) returning * into v_modulo;
  else
    select to_jsonb(modulo) into v_antes
    from public.financeiro_modulos_catalogo modulo
    where id = p_id;

    update public.financeiro_modulos_catalogo
       set nome = trim(p_nome),
           descricao = coalesce(p_descricao, ''),
           preco_padrao = coalesce(p_preco_padrao, 0),
           incluido_plano_base = coalesce(p_incluido_plano_base, false),
           ativo = coalesce(p_ativo, true),
           atualizado_em = now(),
           atualizado_por = auth.uid()
     where id = p_id
     returning * into v_modulo;
  end if;

  if v_modulo.id is null then
    raise exception 'Modulo nao encontrado';
  end if;

  insert into public.financeiro_auditoria (
    entidade, entidade_id, acao, motivo, dados_antes, dados_depois,
    usuario_id, usuario_email
  ) values (
    'MODULO_CATALOGO', v_modulo.id, 'SALVAR', '', v_antes,
    to_jsonb(v_modulo), auth.uid(), auth.jwt() ->> 'email'
  );

  return jsonb_build_object('modulo', to_jsonb(v_modulo));
end;
$$;

create or replace function public.financeiro_master_salvar_modulo_loja(
  p_mercado_id uuid,
  p_modulo_id uuid,
  p_ativo boolean,
  p_preco_mensal numeric,
  p_vigencia_inicio date,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contrato public.financeiro_contratos%rowtype;
  v_modulo public.financeiro_modulos_catalogo%rowtype;
  v_registro public.financeiro_contrato_modulos%rowtype;
begin
  perform public.financeiro_exigir_master();

  if trim(coalesce(p_motivo, '')) = '' then
    raise exception 'Informe o motivo ou a condicao negociada';
  end if;
  if coalesce(p_preco_mensal, 0) < 0 then
    raise exception 'Preco mensal invalido';
  end if;

  select * into v_contrato
  from public.financeiro_contratos
  where mercado_id = p_mercado_id;
  if not found then
    raise exception 'Configure o contrato da loja antes dos modulos';
  end if;

  select * into v_modulo
  from public.financeiro_modulos_catalogo
  where id = p_modulo_id;
  if not found or v_modulo.incluido_plano_base then
    raise exception 'Modulo adicional invalido';
  end if;

  update public.financeiro_contrato_modulos
     set vigencia_fim = greatest(p_vigencia_inicio - 1, vigencia_inicio)
   where contrato_id = v_contrato.id
     and modulo_id = p_modulo_id
     and vigencia_fim is null;

  insert into public.financeiro_contrato_modulos (
    contrato_id, modulo_id, ativo, preco_mensal,
    vigencia_inicio, motivo, criado_por
  ) values (
    v_contrato.id, p_modulo_id, coalesce(p_ativo, false),
    coalesce(p_preco_mensal, v_modulo.preco_padrao),
    p_vigencia_inicio, trim(p_motivo), auth.uid()
  ) returning * into v_registro;

  insert into public.financeiro_modulos_acesso (
    mercado_id, modulo_codigo, permitido, atualizado_por
  ) values (
    p_mercado_id, v_modulo.codigo, coalesce(p_ativo, false), auth.uid()
  )
  on conflict (mercado_id, modulo_codigo) do update set
    permitido = excluded.permitido,
    atualizado_em = now(),
    atualizado_por = auth.uid();

  insert into public.financeiro_auditoria (
    mercado_id, entidade, entidade_id, acao, motivo,
    dados_depois, usuario_id, usuario_email
  ) values (
    p_mercado_id, 'CONTRATO_MODULO', v_registro.id,
    case when p_ativo then 'ATIVAR' else 'DESATIVAR' end,
    trim(p_motivo), to_jsonb(v_registro), auth.uid(), auth.jwt() ->> 'email'
  );

  return jsonb_build_object('modulo_contrato', to_jsonb(v_registro));
end;
$$;

-- 9) Fechamento: cria um snapshot imutavel do valor calculado.
create or replace function public.financeiro_criar_cobranca_loja_interna(
  p_mercado_id uuid,
  p_competencia date,
  p_criado_por uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_competencia date := date_trunc('month', p_competencia)::date;
  v_fim date := (date_trunc('month', p_competencia) + interval '1 month - 1 day')::date;
  v_contrato public.financeiro_contratos%rowtype;
  v_resumo jsonb;
  v_cobranca_id uuid;
  v_vencimento date;
begin
  select * into v_contrato
  from public.financeiro_contratos
  where mercado_id = p_mercado_id;

  if not found or public.financeiro_dias_ativos(v_contrato.id, v_competencia) = 0 then
    return null;
  end if;

  select id into v_cobranca_id
  from public.financeiro_cobrancas
  where mercado_id = p_mercado_id
    and competencia = v_competencia;

  if v_cobranca_id is not null then
    return v_cobranca_id;
  end if;

  v_resumo := public.financeiro_resumo_loja(p_mercado_id, v_competencia);
  v_vencimento := (
    date_trunc('month', v_competencia) + interval '1 month'
    + make_interval(days => v_contrato.dia_vencimento - 1)
  )::date;

  insert into public.financeiro_cobrancas (
    contrato_id, mercado_id, competencia, periodo_inicio, periodo_fim,
    dias_ativos, dias_no_mes, gmv_elegivel, pedidos_elegiveis,
    ticket_medio, faturamento_equivalente, valor_plano_base,
    valor_modulos, valor_implantacao, valor_ajustes, valor_total,
    status, vencimento_em, criado_por, atualizado_por
  ) values (
    v_contrato.id, p_mercado_id, v_competencia, v_competencia, v_fim,
    (v_resumo ->> 'dias_ativos')::integer,
    (v_resumo ->> 'dias_no_mes')::integer,
    (v_resumo ->> 'gmv_elegivel')::numeric,
    (v_resumo ->> 'pedidos_elegiveis')::integer,
    (v_resumo ->> 'ticket_medio')::numeric,
    (v_resumo ->> 'faturamento_equivalente')::numeric,
    (v_resumo ->> 'mensalidade_base')::numeric,
    (v_resumo ->> 'modulos_adicionais')::numeric,
    (v_resumo ->> 'implantacao')::numeric,
    0,
    (v_resumo ->> 'total_estimado')::numeric,
    'AGUARDANDO_EMISSAO', v_vencimento, p_criado_por, p_criado_por
  ) returning id into v_cobranca_id;

  insert into public.financeiro_cobranca_itens (
    cobranca_id, tipo, codigo, descricao, quantidade,
    valor_unitario, valor_total, detalhes
  ) values (
    v_cobranca_id, 'PLANO_BASE', 'app_mercado',
    'Assinatura App Mercado', 1,
    (v_resumo ->> 'mensalidade_base')::numeric,
    (v_resumo ->> 'mensalidade_base')::numeric,
    jsonb_build_object(
      'gmv_elegivel', v_resumo -> 'gmv_elegivel',
      'faturamento_equivalente', v_resumo -> 'faturamento_equivalente',
      'dias_ativos', v_resumo -> 'dias_ativos',
      'dias_no_mes', v_resumo -> 'dias_no_mes'
    )
  );

  insert into public.financeiro_cobranca_itens (
    cobranca_id, tipo, codigo, descricao, quantidade,
    valor_unitario, valor_total
  )
  select
    v_cobranca_id, 'MODULO', catalogo.codigo, catalogo.nome, 1,
    round(historico.preco_mensal * (
      (least(coalesce(historico.vigencia_fim, v_fim), v_fim)
       - greatest(historico.vigencia_inicio, v_competencia) + 1)::numeric
      / (extract(day from v_fim)::numeric)
    ), 2),
    round(historico.preco_mensal * (
      (least(coalesce(historico.vigencia_fim, v_fim), v_fim)
       - greatest(historico.vigencia_inicio, v_competencia) + 1)::numeric
      / (extract(day from v_fim)::numeric)
    ), 2)
  from public.financeiro_contrato_modulos historico
  join public.financeiro_modulos_catalogo catalogo on catalogo.id = historico.modulo_id
  where historico.contrato_id = v_contrato.id
    and historico.ativo = true
    and historico.vigencia_inicio <= v_fim
    and coalesce(historico.vigencia_fim, v_fim) >= v_competencia;

  if (v_resumo ->> 'implantacao')::numeric > 0 then
    insert into public.financeiro_cobranca_itens (
      cobranca_id, tipo, codigo, descricao, quantidade,
      valor_unitario, valor_total, detalhes
    ) values (
      v_cobranca_id, 'IMPLANTACAO', lower(v_contrato.tipo_implantacao),
      'Taxa de implantação', 1,
      (v_resumo ->> 'implantacao')::numeric,
      (v_resumo ->> 'implantacao')::numeric,
      jsonb_build_object(
        'valor_original', v_contrato.valor_implantacao,
        'desconto', v_contrato.desconto_implantacao,
        'tipo', v_contrato.tipo_implantacao
      )
    );
  end if;

  return v_cobranca_id;
end;
$$;

create or replace function public.financeiro_fechar_competencia_interna(
  p_competencia date,
  p_criado_por uuid default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contrato record;
  v_quantidade integer := 0;
begin
  for v_contrato in
    select contrato.id, contrato.mercado_id
    from public.financeiro_contratos contrato
    where exists (
      select 1
      from public.financeiro_contrato_periodos periodo
      where periodo.contrato_id = contrato.id
        and periodo.inicio_em <= (date_trunc('month', p_competencia) + interval '1 month - 1 day')::date
        and coalesce(periodo.fim_em, 'infinity'::date) >= date_trunc('month', p_competencia)::date
    )
  loop
    if public.financeiro_criar_cobranca_loja_interna(
      v_contrato.mercado_id,
      p_competencia,
      p_criado_por
    ) is not null then
      v_quantidade := v_quantidade + 1;
    end if;
  end loop;

  return v_quantidade;
end;
$$;

create or replace function public.financeiro_master_fechar_competencia(
  p_competencia date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quantidade integer;
begin
  perform public.financeiro_exigir_master();
  v_quantidade := public.financeiro_fechar_competencia_interna(
    p_competencia,
    auth.uid()
  );

  insert into public.financeiro_auditoria (
    entidade, acao, motivo, dados_depois, usuario_id, usuario_email
  ) values (
    'COMPETENCIA', 'FECHAR', to_char(p_competencia, 'MM/YYYY'),
    jsonb_build_object('quantidade', v_quantidade),
    auth.uid(), auth.jwt() ->> 'email'
  );

  return jsonb_build_object('quantidade', v_quantidade);
end;
$$;

create or replace function public.financeiro_fechar_mes_anterior_automatico()
returns integer
language sql
security definer
set search_path = public
as $$
  select public.financeiro_fechar_competencia_interna(
    (date_trunc('month', now() at time zone 'America/Sao_Paulo') - interval '1 month')::date,
    null
  );
$$;

revoke all on function public.financeiro_fechar_mes_anterior_automatico() from public, anon, authenticated;
grant execute on function public.financeiro_fechar_mes_anterior_automatico() to service_role;

-- Agenda o fechamento para 03:05 UTC do primeiro dia de cada mes (00:05 em Brasilia).
-- Se pg_cron nao estiver habilitado, o fechamento continua disponivel pelo botao no app.
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    begin
      perform cron.unschedule('financeiro-fechamento-mensal');
    exception when others then
      null;
    end;

    perform cron.schedule(
      'financeiro-fechamento-mensal',
      '5 3 1 * *',
      'select public.financeiro_fechar_mes_anterior_automatico();'
    );
  end if;
exception when others then
  raise notice 'pg_cron indisponivel; use o fechamento manual pelo app: %', sqlerrm;
end;
$$;

-- 10) Operacoes manuais do master.
create or replace function public.financeiro_master_atualizar_cobranca(
  p_cobranca_id uuid,
  p_status text,
  p_referencia text default '',
  p_pago_em timestamptz default null,
  p_forma_pagamento text default '',
  p_observacao text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes jsonb;
  v_cobranca public.financeiro_cobrancas%rowtype;
begin
  perform public.financeiro_exigir_master();

  if p_status not in (
    'AGUARDANDO_EMISSAO', 'EMITIDA', 'PAGA',
    'VENCIDA', 'NEGOCIADA', 'CANCELADA'
  ) then
    raise exception 'Status de cobranca invalido';
  end if;

  select to_jsonb(cobranca) into v_antes
  from public.financeiro_cobrancas cobranca
  where id = p_cobranca_id;

  update public.financeiro_cobrancas
     set status = p_status,
         referencia = coalesce(p_referencia, ''),
         pago_em = case
           when p_status = 'PAGA' then coalesce(p_pago_em, now())
           else null
         end,
         forma_pagamento = coalesce(p_forma_pagamento, ''),
         observacao = coalesce(p_observacao, ''),
         atualizado_em = now(),
         atualizado_por = auth.uid()
   where id = p_cobranca_id
   returning * into v_cobranca;

  if v_cobranca.id is null then
    raise exception 'Cobranca nao encontrada';
  end if;

  insert into public.financeiro_auditoria (
    mercado_id, entidade, entidade_id, acao, motivo,
    dados_antes, dados_depois, usuario_id, usuario_email
  ) values (
    v_cobranca.mercado_id, 'COBRANCA', v_cobranca.id,
    'ALTERAR_STATUS', coalesce(p_observacao, ''), v_antes,
    to_jsonb(v_cobranca), auth.uid(), auth.jwt() ->> 'email'
  );

  return jsonb_build_object('cobranca', to_jsonb(v_cobranca));
end;
$$;

create or replace function public.financeiro_master_cancelar_loja(
  p_mercado_id uuid,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contrato public.financeiro_contratos%rowtype;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_pedidos integer;
  v_sincronizado_em timestamptz;
  v_sincronizacao_ok boolean;
  v_cobranca_id uuid;
begin
  perform public.financeiro_exigir_master();

  if trim(coalesce(p_motivo, '')) = '' then
    raise exception 'Informe o motivo do cancelamento';
  end if;

  select * into v_contrato
  from public.financeiro_contratos
  where mercado_id = p_mercado_id
  for update;

  if not found then
    raise exception 'Contrato nao encontrado';
  end if;
  if v_contrato.status = 'CANCELADO' then
    raise exception 'Este contrato ja esta cancelado';
  end if;

  select apuracao.pedidos_em_andamento, apuracao.sincronizado_em,
         apuracao.sincronizacao_ok
  into v_pedidos, v_sincronizado_em, v_sincronizacao_ok
  from public.financeiro_apuracoes_loja apuracao
  where apuracao.mercado_id = p_mercado_id
    and apuracao.competencia = date_trunc('month', v_hoje)::date;

  if not found or not coalesce(v_sincronizacao_ok, false)
     or v_sincronizado_em < now() - interval '10 minutes' then
    raise exception 'Sincronize os pedidos da loja antes de cancelar o contrato';
  end if;

  if v_pedidos > 0 then
    raise exception 'Cancelamento impedido: existem % pedido(s) em andamento', v_pedidos;
  end if;

  update public.financeiro_contrato_periodos
     set fim_em = v_hoje
   where contrato_id = v_contrato.id
     and fim_em is null;

  update public.financeiro_contratos
     set status = 'CANCELADO',
         cancelado_em = v_hoje,
         observacao = concat_ws(E'\n', nullif(observacao, ''), trim(p_motivo)),
         atualizado_em = now(),
         atualizado_por = auth.uid()
   where id = v_contrato.id
   returning * into v_contrato;

  v_cobranca_id := public.financeiro_criar_cobranca_loja_interna(
    p_mercado_id,
    date_trunc('month', v_hoje)::date,
    auth.uid()
  );

  update public.mercados
     set ativo = false
   where id = p_mercado_id;

  update public.financeiro_modulos_acesso
     set permitido = false,
         atualizado_em = now(),
         atualizado_por = auth.uid()
   where mercado_id = p_mercado_id;

  insert into public.financeiro_auditoria (
    mercado_id, entidade, entidade_id, acao, motivo,
    dados_depois, usuario_id, usuario_email
  ) values (
    p_mercado_id, 'CONTRATO', v_contrato.id, 'CANCELAR', trim(p_motivo),
    jsonb_build_object('contrato', to_jsonb(v_contrato), 'cobranca_id', v_cobranca_id),
    auth.uid(), auth.jwt() ->> 'email'
  );

  return jsonb_build_object(
    'contrato', to_jsonb(v_contrato),
    'cobranca_id', v_cobranca_id
  );
end;
$$;

drop function if exists public.financeiro_master_reativar_loja(uuid, date, text);

create or replace function public.financeiro_master_reativar_loja(
  p_mercado_id uuid,
  p_data date,
  p_motivo text,
  p_modulos_ids uuid[] default '{}'::uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contrato public.financeiro_contratos%rowtype;
  v_pendencias integer;
  v_modulo record;
begin
  perform public.financeiro_exigir_master();

  if trim(coalesce(p_motivo, '')) = '' then
    raise exception 'Informe o motivo da reativacao';
  end if;

  select * into v_contrato
  from public.financeiro_contratos
  where mercado_id = p_mercado_id
  for update;

  if not found or v_contrato.status <> 'CANCELADO' then
    raise exception 'A loja nao possui contrato cancelado';
  end if;

  select count(*)::integer into v_pendencias
  from public.financeiro_cobrancas
  where mercado_id = p_mercado_id
    and status not in ('PAGA', 'CANCELADA')
    and valor_total > 0;

  if v_pendencias > 0 then
    raise exception 'Reativacao impedida: quite todas as cobrancas pendentes';
  end if;

  update public.financeiro_contratos
     set status = 'ATIVO',
         cancelado_em = null,
         atualizado_em = now(),
         atualizado_por = auth.uid()
   where id = v_contrato.id
   returning * into v_contrato;

  insert into public.financeiro_contrato_periodos (
    contrato_id, inicio_em, motivo, criado_por
  ) values (
    v_contrato.id, p_data, trim(p_motivo), auth.uid()
  );

  update public.financeiro_contrato_modulos
     set vigencia_fim = greatest(p_data - 1, vigencia_inicio)
   where contrato_id = v_contrato.id
     and vigencia_fim is null;

  for v_modulo in
    select
      catalogo.id,
      coalesce((
        select historico.preco_mensal
        from public.financeiro_contrato_modulos historico
        where historico.contrato_id = v_contrato.id
          and historico.modulo_id = catalogo.id
        order by historico.vigencia_inicio desc, historico.criado_em desc
        limit 1
      ), catalogo.preco_padrao) as preco_mensal
    from public.financeiro_modulos_catalogo catalogo
    where catalogo.id = any(coalesce(p_modulos_ids, '{}'::uuid[]))
      and catalogo.ativo = true
      and catalogo.incluido_plano_base = false
  loop
    insert into public.financeiro_contrato_modulos (
      contrato_id, modulo_id, ativo, preco_mensal,
      vigencia_inicio, motivo, criado_por
    ) values (
      v_contrato.id, v_modulo.id, true, v_modulo.preco_mensal,
      p_data, trim(p_motivo), auth.uid()
    );
  end loop;

  update public.mercados set ativo = true where id = p_mercado_id;

  insert into public.financeiro_modulos_acesso (
    mercado_id, modulo_codigo, permitido, atualizado_por
  )
  select p_mercado_id, catalogo.codigo, true, auth.uid()
  from public.financeiro_modulos_catalogo catalogo
  where catalogo.ativo = true
    and (
      catalogo.incluido_plano_base = true
      or exists (
        select 1
        from public.financeiro_contrato_modulos contratado
        where contratado.contrato_id = v_contrato.id
          and contratado.modulo_id = catalogo.id
          and contratado.ativo = true
          and contratado.vigencia_inicio <= p_data
          and coalesce(contratado.vigencia_fim, 'infinity'::date) >= p_data
      )
    )
  on conflict (mercado_id, modulo_codigo) do update set
    permitido = true,
    atualizado_em = now(),
    atualizado_por = auth.uid();

  insert into public.financeiro_auditoria (
    mercado_id, entidade, entidade_id, acao, motivo,
    dados_depois, usuario_id, usuario_email
  ) values (
    p_mercado_id, 'CONTRATO', v_contrato.id, 'REATIVAR', trim(p_motivo),
    to_jsonb(v_contrato), auth.uid(), auth.jwt() ->> 'email'
  );

  return jsonb_build_object('contrato', to_jsonb(v_contrato));
end;
$$;

-- 11) Permissoes das RPCs. A seguranca real continua dentro de cada funcao.
grant execute on function public.financeiro_master_dashboard(date) to authenticated;
grant execute on function public.financeiro_master_detalhe_loja(uuid, date) to authenticated;
grant execute on function public.financeiro_master_salvar_contrato(uuid, date, text, text, numeric, numeric, text) to authenticated;
grant execute on function public.financeiro_master_salvar_modulo(uuid, text, text, text, numeric, boolean, boolean) to authenticated;
grant execute on function public.financeiro_master_salvar_modulo_loja(uuid, uuid, boolean, numeric, date, text) to authenticated;
grant execute on function public.financeiro_master_fechar_competencia(date) to authenticated;
grant execute on function public.financeiro_master_atualizar_cobranca(uuid, text, text, timestamptz, text, text) to authenticated;
grant execute on function public.financeiro_master_cancelar_loja(uuid, text) to authenticated;
grant execute on function public.financeiro_master_reativar_loja(uuid, date, text, uuid[]) to authenticated;

revoke all on function public.financeiro_exigir_master() from public, anon;
revoke all on function public.financeiro_criar_cobranca_loja_interna(uuid, date, uuid) from public, anon, authenticated;
revoke all on function public.financeiro_fechar_competencia_interna(date, uuid) from public, anon, authenticated;
revoke all on function public.financeiro_situacao_acesso_interna(uuid) from public, anon, authenticated;

commit;

-- Conferencia: todas as colunas devem retornar true.
select
  to_regclass('public.financeiro_apuracoes_loja') is not null as apuracoes_prontas,
  to_regclass('public.financeiro_modulos_acesso') is not null as modulos_acesso_prontos,
  to_regclass('public.financeiro_contratos') is not null as contratos_prontos,
  to_regclass('public.financeiro_cobrancas') is not null as cobrancas_prontas,
  to_regprocedure('public.financeiro_master_dashboard(date)') is not null as painel_pronto,
  to_regprocedure('public.financeiro_acesso_loja(uuid)') is not null as acesso_pronto;

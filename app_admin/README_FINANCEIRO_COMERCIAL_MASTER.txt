MODULO FINANCEIRO E COMERCIAL - PRIMEIRA VERSAO
================================================

1. BANCO CENTRAL

Execute uma unica vez, no SQL Editor da base Supabase central:

  SQL_FINANCEIRO_COMERCIAL_MASTER.sql

Ao final, a consulta de conferencia deve retornar seis colunas com true:

  apuracoes_prontas
  modulos_acesso_prontos
  contratos_prontos
  cobrancas_prontas
  painel_pronto
  acesso_pronto

O script usa diretamente apenas a tabela mercados da base central. Pedidos,
usuarios e liberacoes operacionais continuam nas bases das lojas. Nao execute
este SQL nas bases das lojas.

2. EDGE FUNCTIONS DA CENTRAL

Depois do SQL, publique estas duas funcoes do projeto supabase_admin_central:

  financeiro-master
  validar-mercado-ativo

A financeiro-master usa as conexoes ja cadastradas no Supabase central para
consultar cada loja com a service_role e salvar somente o resumo mensal na
tabela central financeiro_apuracoes_loja. As chaves das lojas nao vao para o
aplicativo.

3. ACESSO

Entre no App Admin com a conta master central e abra:

  Admin Geral > Financeiro e comercial

Ao abrir ou atualizar o painel, a Edge Function sincroniza o faturamento das
lojas. Lojas sem contrato continuam funcionando normalmente. Abra uma loja no
painel e configure a data de inicio, implantacao e status Ativo para iniciar a
apuracao.

4. REGRAS IMPLANTADAS

- cobranca separada por mercado_id;
- competencia do primeiro ao ultimo dia do mes em America/Sao_Paulo;
- vencimento no dia 10;
- valores fixos ate R$ 100 mil e 0,25% somente sobre o excedente;
- primeira, ultima e reativacao proporcionais aos dias ativos;
- taxa de implantacao integral de R$ 590 ou R$ 990, com edicao pelo master;
- modulos adicionais a R$ 10 por padrao, com preco negociado por loja;
- fechamento em snapshot, sem recalculo silencioso;
- emissao e baixa de pagamento manuais pelo master;
- apos 15 dias de atraso, somente Gestao de Pedidos permanece liberada;
- cancelamento impedido enquanto houver pedidos em andamento;
- cancelamento desativa a loja e gera cobranca proporcional final;
- reativacao somente sem cobrancas pendentes e sem nova implantacao;
- dados financeiros protegidos por RLS e public.is_master();
- historico de alteracoes na tabela financeiro_auditoria.

5. FECHAMENTO AUTOMATICO

Quando pg_cron estiver habilitado, o script agenda o fechamento do mes anterior
para 00:05 (horario de Brasilia) no primeiro dia do mes. Para o fechamento
automatico refletir dados novos, agende tambem uma chamada autenticada da Edge
Function antes do horario, ou use o botao Fechar competencia no painel master.

6. PEDIDOS E GMV

Entram no GMV os pedidos da loja com status entregue. A data da competencia e
atualizado_em, preenchida quando o pedido muda para entregue, e o valor usado e
o campo total. O painel mostra um aviso se alguma loja nao puder ser
sincronizada; nesse caso, nao feche a competencia antes de corrigir a conexao.

REQUISITOS DA BASE DA LOJA

- tabela pedidos com id, mercado_id, status, total e atualizado_em;
- tabela loja_modulos_liberados ja instalada;
- supabase_url e supabase_service_role_key cadastradas na Central.

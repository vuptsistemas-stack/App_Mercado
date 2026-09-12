# Alteracao obrigatoria na Edge Function `validar-cupom-desconto`

O formulario do admin passa `uso_unico_por_cliente` e o aplicativo envia
`pedido_id` na confirmacao. Para a regra funcionar de verdade, inclua a logica
abaixo na funcao Central, depois de validar o token `loja_access_token` e obter
o UUID do cliente autenticado. Nunca aceite `cliente_id` vindo do corpo da
requisicao.

## 1. Ao carregar o cupom

Inclua `uso_unico_por_cliente` no `select` do cupom.

## 2. Antes de devolver um cupom valido

Quando `cupom.uso_unico_por_cliente === true`, consulte
`cupom_usos_clientes` usando `mercado_id`, `cupom.id` e o UUID extraido do
token da loja. Se houver registro, responda HTTP 400:

```ts
return json({ sucesso: false, erro: 'Este cupom ja foi utilizado por voce.' }, 400);
```

## 3. Ao receber `confirmar_uso: true`

Antes de incrementar `quantidade_usada`, chame a RPC criada pelo arquivo
`SQL_CUPOM_USO_UNICO_POR_CLIENTE.sql`:

```ts
if (cupom.uso_unico_por_cliente) {
  const { data: registrado, error } = await central.rpc(
    'registrar_uso_unico_cupom_cliente',
    {
      p_mercado_id: mercadoId,
      p_cupom_id: cupom.id,
      p_cliente_id: clienteIdDoTokenDaLoja,
      p_pedido_id: body.pedido_id ?? null,
    },
  );

  if (error) throw error;
  if (!registrado) {
    return json(
      { sucesso: false, erro: 'Este cupom ja foi utilizado por voce.' },
      400,
    );
  }
}
```

So incremente `quantidade_usada` se a RPC acima retornar `true`. A restricao
unica no banco impede duas compras simultaneas da mesma conta com o mesmo
cupom.

## 4. Funcao de gerenciamento do admin

Na Edge Function `gerenciar-cupons-desconto`, permita o campo
`uso_unico_por_cliente` no objeto salvo em `cupons_desconto`; caso ela monte
uma lista manual de campos, acrescente:

```ts
uso_unico_por_cliente: Boolean(cupom.uso_unico_por_cliente),
```

Sem os passos 1 a 4, a chave aparece no cadastro, mas a regra nao e aplicada
no servidor.

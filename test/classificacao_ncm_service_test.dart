import 'package:flutter_test/flutter_test.dart';

import 'package:app_mercado/models/produto.dart';
import 'package:app_mercado/services/classificacao_ncm_service.dart';

Produto produto({
  String nome = 'Arroz branco 5kg',
  String ncm = '10063021',
  String categoria = '',
  String subcategoria = '',
}) {
  return Produto(
    produtoId: 1,
    nome: nome,
    ean: '7890000000001',
    preco: 10,
    estoque: 5,
    ncm: ncm,
    categoria: categoria,
    subcategoria: subcategoria,
    categoriaApi: categoria,
    subcategoriaApi: subcategoria,
  );
}

const regraArroz = RegraClassificacaoNcm(
  ncmPrefixo: '1006',
  categoria: 'Mercearia',
  subcategoria: 'Arroz',
  ordemCategoria: 10,
  ordemSubcategoria: 2,
  prioridade: 0,
  palavrasIncluir: [],
  palavrasExcluir: [],
  escopoLoja: false,
);

void main() {
  test('Produto lê NCM e preserva a classificação original da API', () {
    final item = Produto.fromJson({
      'produto_id': 10,
      'nome_produto': 'Leite integral',
      'NCM': '0401.20.10',
      'nome_grupo': 'Laticínios',
      'nome_subgrupo': 'Leites',
    });

    expect(item.ncm, '0401.20.10');
    expect(item.categoriaApi, 'Laticínios');
    expect(item.subcategoriaApi, 'Leites');
  });

  test('modo NCM aplica categoria, subcategoria e ordenacao', () {
    final resultado = ClassificacaoNcmService.resolverProduto(
      produto(),
      modo: 'NCM',
      regras: const [regraArroz],
    );

    expect(resultado.categoria, 'Mercearia');
    expect(resultado.subcategoria, 'Arroz');
    expect(resultado.ordemCategoria, 10);
    expect(resultado.ordemSubcategoria, 2);
  });

  test('modo hibrido preserva classificacao completa da API', () {
    final resultado = ClassificacaoNcmService.resolverProduto(
      produto(categoria: 'Alimentos', subcategoria: 'Cereais'),
      modo: 'HIBRIDO',
      regras: const [regraArroz],
    );

    expect(resultado.categoria, 'Alimentos');
    expect(resultado.subcategoria, 'Cereais');
  });

  test('modo hibrido usa NCM quando a API nao classifica', () {
    final resultado = ClassificacaoNcmService.resolverProduto(
      produto(),
      modo: 'HIBRIDO',
      regras: const [regraArroz],
    );

    expect(resultado.categoria, 'Mercearia');
    expect(resultado.subcategoria, 'Arroz');
  });

  test('modo NCM envia produto sem regra para Outros', () {
    final resultado = ClassificacaoNcmService.resolverProduto(
      produto(ncm: '99999999'),
      modo: 'NCM',
      regras: const [regraArroz],
    );

    expect(resultado.categoria, 'Outros');
    expect(resultado.ordemCategoria, 9999);
  });

  test('palavras de inclusao e exclusao refinam a regra', () {
    const regra = RegraClassificacaoNcm(
      ncmPrefixo: '2202',
      categoria: 'Bebidas',
      subcategoria: 'Refrigerantes',
      ordemCategoria: 0,
      ordemSubcategoria: 0,
      prioridade: 0,
      palavrasIncluir: ['refrigerante'],
      palavrasExcluir: ['zero'],
      escopoLoja: false,
    );

    final comum = ClassificacaoNcmService.resolverProduto(
      produto(nome: 'Refrigerante cola 2l', ncm: '22021000'),
      modo: 'NCM',
      regras: const [regra],
    );
    final zero = ClassificacaoNcmService.resolverProduto(
      produto(nome: 'Refrigerante cola zero 2l', ncm: '22021000'),
      modo: 'NCM',
      regras: const [regra],
    );

    expect(comum.subcategoria, 'Refrigerantes');
    expect(zero.categoria, 'Outros');
  });
}

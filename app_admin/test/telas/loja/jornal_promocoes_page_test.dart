import 'dart:convert';

import 'package:app_preco/services/sessao_loja.dart';
import 'package:app_preco/telas/loja/jornal_promocoes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('monta e revisa um encarte com layout automatico', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SessaoLoja.mercadoId = null;
    SessaoLoja.mercadoCodigo = 'teste';
    SessaoLoja.mercadoNome = 'Mercado Teste';
    SessaoLoja.logoUrl = null;
    SessaoLoja.apiBaseUrl = null;
    SessaoLoja.corPrimariaHex = '#E30613';
    SessaoLoja.corSecundariaHex = '#B8000D';
    SessaoLoja.corFundoHex = '#F5F7FA';

    final itens = List.generate(
      7,
      (index) => {
        'id': 'produto-$index',
        'nome': 'Produto em promocao ${index + 1}',
        'ean': '78900000000$index',
        'preco': 7.99 + index,
        'preco_original': 10.99 + index,
        'imagem_url': '',
        'unidade': 'un',
        'destaque': index == 0,
      },
    );

    SharedPreferences.setMockInitialValues({
      'jornal_promocoes_rascunho_teste': jsonEncode({
        'titulo': 'Ofertas da semana',
        'chamada': 'Economia de verdade esta aqui',
        'validade': '05/09 a 12/09',
        'observacao': 'Ofertas validas enquanto durarem os estoques.',
        'modelo': 'impacto',
        'formato': 'status',
        'itens': itens,
      }),
    });

    await tester.pumpWidget(const MaterialApp(home: JornalPromocoesPage()));
    await tester.pumpAndSettle();

    expect(find.text('Produtos do jornal (7)'), findsOneWidget);
    expect(find.text('Personalizar'), findsOneWidget);

    await tester.tap(find.text('Personalizar'));
    await tester.pumpAndSettle();
    expect(find.text('Design e formato'), findsOneWidget);

    await tester.ensureVisible(find.text('Classico'));
    await tester.tap(find.text('Classico'));
    await tester.ensureVisible(find.text('Instagram'));
    await tester.tap(find.text('Instagram'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Ver previa'));
    await tester.tap(find.text('Ver previa'));
    await tester.pumpAndSettle();

    expect(find.text('Previa final'), findsOneWidget);
    expect(find.text('1080 x 1350'), findsWidgets);
    expect(find.text('Compartilhar PNG'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('usa arte de encarte como fundo e preserva a area de ofertas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SessaoLoja.mercadoId = null;
    SessaoLoja.mercadoCodigo = 'teste';
    SessaoLoja.mercadoNome = 'Mercado Teste';
    SessaoLoja.logoUrl = null;
    SessaoLoja.apiBaseUrl = null;
    SessaoLoja.corPrimariaHex = '#E30613';
    SessaoLoja.corSecundariaHex = '#B8000D';
    SessaoLoja.corFundoHex = '#F5F7FA';

    final itens = List.generate(
      12,
      (index) => {
        'id': 'oferta-$index',
        'nome': 'Oferta especial ${index + 1}',
        'ean': '78910000000$index',
        'preco': 4.99 + index,
        'preco_original': 7.99 + index,
        'imagem_url': '',
        'unidade': 'un',
        'destaque': index == 0,
      },
    );

    SharedPreferences.setMockInitialValues({
      'jornal_promocoes_rascunho_teste': jsonEncode({
        'modelo': 'encarte',
        'formato': 'feed',
        'itens': itens,
      }),
    });

    await tester.pumpWidget(const MaterialApp(home: JornalPromocoesPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Personalizar'));
    await tester.pumpAndSettle();
    expect(find.text('Modelo Super Ofertas'), findsOneWidget);
    expect(find.text('Trocar imagem'), findsOneWidget);

    await tester.ensureVisible(find.text('Ver previa'));
    await tester.tap(find.text('Ver previa'));
    await tester.pumpAndSettle();

    expect(find.text('1080 x 1350'), findsWidgets);
    expect(find.text('Compartilhar PNG'), findsOneWidget);
    expect(find.text('Imprimir A4'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

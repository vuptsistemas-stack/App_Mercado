import 'package:app_mercado/pages/login_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

Future<void> pumpLoginIphone12(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 47, bottom: 34),
            textScaler: const TextScaler.linear(0.7),
          ),
          child: child!,
        );
      },
      home: LoginPage(onContinuarSemConta: () {}),
    ),
  );
}

Future<void> limparSimulacaoIphone(WidgetTester tester) async {
  debugDefaultTargetPlatformOverride = null;
  await tester.binding.setSurfaceSize(null);
}

void main() {
  testWidgets('habilita Google, Apple e Cadastre-se no iPhone 12', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    try {
      await pumpLoginIphone12(tester);

      final google = find.widgetWithText(OutlinedButton, 'Entrar com Google');
      expect(google, findsOneWidget);
      expect(tester.widget<OutlinedButton>(google).onPressed, isNotNull);

      final apple = find.byType(SignInWithAppleButton);
      expect(apple, findsOneWidget);
      expect(tester.widget<SignInWithAppleButton>(apple).onPressed, isNotNull);

      final cadastro = find.widgetWithText(TextButton, 'Cadastre-se');
      expect(cadastro, findsOneWidget);
      expect(tester.widget<TextButton>(cadastro).onPressed, isNotNull);

      for (final botao in [google, apple, cadastro]) {
        await tester.ensureVisible(botao);
        expect(
          tester.getRect(botao).overlaps(const Rect.fromLTWH(0, 0, 390, 844)),
          isTrue,
        );
      }
    } finally {
      await limparSimulacaoIphone(tester);
    }
  });

  testWidgets('abre o cadastro ao tocar em Cadastre-se no iPhone 12', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    try {
      await pumpLoginIphone12(tester);

      final botaoCadastro = find.text('Cadastre-se');
      await tester.ensureVisible(botaoCadastro);
      await tester.tap(botaoCadastro);
      await tester.pumpAndSettle();

      expect(find.text('Criar cadastro'), findsOneWidget);
    } finally {
      await limparSimulacaoIphone(tester);
    }
  });
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/app_navigator.dart';
import 'services/sessao_loja.dart';
import 'telas/web/pedidos_web_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://pkrkeeupcvxnqhynfvbw.supabase.co',
    publishableKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBrcmtlZXVwY3Z4bnFoeW5mdmJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE3MjAyNjQsImV4cCI6MjA5NzI5NjI2NH0.THMGXQ24hOWVt_UDxy-qlW6_BGfFt2vkLB1I9j4dGi0',
    authOptions: const FlutterAuthClientOptions(autoRefreshToken: true),
  );

  runApp(const PedidosWebApp());
}

class PedidosWebApp extends StatelessWidget {
  const PedidosWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SessaoLoja.alteracoes,
      builder: (context, _, child) {
        final primaria = SessaoLoja.corPrimaria;

        return MaterialApp(
          title: 'Vupt Pedidos',
          debugShowCheckedModeBanner: false,
          navigatorKey: AppNavigator.navigatorKey,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaria,
              primary: primaria,
              secondary: SessaoLoja.corSecundaria,
              surface: Colors.white,
            ),
            scaffoldBackgroundColor: const Color(0xFFF5F7FA),
            fontFamily: 'Roboto',
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFD9DEE7)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFD9DEE7)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: primaria, width: 1.5),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: primaria,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            snackBarTheme: SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          home: const PedidosWebBootstrapPage(),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/firebase_web_config.dart';
import 'telas/auth/login_central_page.dart';
import 'telas/auth/verificar_perfil_page.dart';
import 'services/app_navigator.dart';
import 'services/push_notification_service.dart';
import 'services/sessao_loja.dart';
import 'telas/loja/menu_inicial.dart';
import 'telas/shared/aba_fluante_global.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (kIsWeb) {
      await Firebase.initializeApp(options: FirebaseWebConfig.options);
    } else {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
  } catch (e) {
    debugPrint('Firebase indisponivel ao iniciar o app: $e');
  }

  await Supabase.initialize(
    url: 'https://pkrkeeupcvxnqhynfvbw.supabase.co',
    publishableKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBrcmtlZXVwY3Z4bnFoeW5mdmJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE3MjAyNjQsImV4cCI6MjA5NzI5NjI2NH0.THMGXQ24hOWVt_UDxy-qlW6_BGfFt2vkLB1I9j4dGi0',
    authOptions: const FlutterAuthClientOptions(autoRefreshToken: true),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: SessaoLoja.alteracoes,
      builder: (context, _, child) {
        final primaria = SessaoLoja.corPrimaria;
        final secundaria = SessaoLoja.corSecundaria;

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: AppNavigator.navigatorKey,
          theme: ThemeData(
            useMaterial3: true,
            visualDensity: VisualDensity.compact,
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaria,
              primary: primaria,
              secondary: secundaria,
              surface: Colors.white,
              surfaceContainerHighest: const Color(0xFFF3F6F8),
            ),
            scaffoldBackgroundColor: SessaoLoja.corFundo,
            appBarTheme: AppBarTheme(
              backgroundColor: primaria,
              foregroundColor: Colors.white,
              centerTitle: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              toolbarHeight: 68,
              titleTextStyle: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.black.withValues(alpha: 0.07)),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: Colors.black.withValues(alpha: 0.10),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: Colors.black.withValues(alpha: 0.10),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: primaria, width: 1.4),
              ),
            ),
            listTileTheme: const ListTileThemeData(
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              iconColor: Color(0xFF667085),
              textColor: Color(0xFF1F2937),
            ),
            snackBarTheme: SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF1F2937),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            floatingActionButtonTheme: FloatingActionButtonThemeData(
              backgroundColor: primaria,
              foregroundColor: Colors.white,
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: primaria,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaria,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            progressIndicatorTheme: ProgressIndicatorThemeData(color: primaria),
          ),
          builder: (context, child) {
            return AbaFlutuanteGlobalHost(
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const VerificarSessaoPage(),
        );
      },
    );
  }
}

class VerificarSessaoPage extends StatefulWidget {
  const VerificarSessaoPage({super.key});

  @override
  State<VerificarSessaoPage> createState() => _VerificarSessaoPageState();
}

class _VerificarSessaoPageState extends State<VerificarSessaoPage> {
  late final Future<Widget> _destino = _verificarDestino();

  Future<Widget> _verificarDestino() async {
    final auth = Supabase.instance.client.auth;

    if (auth.currentSession != null) {
      try {
        await auth.refreshSession();
      } catch (_) {}

      if (auth.currentSession != null) {
        return const VerificarPerfilPage();
      }
    }

    final restaurouLoja = await SessaoLoja.restaurarSessaoLojaPersistida();

    if (restaurouLoja) {
      return const MenuInicialPage();
    }

    return const LoginCentralPage();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _destino,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return snapshot.data ?? const LoginCentralPage();
      },
    );
  }
}

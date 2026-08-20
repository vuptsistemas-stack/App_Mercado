import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_mercado_config.dart';
import 'notificacao_status_pedido_service.dart';
import 'sessao_mercado_cliente.dart' as sessao;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {
    // Sem o arquivo nativo do Firebase, o app continua funcionando sem push.
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final SupabaseClient central = SupabaseClient(
    AppMercadoConfig.centralSupabaseUrl,
    AppMercadoConfig.centralSupabaseAnonKey,
    authOptions: const AuthClientOptions(
      autoRefreshToken: false,
    ),
  );

  bool escutandoAtualizacaoToken = false;
  String ultimaChaveRegistrada = '';

  Future<void> inicializarCliente() async {
    final clienteLoja = Supabase.instance.client;
    final usuario = clienteLoja.auth.currentUser;
    final mercadoId = sessao.SessaoMercadoCliente.mercadoIdObrigatorio;

    if (usuario == null || mercadoId.isEmpty) return;

    await NotificacaoStatusPedidoService.instance.inicializar();

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );

      var token = await FirebaseMessaging.instance.getToken();
      if ((token ?? '').isEmpty && defaultTargetPlatform == TargetPlatform.iOS) {
        await Future<void>.delayed(const Duration(seconds: 2));
        token = await FirebaseMessaging.instance.getToken();
      }

      if ((token ?? '').isNotEmpty) {
        await _registrarToken(token!);
      }

      if (!escutandoAtualizacaoToken) {
        escutandoAtualizacaoToken = true;
        FirebaseMessaging.instance.onTokenRefresh.listen((novoToken) async {
          await _registrarToken(novoToken);
        });
      }
    } catch (e) {
      debugPrint('PUSH CLIENTE indisponivel: $e');
    }
  }

  Future<void> _registrarToken(String token) async {
    final clienteLoja = Supabase.instance.client;
    final usuario = clienteLoja.auth.currentUser;
    final sessaoAtual = clienteLoja.auth.currentSession;
    final mercadoId = sessao.SessaoMercadoCliente.mercadoIdObrigatorio;

    if (usuario == null || sessaoAtual == null || mercadoId.isEmpty) return;

    final chave = '$mercadoId:${usuario.id}:$token';
    if (ultimaChaveRegistrada == chave) return;

    final resposta = await central.functions.invoke(
      'registrar-push-token',
      body: {
        'mercado_id': mercadoId,
        'mercado_codigo':
            sessao.SessaoMercadoCliente.mercadoCodigoObrigatorio,
        'app_tipo': 'CLIENTE',
        'plataforma': _plataforma,
        'fcm_token': token,
        'app_id': AppMercadoConfig.appPackage,
        'loja_access_token': sessaoAtual.accessToken,
      },
    );

    final dados = resposta.data;
    if (resposta.status >= 400 ||
        (dados is Map && dados['sucesso'] == false)) {
      throw Exception(
        dados is Map ? dados['erro'] ?? 'Falha ao registrar push.' : dados,
      );
    }

    ultimaChaveRegistrada = chave;
  }

  Future<void> notificarEventoPedido({
    required String evento,
    required String pedidoId,
  }) async {
    final sessaoAtual = Supabase.instance.client.auth.currentSession;
    if (sessaoAtual == null || pedidoId.isEmpty) return;

    try {
      final resposta = await central.functions.invoke(
        'notificar-pedido-push',
        body: {
          'evento': evento,
          'mercado_id': sessao.SessaoMercadoCliente.mercadoIdObrigatorio,
          'mercado_codigo':
              sessao.SessaoMercadoCliente.mercadoCodigoObrigatorio,
          'pedido_id': pedidoId,
          'loja_access_token': sessaoAtual.accessToken,
        },
      );

      final dados = resposta.data;
      if (resposta.status >= 400 ||
          (dados is Map && dados['sucesso'] == false)) {
        debugPrint('PUSH PEDIDO recusado: $dados');
      }
    } catch (e) {
      // O pedido ja foi salvo/cancelado. Push nao desfaz a operacao.
      debugPrint('PUSH PEDIDO indisponivel: $e');
    }
  }

  String get _plataforma => defaultTargetPlatform == TargetPlatform.iOS
      ? 'IOS'
      : 'ANDROID';
}

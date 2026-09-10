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
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  bool escutandoAtualizacaoToken = false;
  bool escutandoMensagensForeground = false;
  bool escutandoAberturaNotificacoes = false;
  bool pushAtivo = false;
  String ultimaChaveRegistrada = '';
  final Map<String, DateTime> _mensagensForegroundProcessadas = {};

  Future<void> inicializarCliente() async {
    final clienteLoja = Supabase.instance.client;
    final usuario = clienteLoja.auth.currentUser;
    final mercadoId = sessao.SessaoMercadoCliente.mercadoIdObrigatorio;

    if (usuario == null || mercadoId.isEmpty) return;

    await NotificacaoStatusPedidoService.instance.inicializar();
    _escutarAberturaNotificacoes();

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: false,
            badge: false,
            sound: false,
          );
      _escutarMensagensEmPrimeiroPlano();

      var token = await FirebaseMessaging.instance.getToken();
      if ((token ?? '').isEmpty &&
          defaultTargetPlatform == TargetPlatform.iOS) {
        await Future<void>.delayed(const Duration(seconds: 2));
        token = await FirebaseMessaging.instance.getToken();
      }

      if ((token ?? '').isNotEmpty) {
        await _registrarToken(token!);
        pushAtivo = true;
      }

      if (!escutandoAtualizacaoToken) {
        escutandoAtualizacaoToken = true;
        FirebaseMessaging.instance.onTokenRefresh.listen((novoToken) async {
          try {
            await _registrarToken(novoToken);
            pushAtivo = true;
          } catch (e) {
            debugPrint('PUSH CLIENTE falhou ao renovar token: $e');
          }
        });
      }
    } catch (e) {
      pushAtivo = false;
      debugPrint('PUSH CLIENTE indisponivel: $e');
    }
  }

  void _escutarMensagensEmPrimeiroPlano() {
    if (escutandoMensagensForeground) return;

    escutandoMensagensForeground = true;
    FirebaseMessaging.onMessage.listen((mensagem) async {
      final evento = mensagem.data['evento']?.toString().toUpperCase() ?? '';
      if (evento == 'JORNAL_PUBLICADO') {
        await NotificacaoStatusPedidoService.instance.jornalPublicado(
          titulo: mensagem.notification?.title ?? 'Novo jornal de ofertas',
          mensagem:
              mensagem.notification?.body ??
              'Confira as novas ofertas da loja.',
        );
        return;
      }

      if (evento != 'STATUS_PEDIDO') return;

      final pedidoId = mensagem.data['pedido_id']?.toString() ?? '';
      final status =
          mensagem.data['status']?.toString().trim().toLowerCase() ?? '';
      final chave = '$evento:$pedidoId:$status';
      final agora = DateTime.now();

      _mensagensForegroundProcessadas.removeWhere(
        (_, horario) => agora.difference(horario) > const Duration(minutes: 2),
      );

      if (_mensagensForegroundProcessadas.containsKey(chave)) return;
      _mensagensForegroundProcessadas[chave] = agora;

      await NotificacaoStatusPedidoService.instance.statusAlterado(
        numeroPedido: mensagem.data['numero_pedido']?.toString() ?? '',
        status: _textoStatus(status),
      );
    });
  }

  void _escutarAberturaNotificacoes() {
    if (escutandoAberturaNotificacoes) return;
    escutandoAberturaNotificacoes = true;

    FirebaseMessaging.onMessageOpenedApp.listen(_tratarAberturaNotificacao);
    FirebaseMessaging.instance.getInitialMessage().then((mensagem) {
      if (mensagem != null) _tratarAberturaNotificacao(mensagem);
    });
  }

  void _tratarAberturaNotificacao(RemoteMessage mensagem) {
    final evento = mensagem.data['evento']?.toString().toUpperCase() ?? '';
    final destino = mensagem.data['destino']?.toString().trim();
    if (destino == 'jornal_promocoes' || evento == 'JORNAL_PUBLICADO') {
      NotificacaoStatusPedidoService.instance.abrirDestino('jornal_promocoes');
    } else if (evento == 'STATUS_PEDIDO') {
      NotificacaoStatusPedidoService.instance.abrirDestino('pedidos');
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
        'mercado_codigo': sessao.SessaoMercadoCliente.mercadoCodigoObrigatorio,
        'app_tipo': 'CLIENTE',
        'plataforma': _plataforma,
        'fcm_token': token,
        'app_id': AppMercadoConfig.appPackage,
        'loja_access_token': sessaoAtual.accessToken,
      },
    );

    final dados = resposta.data;
    if (resposta.status >= 400 || (dados is Map && dados['sucesso'] == false)) {
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

  String get _plataforma =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID';

  String _textoStatus(String status) {
    switch (status) {
      case 'novo':
        return 'Aguardando aceite';
      case 'aceito':
        return 'Pedido aceito';
      case 'preparando':
        return 'Em preparacao';
      case 'saiu_para_entrega':
        return 'Saiu para entrega';
      case 'entregue':
        return 'Entregue';
      case 'cancelado':
        return 'Cancelado';
      default:
        return status;
    }
  }
}

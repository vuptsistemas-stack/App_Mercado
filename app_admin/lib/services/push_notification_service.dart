import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/firebase_web_config.dart';
import 'notificacao_pedidos_service.dart';
import 'sessao_loja.dart';

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

  bool escutandoAtualizacaoToken = false;
  bool escutandoMensagensForeground = false;
  bool pushAtivo = false;
  String ultimaChaveRegistrada = '';
  final Map<String, DateTime> _mensagensForegroundProcessadas = {};

  bool reservarNotificacaoLocal({
    required String evento,
    required String pedidoId,
    String status = '',
  }) {
    final chave = '${evento.toUpperCase()}:$pedidoId:$status';
    final agora = DateTime.now();

    _mensagensForegroundProcessadas.removeWhere(
      (_, horario) => agora.difference(horario) > const Duration(minutes: 2),
    );

    if (chave == '::' || _mensagensForegroundProcessadas.containsKey(chave)) {
      return false;
    }

    _mensagensForegroundProcessadas[chave] = agora;
    return true;
  }

  Future<bool> inicializarAdmin({bool solicitarPermissao = false}) async {
    SessaoLoja.sincronizarSessaoAtual();

    if (SessaoLoja.mercadoIdObrigatorio.isEmpty ||
        SessaoLoja.usuarioId?.isNotEmpty != true) {
      return false;
    }

    await NotificacaoPedidosService.instance.inicializar();

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      final configuracoes = !kIsWeb || solicitarPermissao
          ? await FirebaseMessaging.instance.requestPermission(
              alert: true,
              badge: true,
              sound: true,
            )
          : await FirebaseMessaging.instance.getNotificationSettings();
      final permissaoConcedida =
          configuracoes.authorizationStatus == AuthorizationStatus.authorized ||
          configuracoes.authorizationStatus == AuthorizationStatus.provisional;

      if (!permissaoConcedida) {
        pushAtivo = false;
        return false;
      }
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: false,
            badge: false,
            sound: false,
          );
      _escutarMensagensEmPrimeiroPlano();

      if (kIsWeb && FirebaseWebConfig.vapidKey.trim().isEmpty) {
        debugPrint(
          'PUSH ADMIN WEB aguardando FIREBASE_WEB_VAPID_KEY no build.',
        );
        return false;
      }

      var token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? FirebaseWebConfig.vapidKey : null,
      );
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
            debugPrint('PUSH ADMIN falhou ao renovar token: $e');
          }
        });
      }

      return pushAtivo;
    } catch (e) {
      pushAtivo = false;
      debugPrint('PUSH ADMIN indisponivel: $e');
      return false;
    }
  }

  void _escutarMensagensEmPrimeiroPlano() {
    if (escutandoMensagensForeground) return;

    escutandoMensagensForeground = true;
    FirebaseMessaging.onMessage.listen((mensagem) async {
      final evento = mensagem.data['evento']?.toString().toUpperCase() ?? '';
      if (evento != 'NOVO_PEDIDO' && evento != 'PEDIDO_CANCELADO') return;

      final pedidoId = mensagem.data['pedido_id']?.toString() ?? '';
      final status = mensagem.data['status']?.toString() ?? '';
      if (!reservarNotificacaoLocal(
        evento: evento,
        pedidoId: pedidoId,
        status: status,
      )) {
        return;
      }

      final titulo =
          mensagem.notification?.title ??
          (evento == 'NOVO_PEDIDO'
              ? 'Novo pedido recebido'
              : 'Pedido cancelado pelo cliente');
      final corpo =
          mensagem.notification?.body ?? 'Confira os pedidos da loja.';

      if (evento == 'NOVO_PEDIDO') {
        await NotificacaoPedidosService.instance.novoPedido(
          titulo: titulo,
          mensagem: corpo,
        );
      } else {
        await NotificacaoPedidosService.instance.pedidoCancelado(
          titulo: titulo,
          mensagem: corpo,
        );
      }
    });
  }

  Future<void> _registrarToken(String token) async {
    SessaoLoja.sincronizarSessaoAtual();

    final mercadoId = SessaoLoja.mercadoId ?? '';
    final mercadoCodigo = SessaoLoja.mercadoCodigo ?? '';
    final usuarioId = SessaoLoja.usuarioId ?? '';

    if (mercadoId.isEmpty || mercadoCodigo.isEmpty || usuarioId.isEmpty) {
      return;
    }

    final chave = '$mercadoId:$usuarioId:$token';
    if (ultimaChaveRegistrada == chave) return;

    final pacote = await PackageInfo.fromPlatform();
    final resposta = await Supabase.instance.client.functions.invoke(
      'registrar-push-token',
      body: {
        'mercado_id': mercadoId,
        'mercado_codigo': mercadoCodigo,
        'app_tipo': 'ADMIN',
        'plataforma': _plataforma,
        'fcm_token': token,
        'app_id': pacote.packageName,
        'loja_access_token': SessaoLoja.lojaAccessToken,
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

  Future<void> notificarStatusPedido({required String pedidoId}) async {
    SessaoLoja.sincronizarSessaoAtual();

    try {
      final resposta = await Supabase.instance.client.functions.invoke(
        'notificar-pedido-push',
        body: {
          'evento': 'STATUS_PEDIDO',
          'mercado_id': SessaoLoja.mercadoIdObrigatorio,
          'mercado_codigo': SessaoLoja.mercadoCodigo ?? '',
          'pedido_id': pedidoId,
          'loja_access_token': SessaoLoja.lojaAccessToken,
        },
      );

      final dados = resposta.data;
      if (resposta.status >= 400 ||
          (dados is Map && dados['sucesso'] == false)) {
        debugPrint('PUSH STATUS recusado: $dados');
      }
    } catch (e) {
      // O status foi salvo. Falha de push nao deve desfazer a operacao.
      debugPrint('PUSH STATUS indisponivel: $e');
    }
  }

  Future<ResultadoPublicacaoJornal> publicarJornal({
    required String titulo,
    required String validade,
    required String formato,
    required int largura,
    required int altura,
    required Uint8List imagem,
  }) async {
    SessaoLoja.sincronizarSessaoAtual();

    final mercadoId = SessaoLoja.mercadoIdObrigatorio.trim();
    if (mercadoId.isEmpty) {
      throw Exception('Loja não identificada.');
    }

    final resposta = await Supabase.instance.client.functions.invoke(
      'notificar-jornal-push',
      body: {
        'mercado_id': mercadoId,
        'mercado_codigo': SessaoLoja.mercadoCodigo ?? '',
        'mercado_nome': SessaoLoja.mercadoNome ?? '',
        'titulo_jornal': titulo.trim(),
        'validade': validade.trim(),
        'formato': formato.trim(),
        'largura': largura,
        'altura': altura,
        'imagem_mime_type': 'image/png',
        'imagem_base64': base64Encode(imagem),
        'loja_access_token': SessaoLoja.lojaAccessToken,
      },
    );

    final dados = resposta.data;
    if (resposta.status >= 400 || dados is! Map || dados['sucesso'] != true) {
      final mensagem = dados is Map
          ? dados['erro']?.toString()
          : 'Falha ao publicar o jornal.';
      throw Exception(mensagem ?? 'Falha ao publicar o jornal.');
    }

    return ResultadoPublicacaoJornal(
      dispositivos: int.tryParse('${dados['dispositivos'] ?? 0}') ?? 0,
      enviados: int.tryParse('${dados['enviados'] ?? 0}') ?? 0,
      falhas: int.tryParse('${dados['falhas'] ?? 0}') ?? 0,
      jornalSalvo: dados['jornal_salvo'] == true,
    );
  }

  String get _plataforma {
    if (kIsWeb) return 'WEB';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID';
  }
}

class ResultadoPublicacaoJornal {
  final int dispositivos;
  final int enviados;
  final int falhas;
  final bool jornalSalvo;

  const ResultadoPublicacaoJornal({
    required this.dispositivos,
    required this.enviados,
    required this.falhas,
    required this.jornalSalvo,
  });
}

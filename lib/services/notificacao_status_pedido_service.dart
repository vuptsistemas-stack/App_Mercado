import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificacaoStatusPedidoService {
  NotificacaoStatusPedidoService._();

  static final NotificacaoStatusPedidoService instance =
      NotificacaoStatusPedidoService._();

  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _destinosController =
      StreamController<String>.broadcast();

  bool inicializado = false;
  String? _destinoPendente;

  Stream<String> get destinos => _destinosController.stream;

  String? consumirDestinoPendente() {
    final destino = _destinoPendente;
    _destinoPendente = null;
    return destino;
  }

  void abrirDestino(String? payload) {
    final destino = payload?.trim() ?? '';
    if (destino.isEmpty) return;
    _destinoPendente = destino;
    _destinosController.add(destino);
  }

  Future<void> inicializar() async {
    if (inicializado) return;

    const configuracao = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await plugin.initialize(
      settings: configuracao,
      onDidReceiveNotificationResponse: (resposta) {
        abrirDestino(resposta.payload);
      },
    );

    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    const canalJornal = AndroidNotificationChannel(
      'jornal_promocoes',
      'Jornais e promoções',
      description: 'Avisos quando a loja publicar um novo jornal de ofertas',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(canalJornal);

    await plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    inicializado = true;
  }

  Future<void> statusAlterado({
    required String numeroPedido,
    required String status,
  }) async {
    await inicializar();

    const android = AndroidNotificationDetails(
      'status_pedidos_cliente',
      'Atualizacoes dos pedidos',
      channelDescription: 'Avisos quando o status de um pedido for alterado',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: 'Pedido atualizado',
    );

    const detalhes = NotificationDetails(
      android: android,
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );

    await plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: numeroPedido.isEmpty
          ? 'Seu pedido foi atualizado'
          : 'Pedido #$numeroPedido atualizado',
      body: 'Novo status: $status',
      notificationDetails: detalhes,
      payload: 'pedidos',
    );
  }

  Future<void> jornalPublicado({
    required String titulo,
    required String mensagem,
  }) async {
    await inicializar();

    const android = AndroidNotificationDetails(
      'jornal_promocoes',
      'Jornais e promoções',
      channelDescription:
          'Avisos quando a loja publicar um novo jornal de ofertas',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: 'Novo jornal de ofertas',
    );

    const detalhes = NotificationDetails(
      android: android,
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );

    await plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: titulo,
      body: mensagem,
      notificationDetails: detalhes,
      payload: 'jornal_promocoes',
    );
  }
}

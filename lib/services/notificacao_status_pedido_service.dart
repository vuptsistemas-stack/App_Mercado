import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificacaoStatusPedidoService {
  NotificacaoStatusPedidoService._();

  static final NotificacaoStatusPedidoService instance =
      NotificacaoStatusPedidoService._();

  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  bool inicializado = false;

  Future<void> inicializar() async {
    if (inicializado) return;

    const configuracao = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await plugin.initialize(settings: configuracao);

    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

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
}

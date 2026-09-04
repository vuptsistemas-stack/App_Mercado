import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificacaoPedidosService {
  NotificacaoPedidosService._();

  static final NotificacaoPedidosService instance =
      NotificacaoPedidosService._();

  final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  bool inicializado = false;

  static const AndroidNotificationChannel canalNovosPedidos =
      AndroidNotificationChannel(
        'pedidos_novos_chamada_v1',
        'Novos pedidos - toque prolongado',
        description:
            'Notificacoes urgentes com toque prolongado para novos pedidos',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('novo_pedido'),
        enableVibration: true,
      );

  static const AndroidNotificationChannel canalPedidosCancelados =
      AndroidNotificationChannel(
        'pedidos_cancelados',
        'Pedidos cancelados',
        description: 'Notificacoes de pedidos cancelados pelos clientes',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

  static final Int64List vibracaoNovoPedido = Int64List.fromList(<int>[
    0,
    700,
    300,
    700,
    700,
    700,
    300,
    700,
  ]);

  Future<void> inicializar() async {
    if (inicializado) {
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await plugin.initialize(settings: initSettings);

    final androidPlugin = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(canalNovosPedidos);
    await androidPlugin?.createNotificationChannel(canalPedidosCancelados);

    await androidPlugin?.requestNotificationsPermission();

    await plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    inicializado = true;
  }

  Future<void> novoPedido({
    required String titulo,
    required String mensagem,
  }) async {
    await inicializar();

    final androidDetails = AndroidNotificationDetails(
      'pedidos_novos_chamada_v1',
      'Novos pedidos - toque prolongado',
      channelDescription:
          'Notificações urgentes com toque prolongado para novos pedidos',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('novo_pedido'),
      enableVibration: true,
      vibrationPattern: vibracaoNovoPedido,
      category: AndroidNotificationCategory.message,
      ticker: 'Novo pedido',
    );

    final detalhes = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'novo_pedido.wav',
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    await plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: titulo,
      body: mensagem,
      notificationDetails: detalhes,
    );
  }

  Future<void> pedidoCancelado({
    required String titulo,
    required String mensagem,
  }) async {
    await inicializar();

    const androidDetails = AndroidNotificationDetails(
      'pedidos_cancelados',
      'Pedidos cancelados',
      channelDescription: 'Notificações de pedidos cancelados pelos clientes',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: 'Pedido cancelado',
    );

    const detalhes = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );

    await plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: titulo,
      body: mensagem,
      notificationDetails: detalhes,
    );
  }

  Future<void> alertaValidade({
    required String titulo,
    required String mensagem,
  }) async {
    await inicializar();

    const androidDetails = AndroidNotificationDetails(
      'acoes_validade',
      'Acoes de validade',
      channelDescription:
          'Alertas de encerramento de descontos por validade ou estoque',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ticker: 'Alerta de validade',
    );

    const detalhes = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );

    await plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: titulo,
      body: mensagem,
      notificationDetails: detalhes,
    );
  }
}

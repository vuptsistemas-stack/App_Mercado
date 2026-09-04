import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notificacao_pedidos_service.dart';
import 'push_notification_service.dart';
import 'sessao_loja.dart';

class MonitorPedidosService {
  MonitorPedidosService._();

  static final MonitorPedidosService instance = MonitorPedidosService._();

  RealtimeChannel? canal;
  Timer? timerNovosPedidos;
  bool consultandoNovosPedidos = false;

  String mercadoMonitorado = '';
  Future<void> Function()? aoReceberNovoPedido;

  final Set<String> pedidosNotificados = {};
  final Set<String> cancelamentosNotificados = {};

  Future<void> iniciar({Future<void> Function()? onNovoPedido}) async {
    SessaoLoja.sincronizarSessaoAtual();

    final supabaseLoja = SessaoLoja.supabaseLoja;
    final mercadoId = SessaoLoja.mercadoId ?? '';

    if (supabaseLoja == null || mercadoId.isEmpty) {
      return;
    }

    aoReceberNovoPedido = onNovoPedido;

    await NotificacaoPedidosService.instance.inicializar();
    await PushNotificationService.instance.inicializarAdmin();

    if (canal != null && mercadoMonitorado == mercadoId) {
      _garantirConsultaPeriodica();
      return;
    }

    await parar();

    mercadoMonitorado = mercadoId;
    await _consultarNovosPedidos();
    canal = supabaseLoja.channel('monitor-pedidos-admin-$mercadoId');

    canal!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'pedidos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'mercado_id',
            value: mercadoId,
          ),
          callback: (payload) async {
            await _notificarNovoPedido(payload.newRecord);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'pedidos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'mercado_id',
            value: mercadoId,
          ),
          callback: (payload) async {
            final pedido = payload.newRecord;

            if (!SessaoLoja.mesmoMercado(pedido)) {
              return;
            }

            final status = pedido['status']?.toString().toLowerCase() ?? '';

            if (status != 'cancelado') {
              return;
            }

            final canceladoPor =
                pedido['cancelado_por']?.toString().toLowerCase().trim() ?? '';

            if (canceladoPor.isNotEmpty && canceladoPor != 'cliente') {
              return;
            }

            final pedidoId = pedido['id']?.toString() ?? '';
            final numeroPedido = pedido['numero_pedido']?.toString() ?? '';
            final chavePedido = pedidoId.isNotEmpty ? pedidoId : numeroPedido;
            final chaveCancelamento = 'cancelado-$chavePedido';

            if (chavePedido.isNotEmpty &&
                cancelamentosNotificados.contains(chaveCancelamento)) {
              return;
            }

            if (chavePedido.isNotEmpty) {
              cancelamentosNotificados.add(chaveCancelamento);
            }

            final cliente =
                pedido['cliente_nome']?.toString().trim().isNotEmpty == true
                ? pedido['cliente_nome'].toString()
                : 'Cliente';

            if (PushNotificationService.instance.reservarNotificacaoLocal(
              evento: 'PEDIDO_CANCELADO',
              pedidoId: chavePedido,
              status: status,
            )) {
              await NotificacaoPedidosService.instance.pedidoCancelado(
                titulo: 'Pedido cancelado pelo cliente',
                mensagem: numeroPedido.isEmpty
                    ? '$cliente cancelou um pedido'
                    : 'Pedido #$numeroPedido - $cliente',
              );
            }

            final callbackAtual = aoReceberNovoPedido;

            if (callbackAtual != null) {
              await callbackAtual();
            }
          },
        )
        .subscribe();

    _garantirConsultaPeriodica();
  }

  void _garantirConsultaPeriodica() {
    timerNovosPedidos ??= Timer.periodic(
      const Duration(seconds: 8),
      (_) => _consultarNovosPedidos(),
    );
  }

  String _chaveUltimaConsulta(String mercadoId) =>
      'app_preco_ultimo_pedido_monitorado_$mercadoId';

  Future<void> _consultarNovosPedidos() async {
    if (consultandoNovosPedidos) return;

    SessaoLoja.sincronizarSessaoAtual();

    final supabaseLoja = SessaoLoja.supabaseLoja;
    final mercadoId = SessaoLoja.mercadoId ?? '';

    if (supabaseLoja == null || mercadoId.isEmpty) return;

    consultandoNovosPedidos = true;

    try {
      final preferencias = await SharedPreferences.getInstance();
      final chave = _chaveUltimaConsulta(mercadoId);
      final ultimoTexto = preferencias.getString(chave);
      final agora = DateTime.now().toUtc();
      final desde = DateTime.tryParse(ultimoTexto ?? '')?.toUtc() ??
          agora.subtract(const Duration(minutes: 5));

      final resposta = await supabaseLoja
          .from('pedidos')
          .select(
            'id, numero_pedido, cliente_nome, total, status, mercado_id, criado_em',
          )
          .eq('mercado_id', mercadoId)
          .gte('criado_em', desde.toIso8601String())
          .order('criado_em', ascending: true)
          .limit(100);

      for (final pedido in List<Map<String, dynamic>>.from(resposta)) {
        await _notificarNovoPedido(pedido);
      }

      await preferencias.setString(chave, agora.toIso8601String());
    } catch (_) {
      // O canal Realtime continua ativo se a conferencia pontual falhar.
    } finally {
      consultandoNovosPedidos = false;
    }
  }

  Future<void> _notificarNovoPedido(Map<String, dynamic> pedido) async {
    if (!SessaoLoja.mesmoMercado(pedido)) return;

    final status = pedido['status']?.toString().toLowerCase() ?? '';

    if (status.isNotEmpty && status != 'novo') return;

    final pedidoId = pedido['id']?.toString() ?? '';
    final numeroPedido = pedido['numero_pedido']?.toString() ?? '';
    final chavePedido = pedidoId.isNotEmpty ? pedidoId : numeroPedido;

    if (chavePedido.isNotEmpty && pedidosNotificados.contains(chavePedido)) {
      return;
    }

    if (chavePedido.isNotEmpty) pedidosNotificados.add(chavePedido);

    final cliente =
        pedido['cliente_nome']?.toString().trim().isNotEmpty == true
        ? pedido['cliente_nome'].toString()
        : 'Cliente';
    final total = pedido['total']?.toString() ?? '';

    if (PushNotificationService.instance.reservarNotificacaoLocal(
      evento: 'NOVO_PEDIDO',
      pedidoId: chavePedido,
      status: status,
    )) {
      await NotificacaoPedidosService.instance.novoPedido(
        titulo: 'Novo pedido recebido',
        mensagem: numeroPedido.isEmpty
            ? '$cliente fez um novo pedido'
            : 'Pedido #$numeroPedido - $cliente - R\$ $total',
      );
    }

    final callbackAtual = aoReceberNovoPedido;
    if (callbackAtual != null) await callbackAtual();
  }

  Future<void> parar() async {
    timerNovosPedidos?.cancel();
    timerNovosPedidos = null;
    consultandoNovosPedidos = false;

    final supabaseLoja = SessaoLoja.supabaseLoja;

    if (canal != null && supabaseLoja != null) {
      await supabaseLoja.removeChannel(canal!);
    }

    canal = null;
    mercadoMonitorado = '';
  }
}

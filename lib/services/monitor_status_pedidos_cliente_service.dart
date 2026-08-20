import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notificacao_status_pedido_service.dart';
import 'push_notification_service.dart';
import 'sessao_mercado_cliente.dart' as sessao;

class MonitorStatusPedidosClienteService {
  MonitorStatusPedidosClienteService._();

  static final MonitorStatusPedidosClienteService instance =
      MonitorStatusPedidosClienteService._();

  RealtimeChannel? canal;
  Timer? timerConferencia;
  String chaveMonitorada = '';
  final Map<String, String> statusConhecidos = {};
  bool conferindo = false;

  Future<void> iniciar() async {
    final cliente = Supabase.instance.client;
    final usuario = cliente.auth.currentUser;
    final mercadoId = sessao.SessaoMercadoCliente.mercadoIdObrigatorio;

    if (usuario == null || mercadoId.isEmpty) return;

    final novaChave = '$mercadoId:${usuario.id}';

    if (canal != null && chaveMonitorada == novaChave) {
      _garantirTimer();
      return;
    }

    await parar();
    chaveMonitorada = novaChave;

    await NotificacaoStatusPedidoService.instance.inicializar();
    await PushNotificationService.instance.inicializarCliente();
    await _carregarStatusPersistidos();
    await _conferirAlteracoes(notificar: statusConhecidos.isNotEmpty);

    canal = cliente
        .channel('monitor-status-cliente-$novaChave')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'pedidos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: usuario.id,
          ),
          callback: (payload) async {
            await _processarPedido(
              Map<String, dynamic>.from(payload.newRecord),
              notificar: true,
            );
          },
        )
        .subscribe();

    _garantirTimer();
  }

  void _garantirTimer() {
    timerConferencia ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => _conferirAlteracoes(notificar: true),
    );
  }

  Future<void> _conferirAlteracoes({required bool notificar}) async {
    if (conferindo || chaveMonitorada.isEmpty) return;

    final usuario = Supabase.instance.client.auth.currentUser;
    final mercadoId = sessao.SessaoMercadoCliente.mercadoIdObrigatorio;

    if (usuario == null || mercadoId.isEmpty) return;

    conferindo = true;

    try {
      final resposta = await Supabase.instance.client
          .from('pedidos')
          .select('id, numero_pedido, status, mercado_id')
          .eq('mercado_id', mercadoId)
          .eq('user_id', usuario.id)
          .order('criado_em', ascending: false)
          .limit(50);

      for (final item in List<Map<String, dynamic>>.from(resposta)) {
        await _processarPedido(item, notificar: notificar);
      }
    } catch (_) {
      // O Realtime continua ativo se uma conferencia pontual falhar.
    } finally {
      conferindo = false;
    }
  }

  Future<void> _processarPedido(
    Map<String, dynamic> pedido, {
    required bool notificar,
  }) async {
    final mercadoId = pedido['mercado_id']?.toString() ?? '';

    if (mercadoId != sessao.SessaoMercadoCliente.mercadoIdObrigatorio) return;

    final id = pedido['id']?.toString() ?? '';
    final novoStatus = pedido['status']?.toString().trim().toLowerCase() ?? '';

    if (id.isEmpty || novoStatus.isEmpty) return;

    final anterior = statusConhecidos[id];

    if (anterior == novoStatus) return;

    statusConhecidos[id] = novoStatus;
    await _salvarStatusPersistidos();

    if (!notificar || anterior == null) return;

    await NotificacaoStatusPedidoService.instance.statusAlterado(
      numeroPedido: pedido['numero_pedido']?.toString() ?? '',
      status: _textoStatus(novoStatus),
    );
  }

  String _chavePersistencia() =>
      'app_mercado_status_pedidos_${chaveMonitorada.replaceAll(':', '_')}';

  Future<void> _carregarStatusPersistidos() async {
    statusConhecidos.clear();
    final preferencias = await SharedPreferences.getInstance();
    final bruto = preferencias.getString(_chavePersistencia());

    if (bruto == null || bruto.isEmpty) return;

    try {
      final mapa = Map<String, dynamic>.from(jsonDecode(bruto));
      statusConhecidos.addAll(
        mapa.map((chave, valor) => MapEntry(chave, valor.toString())),
      );
    } catch (_) {}
  }

  Future<void> _salvarStatusPersistidos() async {
    if (chaveMonitorada.isEmpty) return;
    final preferencias = await SharedPreferences.getInstance();
    await preferencias.setString(
      _chavePersistencia(),
      jsonEncode(statusConhecidos),
    );
  }

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

  Future<void> parar() async {
    timerConferencia?.cancel();
    timerConferencia = null;

    final canalAtual = canal;
    canal = null;

    if (canalAtual != null) {
      await Supabase.instance.client.removeChannel(canalAtual);
    }

    chaveMonitorada = '';
    statusConhecidos.clear();
  }
}

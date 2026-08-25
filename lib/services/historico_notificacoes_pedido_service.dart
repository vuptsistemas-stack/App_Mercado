import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sessao_mercado_cliente.dart' as sessao;

class NotificacaoPedidoCliente {
  final String id;
  final String pedidoId;
  final String numeroPedido;
  final String status;
  final String titulo;
  final String mensagem;
  final DateTime criadoEm;
  final bool lida;

  const NotificacaoPedidoCliente({
    required this.id,
    required this.pedidoId,
    required this.numeroPedido,
    required this.status,
    required this.titulo,
    required this.mensagem,
    required this.criadoEm,
    required this.lida,
  });

  factory NotificacaoPedidoCliente.fromJson(Map<String, dynamic> json) {
    return NotificacaoPedidoCliente(
      id: json['id']?.toString() ?? '',
      pedidoId: json['pedido_id']?.toString() ?? '',
      numeroPedido: json['numero_pedido']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      titulo: json['titulo']?.toString() ?? 'Pedido atualizado',
      mensagem: json['mensagem']?.toString() ?? '',
      criadoEm:
          DateTime.tryParse(json['criado_em']?.toString() ?? '') ??
          DateTime.now(),
      lida: json['lida'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pedido_id': pedidoId,
      'numero_pedido': numeroPedido,
      'status': status,
      'titulo': titulo,
      'mensagem': mensagem,
      'criado_em': criadoEm.toIso8601String(),
      'lida': lida,
    };
  }

  NotificacaoPedidoCliente copiarComoLida() {
    return NotificacaoPedidoCliente(
      id: id,
      pedidoId: pedidoId,
      numeroPedido: numeroPedido,
      status: status,
      titulo: titulo,
      mensagem: mensagem,
      criadoEm: criadoEm,
      lida: true,
    );
  }
}

class HistoricoNotificacoesPedidoService {
  HistoricoNotificacoesPedidoService._();

  static final HistoricoNotificacoesPedidoService instance =
      HistoricoNotificacoesPedidoService._();

  static const int _limiteRegistros = 60;
  Future<void> _filaGravacao = Future<void>.value();

  String get _chavePersistencia {
    final mercadoId = sessao.SessaoMercadoCliente.mercadoIdObrigatorio;
    final usuarioId =
        Supabase.instance.client.auth.currentUser?.id ?? 'sem_usuario';

    return 'app_mercado_notificacoes_${mercadoId}_$usuarioId';
  }

  Future<List<NotificacaoPedidoCliente>> listar() async {
    final preferencias = await SharedPreferences.getInstance();
    final bruto = preferencias.getString(_chavePersistencia);

    if (bruto == null || bruto.isEmpty) {
      return [];
    }

    try {
      final lista = List<dynamic>.from(jsonDecode(bruto));
      final notificacoes = lista
          .map(
            (item) => NotificacaoPedidoCliente.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();

      notificacoes.sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
      return notificacoes;
    } catch (_) {
      return [];
    }
  }

  Future<int> quantidadeNaoLidas() async {
    final notificacoes = await listar();
    return notificacoes.where((item) => !item.lida).length;
  }

  Future<void> registrarStatusPedido({
    required String pedidoId,
    required String numeroPedido,
    required String status,
    required String descricaoStatus,
  }) {
    final operacao = _filaGravacao.then((_) {
      return _registrarStatusPedido(
        pedidoId: pedidoId,
        numeroPedido: numeroPedido,
        status: status,
        descricaoStatus: descricaoStatus,
      );
    });

    _filaGravacao = operacao.then<void>((_) {}, onError: (_) {});
    return operacao;
  }

  Future<void> _registrarStatusPedido({
    required String pedidoId,
    required String numeroPedido,
    required String status,
    required String descricaoStatus,
  }) async {
    if (pedidoId.trim().isEmpty || status.trim().isEmpty) {
      return;
    }

    final notificacoes = await listar();
    final agora = DateTime.now();
    final statusNormalizado = status.trim().toLowerCase();

    final repetida = notificacoes.any((item) {
      return item.pedidoId == pedidoId &&
          item.status == statusNormalizado &&
          agora.difference(item.criadoEm).abs() < const Duration(minutes: 2);
    });

    if (repetida) {
      return;
    }

    final numeroExibicao = numeroPedido.trim().isEmpty ? '-' : numeroPedido;
    notificacoes.insert(
      0,
      NotificacaoPedidoCliente(
        id: '${agora.microsecondsSinceEpoch}-$pedidoId-$statusNormalizado',
        pedidoId: pedidoId,
        numeroPedido: numeroExibicao,
        status: statusNormalizado,
        titulo: 'Pedido #$numeroExibicao atualizado',
        mensagem: 'O status mudou para: $descricaoStatus',
        criadoEm: agora,
        lida: false,
      ),
    );

    if (notificacoes.length > _limiteRegistros) {
      notificacoes.removeRange(_limiteRegistros, notificacoes.length);
    }

    await _salvar(notificacoes);
  }

  Future<void> marcarTodasComoLidas() async {
    final notificacoes = await listar();

    if (notificacoes.isEmpty || notificacoes.every((item) => item.lida)) {
      return;
    }

    await _salvar(notificacoes.map((item) => item.copiarComoLida()).toList());
  }

  Future<void> _salvar(List<NotificacaoPedidoCliente> notificacoes) async {
    final preferencias = await SharedPreferences.getInstance();
    await preferencias.setString(
      _chavePersistencia,
      jsonEncode(notificacoes.map((item) => item.toJson()).toList()),
    );
  }
}

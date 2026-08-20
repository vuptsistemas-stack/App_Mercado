import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/sessao_mercado_cliente.dart' as sessao;
import '../services/app_tema_service.dart';
import '../services/push_notification_service.dart';

String nomeMercado() {
  final nome = sessao.SessaoMercadoCliente.mercadoNome.trim();

  if (nome.isEmpty) {
    return 'Mercado Online';
  }

  return nome;
}

String whatsappMercadoPedido() {
  return sessao.SessaoMercadoCliente.whatsapp.trim();
}

String whatsappMercadoSomenteNumeros() {
  return whatsappMercadoPedido().replaceAll(RegExp(r'[^0-9]'), '');
}

String normalizarStatusPedidoCliente(dynamic valor) {
  return valor
          ?.toString()
          .trim()
          .toLowerCase()
          .replaceAll('-', '_')
          .replaceAll(RegExp(r'\s+'), '_') ??
      '';
}

bool statusPedidoPermiteCancelamentoCliente(dynamic valor) {
  final status = normalizarStatusPedidoCliente(valor);

  return status.isEmpty ||
      status == 'novo' ||
      status == 'recebido' ||
      status == 'pedido_recebido' ||
      status == 'aceito' ||
      status == 'pedido_aceito' ||
      status == 'preparando' ||
      status == 'preparacao' ||
      status == 'em_preparacao' ||
      status == 'separando' ||
      status == 'separacao' ||
      status == 'em_separacao';
}

class PedidosPage extends StatefulWidget {
  final VoidCallback? onVoltarInicio;

  const PedidosPage({super.key, this.onVoltarInicio});

  @override
  State<PedidosPage> createState() => _PedidosPageState();
}

class _PedidosPageState extends State<PedidosPage> {
  bool carregando = true;
  List<Map<String, dynamic>> pedidos = [];
  RealtimeChannel? canalStatusPedidos;
  final Map<String, String> statusConhecidoPorPedido = {};
  String pedidoCancelandoId = '';

  @override
  void initState() {
    super.initState();
    iniciarAvisosStatusPedido();
    carregarPedidos();
  }

  @override
  void dispose() {
    final canal = canalStatusPedidos;

    if (canal != null) {
      Supabase.instance.client.removeChannel(canal);
    }

    super.dispose();
  }

  void iniciarAvisosStatusPedido() {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null || canalStatusPedidos != null) {
      return;
    }

    final mercadoId = sessao.SessaoMercadoCliente.mercadoIdObrigatorio;

    canalStatusPedidos = Supabase.instance.client
        .channel('pedidos-status-${user.id}-$mercadoId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'pedidos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            final novoPedido = Map<String, dynamic>.from(payload.newRecord);
            processarMudancaStatusPedido(novoPedido);
          },
        )
        .subscribe();
  }

  void registrarStatusConhecidos(List<Map<String, dynamic>> lista) {
    for (final pedido in lista) {
      final id = pedido['id']?.toString() ?? '';

      if (id.isEmpty) {
        continue;
      }

      statusConhecidoPorPedido[id] = pedido['status']?.toString() ?? 'novo';
    }
  }

  void processarMudancaStatusPedido(Map<String, dynamic> pedidoAtualizado) {
    if (!mounted) {
      return;
    }

    final mercadoId = pedidoAtualizado['mercado_id']?.toString() ?? '';

    if (mercadoId != sessao.SessaoMercadoCliente.mercadoIdObrigatorio) {
      return;
    }

    final id = pedidoAtualizado['id']?.toString() ?? '';

    if (id.isEmpty) {
      return;
    }

    final novoStatus = pedidoAtualizado['status']?.toString() ?? 'novo';
    final statusAnterior = statusConhecidoPorPedido[id];

    statusConhecidoPorPedido[id] = novoStatus;

    setState(() {
      final indice = pedidos.indexWhere(
        (pedido) => pedido['id']?.toString() == id,
      );

      if (indice >= 0) {
        pedidos[indice] = {...pedidos[indice], ...pedidoAtualizado};
      }
    });

    if (statusAnterior == null || statusAnterior == novoStatus) {
      return;
    }

    mostrarAvisoStatusPedido(pedidoAtualizado, novoStatus);
  }

  void mostrarAvisoStatusPedido(
    Map<String, dynamic> pedido,
    String novoStatus,
  ) {
    final numero = pedido['numero_pedido']?.toString() ?? '-';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Seu pedido #$numero mudou para: ${textoStatus(novoStatus)}',
        ),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Ver',
          textColor: Colors.white,
          onPressed: () {
            final pedidoDaLista = pedidos.firstWhere(
              (item) => item['id']?.toString() == pedido['id']?.toString(),
              orElse: () => pedido,
            );

            abrirDetalhes(pedidoDaLista);
          },
        ),
      ),
    );
  }

  bool erroSessaoExpirada(Object erro) {
    final textoErro = erro.toString().toLowerCase();

    return textoErro.contains('jwt expired') ||
        textoErro.contains('pgrst303') ||
        textoErro.contains('unauthorized') ||
        textoErro.contains('401');
  }

  Future<bool> tentarRenovarSessao() async {
    try {
      final resposta = await Supabase.instance.client.auth.refreshSession();

      return resposta.session != null ||
          Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> carregarPedidos({bool tentouRenovarSessao = false}) async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      setState(() {
        carregando = false;
      });
      return;
    }

    try {
      final resposta = await Supabase.instance.client
          .from('pedidos')
          .select()
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('user_id', user.id)
          .order('criado_em', ascending: false);

      final lista = List<Map<String, dynamic>>.from(resposta);

      for (final pedido in lista) {
        final itens = await Supabase.instance.client
            .from('pedido_itens')
            .select(
              'id, peso_variavel, peso_real_kg, total, total_estimado, total_final',
            )
            .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
            .eq('pedido_id', pedido['id']);

        final listaItens = List<Map<String, dynamic>>.from(itens);
        final totalOriginalItens = listaItens.fold<double>(0, (soma, item) {
          final totalEstimado = numero(item['total_estimado']);
          final totalNormal = numero(item['total']);

          if (totalEstimado > 0) {
            return soma + totalEstimado;
          }

          return soma + totalNormal;
        });

        pedido['quantidade_itens'] = listaItens.length;
        pedido['possui_peso_variavel'] = listaItens.any(itemPesoVariavel);
        pedido['possui_reajuste_valor'] = listaItens.any(itemReajustado);
        pedido['total_original_itens'] = totalOriginalItens;
      }

      registrarStatusConhecidos(lista);

      if (!mounted) return;

      setState(() {
        pedidos = lista;
        carregando = false;
      });
    } catch (e) {
      if (!mounted) return;

      if (!tentouRenovarSessao && erroSessaoExpirada(e)) {
        final renovou = await tentarRenovarSessao();

        if (renovou && mounted) {
          await carregarPedidos(tentouRenovarSessao: true);
          return;
        }
      }

      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mensagemErroCarregarPedidos(e))));
    }
  }

  String mensagemErroCarregarPedidos(Object erro) {
    if (erroSessaoExpirada(erro)) {
      return 'Sua sessão expirou. Saia da conta e entre novamente para ver seus pedidos.';
    }

    return 'Não foi possível carregar seus pedidos. Tente novamente.';
  }

  Map<String, dynamic>? get pedidoAtual {
    final emAndamento = pedidos.where((pedido) {
      final status = normalizarStatusPedidoCliente(pedido['status']);
      return statusPedidoPermiteCancelamentoCliente(status) ||
          status == 'saiu_para_entrega';
    }).toList();

    if (emAndamento.isNotEmpty) {
      return emAndamento.first;
    }

    if (pedidos.isNotEmpty) {
      return pedidos.first;
    }

    return null;
  }

  String formatarMoeda(dynamic valor) {
    final numero = double.tryParse(valor.toString()) ?? 0;
    return 'R\$ ${numero.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  double numero(dynamic valor) {
    if (valor == null) {
      return 0;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor.toString().replaceAll(',', '.').trim()) ?? 0;
  }

  bool valorBool(dynamic valor) {
    if (valor is bool) return valor;
    if (valor is num) return valor == 1;

    final texto = valor?.toString().trim().toLowerCase() ?? '';

    return texto == 'true' || texto == '1' || texto == 'sim';
  }

  bool itemPesoVariavel(Map<String, dynamic> item) {
    return valorBool(item['peso_variavel']);
  }

  bool itemReajustado(Map<String, dynamic> item) {
    if (!itemPesoVariavel(item)) {
      return false;
    }

    final pesoReal = numero(item['peso_real_kg']);
    final totalFinal = numero(item['total_final']);

    return pesoReal > 0 && totalFinal > 0;
  }

  bool pedidoReajustado(Map<String, dynamic> pedido) {
    return valorBool(pedido['total_recalculado']) ||
        valorBool(pedido['possui_reajuste_valor']);
  }

  double valorTotalAnteriorPedido(Map<String, dynamic> pedido) {
    final camposPossiveis = [
      'total_original',
      'total_estimado',
      'subtotal_estimado',
      'valor_estimado',
      'total_sem_reajuste',
      'total_anterior',
      'total_inicial',
      'total_original_itens',
    ];

    for (final campo in camposPossiveis) {
      final valor = numero(pedido[campo]);

      if (valor > 0) {
        return valor;
      }
    }

    return 0;
  }

  bool mostrarTotalAnteriorPedido(Map<String, dynamic> pedido) {
    final totalAtual = numero(pedido['total']);
    final totalAnterior = valorTotalAnteriorPedido(pedido);

    return pedidoReajustado(pedido) &&
        totalAnterior > 0 &&
        (totalAnterior - totalAtual).abs() > 0.009;
  }

  String formatarData(dynamic valor) {
    if (valor == null) return '';

    try {
      final data = DateTime.parse(valor.toString()).toLocal();

      final dia = data.day.toString().padLeft(2, '0');
      final mes = data.month.toString().padLeft(2, '0');
      final ano = data.year.toString();
      final hora = data.hour.toString().padLeft(2, '0');
      final minuto = data.minute.toString().padLeft(2, '0');

      return '$dia/$mes/$ano às $hora:$minuto';
    } catch (_) {
      return valor.toString();
    }
  }

  Color corStatus(String status) {
    switch (status.toLowerCase()) {
      case 'novo':
        return AppTemaService.primaria;
      case 'aceito':
        return Colors.green;
      case 'preparando':
        return Colors.orange;
      case 'saiu_para_entrega':
        return Colors.blue;
      case 'entregue':
        return Colors.green;
      case 'cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData iconeStatus(String status) {
    switch (status.toLowerCase()) {
      case 'novo':
        return Icons.shopping_bag_outlined;
      case 'aceito':
        return Icons.verified_outlined;
      case 'preparando':
        return Icons.restaurant_menu;
      case 'saiu_para_entrega':
        return Icons.local_shipping;
      case 'entregue':
        return Icons.check_circle_outline;
      case 'cancelado':
        return Icons.cancel_outlined;
      default:
        return Icons.receipt_long;
    }
  }

  String textoStatus(String status) {
    switch (status.toLowerCase()) {
      case 'novo':
        return 'Aguardando aceite';
      case 'aceito':
        return 'Pedido aceito';
      case 'preparando':
        return 'Em preparação';
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

  void abrirDetalhes(Map<String, dynamic> pedido) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PedidoDetalhePage(pedido: pedido)),
    );

    carregarPedidos();
  }

  bool podeCancelarPedido(Map<String, dynamic> pedido) {
    return statusPedidoPermiteCancelamentoCliente(pedido['status']);
  }

  Future<void> confirmarCancelamentoPedidoLista(
    Map<String, dynamic> pedido,
  ) async {
    if (pedidoCancelandoId.isNotEmpty || !podeCancelarPedido(pedido)) {
      return;
    }

    final numero = pedido['numero_pedido']?.toString() ?? '-';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancelar pedido?'),
          content: Text(
            'Deseja cancelar o pedido #$numero? A loja sera avisada automaticamente.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancelar pedido'),
            ),
          ],
        );
      },
    );

    if (confirmar == true) {
      await cancelarPedidoLista(pedido);
    }
  }

  Future<void> cancelarPedidoLista(Map<String, dynamic> pedido) async {
    final pedidoId = pedido['id']?.toString().trim() ?? '';
    final mercadoId = sessao.SessaoMercadoCliente.mercadoIdObrigatorio;

    if (pedidoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido sem identificacao.')),
      );
      return;
    }

    setState(() {
      pedidoCancelandoId = pedidoId;
    });

    try {
      await Supabase.instance.client.rpc(
        'cancelar_pedido_cliente_app',
        params: {'p_pedido_id': pedidoId, 'p_mercado_id': mercadoId},
      );

      await PushNotificationService.instance.notificarEventoPedido(
        evento: 'PEDIDO_CANCELADO',
        pedidoId: pedidoId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        for (final item in pedidos) {
          if (item['id']?.toString() == pedidoId) {
            item['status'] = 'cancelado';
            item['cancelado_por'] = 'cliente';
            item['cancelado_em'] = DateTime.now().toIso8601String();
          }
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido cancelado com sucesso.')),
      );

      await carregarPedidos();
    } catch (e) {
      if (!mounted) {
        return;
      }

      final erro = e.toString().toLowerCase();
      final mensagem = erro.contains('cancelar_pedido_cliente_app')
          ? 'A funcao de cancelamento ainda nao foi instalada no banco da loja.'
          : erro.contains('pedido nao pode mais ser cancelado') ||
                erro.contains('pedido nÃ£o pode mais ser cancelado')
          ? 'Este pedido nao pode mais ser cancelado pelo app.'
          : 'Nao foi possivel cancelar o pedido. Tente novamente.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensagem), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          pedidoCancelandoId = '';
        });
      }
    }
  }

  Widget botaoCancelarPedidoLista(Map<String, dynamic> pedido) {
    if (!podeCancelarPedido(pedido)) {
      return const SizedBox.shrink();
    }

    final pedidoId = pedido['id']?.toString() ?? '';
    final cancelando = pedidoCancelandoId == pedidoId;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: cancelando
            ? null
            : () => confirmarCancelamentoPedidoLista(pedido),
        icon: cancelando
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cancel_outlined, size: 18),
        label: Text(cancelando ? 'Cancelando...' : 'Cancelar pedido'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: BorderSide(color: Colors.red.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget pedidoAtualCard() {
    final pedido = pedidoAtual;

    if (pedido == null) {
      return const SizedBox.shrink();
    }

    final status = pedido['status']?.toString() ?? 'novo';

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTemaService.primaria.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: AppTemaService.primaria.withOpacity(0.15),
                child: Icon(
                  iconeStatus(status),
                  color: AppTemaService.primaria,
                  size: 34,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pedido atual',
                      style: TextStyle(
                        color: AppTemaService.primaria,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      textoStatus(status),
                      style: TextStyle(fontSize: 15, color: Colors.black87),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Pedido #${pedido['numero_pedido'] ?? '-'}',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    if (pedidoReajustado(pedido)) ...[
                      SizedBox(height: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.amber.withOpacity(0.35),
                          ),
                        ),
                        child: const Text(
                          'Total reajustado',
                          style: TextStyle(
                            color: Color(0xFF92400E),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => abrirDetalhes(pedido),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTemaService.primaria,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text('Ver pedido'),
              ),
            ],
          ),
          if (podeCancelarPedido(pedido)) ...[
            const SizedBox(height: 12),
            botaoCancelarPedidoLista(pedido),
          ],
        ],
      ),
    );
  }

  Widget pedidoCard(Map<String, dynamic> pedido) {
    final status = pedido['status']?.toString() ?? 'novo';
    final numero = pedido['numero_pedido']?.toString() ?? '-';
    final qtdItens = pedido['quantidade_itens'] ?? 0;
    final reajustado = pedidoReajustado(pedido);
    final totalAnterior = valorTotalAnteriorPedido(pedido);
    final mostrarTotalAnterior = mostrarTotalAnteriorPedido(pedido);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => abrirDetalhes(pedido),
      child: Container(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppTemaService.primaria.withValues(alpha: 0.16),
            width: 1.6,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTemaService.primaria.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: corStatus(status).withOpacity(0.14),
                  child: Icon(
                    iconeStatus(status),
                    color: corStatus(status),
                    size: 29,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pedido #$numero',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        formatarData(pedido['criado_em']),
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        pedido['cliente_nome']?.toString().isNotEmpty == true
                            ? pedido['cliente_nome'].toString()
                            : nomeMercado(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: corStatus(status).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              textoStatus(status),
                              style: TextStyle(
                                color: corStatus(status),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (reajustado)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.amber.withOpacity(0.30),
                                ),
                              ),
                              child: const Text(
                                'Reajustado',
                                style: TextStyle(
                                  color: Color(0xFF92400E),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 104),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (mostrarTotalAnterior) ...[
                        Text(
                          formatarMoeda(totalAnterior),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black45,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.lineThrough,
                            decorationThickness: 2,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        formatarMoeda(pedido['total']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: reajustado
                              ? const Color(0xFF166534)
                              : AppTemaService.primaria,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (reajustado) ...[
                        const SizedBox(height: 3),
                        const Text(
                          'Total atualizado',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFF92400E),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const SizedBox(height: 7),
                      Text(
                        '$qtdItens itens',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: Colors.black54),
              ],
            ),
            if (podeCancelarPedido(pedido)) ...[
              const SizedBox(height: 12),
              botaoCancelarPedidoLista(pedido),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pedidosNovos = pedidos
        .where((p) => (p['status']?.toString() ?? 'novo') == 'novo')
        .length;

    return Scaffold(
      backgroundColor: AppTemaService.fundo,
      appBar: AppBar(
        title: const Text('Meus pedidos'),
        leading: widget.onVoltarInicio != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onVoltarInicio,
              )
            : null,
        backgroundColor: AppTemaService.primaria,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Atualizar pedidos',
            onPressed: carregarPedidos,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none),
                if (pedidosNovos > 0)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      height: 18,
                      constraints: const BoxConstraints(minWidth: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFC107),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        pedidosNovos > 9 ? '9+' : '$pedidosNovos',
                        style: const TextStyle(
                          color: Color(0xFF1F2937),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: carregando
          ? Center(
              child: CircularProgressIndicator(color: AppTemaService.primaria),
            )
          : RefreshIndicator(
              color: AppTemaService.primaria,
              onRefresh: carregarPedidos,
              child: ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 14, 18, 8),
                    child: Text(
                      'Acompanhe seus pedidos',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (pedidos.isNotEmpty) pedidoAtualCard(),
                  if (pedidos.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(child: Text('Nenhum pedido encontrado')),
                    )
                  else
                    ...pedidos.map(pedidoCard),
                ],
              ),
            ),
    );
  }
}

class PedidoDetalhePage extends StatefulWidget {
  final Map<String, dynamic> pedido;

  const PedidoDetalhePage({super.key, required this.pedido});

  @override
  State<PedidoDetalhePage> createState() => _PedidoDetalhePageState();
}

class _PedidoDetalhePageState extends State<PedidoDetalhePage> {
  bool carregando = true;
  bool cancelandoPedido = false;
  List<Map<String, dynamic>> itens = [];

  @override
  void initState() {
    super.initState();
    carregarItens();
  }

  bool erroSessaoExpirada(Object erro) {
    final textoErro = erro.toString().toLowerCase();

    return textoErro.contains('jwt expired') ||
        textoErro.contains('pgrst303') ||
        textoErro.contains('unauthorized') ||
        textoErro.contains('401');
  }

  Future<bool> tentarRenovarSessao() async {
    try {
      final resposta = await Supabase.instance.client.auth.refreshSession();

      return resposta.session != null ||
          Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> carregarItens({bool tentouRenovarSessao = false}) async {
    try {
      final respostaPedido = await Supabase.instance.client
          .from('pedidos')
          .select()
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('id', widget.pedido['id'])
          .maybeSingle();

      final resposta = await Supabase.instance.client
          .from('pedido_itens')
          .select()
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('pedido_id', widget.pedido['id'])
          .order('nome_produto');

      if (!mounted) return;

      setState(() {
        if (respostaPedido != null) {
          widget.pedido.addAll(Map<String, dynamic>.from(respostaPedido));
        }

        itens = List<Map<String, dynamic>>.from(resposta);
        carregando = false;
      });
    } catch (e) {
      if (!mounted) return;

      if (!tentouRenovarSessao && erroSessaoExpirada(e)) {
        final renovou = await tentarRenovarSessao();

        if (renovou && mounted) {
          await carregarItens(tentouRenovarSessao: true);
          return;
        }
      }

      setState(() {
        carregando = false;
      });
    }
  }

  String telefoneWhatsAppFormatado() {
    final somenteNumeros = whatsappMercadoPedido().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    if (somenteNumeros.length == 13 && somenteNumeros.startsWith('55')) {
      final ddd = somenteNumeros.substring(2, 4);
      final parte1 = somenteNumeros.substring(4, 9);
      final parte2 = somenteNumeros.substring(9);
      return '($ddd) $parte1-$parte2';
    }

    if (somenteNumeros.length == 11) {
      final ddd = somenteNumeros.substring(0, 2);
      final parte1 = somenteNumeros.substring(2, 7);
      final parte2 = somenteNumeros.substring(7);
      return '($ddd) $parte1-$parte2';
    }

    return whatsappMercadoPedido();
  }

  Future<void> chamarWhatsApp() async {
    final numero = whatsappMercadoPedido().replaceAll(RegExp(r'[^0-9]'), '');

    if (numero.isEmpty || numero == '5577999999999') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Configure o WhatsApp da loja no cadastro do mercado.'),
        ),
      );
      return;
    }

    final numeroPedido = widget.pedido['numero_pedido']?.toString() ?? '-';

    final mensagem = Uri.encodeComponent(
      'Olá, gostaria de falar sobre o pedido #$numeroPedido.',
    );

    final uri = Uri.parse('https://wa.me/$numero?text=$mensagem');

    final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!abriu && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir o WhatsApp.')),
      );
    }
  }

  String formatarMoeda(dynamic valor) {
    final numero = double.tryParse(valor.toString()) ?? 0;
    return 'R\$ ${numero.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  double numero(dynamic valor) {
    if (valor == null) {
      return 0;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    return double.tryParse(valor.toString().replaceAll(',', '.').trim()) ?? 0;
  }

  bool valorBool(dynamic valor) {
    if (valor is bool) return valor;
    if (valor is num) return valor == 1;

    final texto = valor?.toString().trim().toLowerCase() ?? '';

    return texto == 'true' || texto == '1' || texto == 'sim';
  }

  String statusPedidoAtual() {
    final status = widget.pedido['status']?.toString().trim().toLowerCase();

    return status == null || status.isEmpty ? 'novo' : status;
  }

  bool podeCancelarPedido() {
    return statusPedidoPermiteCancelamentoCliente(statusPedidoAtual());
  }

  bool pedidoCancelado() {
    return statusPedidoAtual() == 'cancelado';
  }

  Future<void> confirmarCancelamentoPedido() async {
    if (cancelandoPedido || !podeCancelarPedido()) {
      return;
    }

    final numero = widget.pedido['numero_pedido']?.toString() ?? '-';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancelar pedido?'),
          content: Text(
            'Deseja cancelar o pedido #$numero? A loja será avisada automaticamente.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancelar pedido'),
            ),
          ],
        );
      },
    );

    if (confirmar == true) {
      await cancelarPedido();
    }
  }

  Future<void> cancelarPedido() async {
    final pedidoId = widget.pedido['id']?.toString().trim() ?? '';
    final mercadoId = sessao.SessaoMercadoCliente.mercadoIdObrigatorio;

    if (pedidoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido sem identificação.')),
      );
      return;
    }

    setState(() {
      cancelandoPedido = true;
    });

    try {
      await Supabase.instance.client.rpc(
        'cancelar_pedido_cliente_app',
        params: {'p_pedido_id': pedidoId, 'p_mercado_id': mercadoId},
      );

      await PushNotificationService.instance.notificarEventoPedido(
        evento: 'PEDIDO_CANCELADO',
        pedidoId: pedidoId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        widget.pedido['status'] = 'cancelado';
        widget.pedido['cancelado_por'] = 'cliente';
        widget.pedido['cancelado_em'] = DateTime.now().toIso8601String();
      });

      await carregarItens();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido cancelado com sucesso.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      final erro = e.toString().toLowerCase();
      final mensagem = erro.contains('cancelar_pedido_cliente_app')
          ? 'A função de cancelamento ainda não foi instalada no banco da loja.'
          : erro.contains('pedido nao pode mais ser cancelado') ||
                erro.contains('pedido não pode mais ser cancelado')
          ? 'Este pedido não pode mais ser cancelado pelo app.'
          : 'Não foi possível cancelar o pedido. Tente novamente.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensagem), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          cancelandoPedido = false;
        });
      }
    }
  }

  String formatarPesoKg(dynamic valor) {
    final peso = numero(valor);

    if (peso <= 0) {
      return '-';
    }

    var texto = peso.toStringAsFixed(3).replaceAll('.', ',');

    while (texto.endsWith('0')) {
      texto = texto.substring(0, texto.length - 1);
    }

    if (texto.endsWith(',')) {
      texto = texto.substring(0, texto.length - 1);
    }

    return '${texto}kg';
  }

  bool itemPesoVariavel(Map<String, dynamic> item) {
    return valorBool(item['peso_variavel']);
  }

  bool itemReajustado(Map<String, dynamic> item) {
    if (!itemPesoVariavel(item)) {
      return false;
    }

    final pesoReal = numero(item['peso_real_kg']);
    final totalFinal = numero(item['total_final']);

    return pesoReal > 0 && totalFinal > 0;
  }

  bool pedidoReajustado() {
    return valorBool(widget.pedido['total_recalculado']) ||
        itens.any(itemReajustado);
  }

  double valorItemExibicao(Map<String, dynamic> item) {
    final totalFinal = numero(item['total_final']);

    if (totalFinal > 0) {
      return totalFinal;
    }

    final totalEstimado = numero(item['total_estimado']);

    if (totalEstimado > 0) {
      return totalEstimado;
    }

    return numero(item['total']);
  }

  double valorItemAnterior(Map<String, dynamic> item) {
    final totalEstimado = numero(item['total_estimado']);

    if (totalEstimado > 0) {
      return totalEstimado;
    }

    return numero(item['total']);
  }

  bool mostrarValorAnteriorItem(Map<String, dynamic> item) {
    final valorAnterior = valorItemAnterior(item);
    final valorAtual = valorItemExibicao(item);

    return itemReajustado(item) &&
        valorAnterior > 0 &&
        (valorAnterior - valorAtual).abs() > 0.009;
  }

  double valorTotalAnteriorPedido() {
    final camposPossiveis = [
      'total_original',
      'total_estimado',
      'subtotal_estimado',
      'valor_estimado',
      'total_sem_reajuste',
      'total_anterior',
      'total_inicial',
    ];

    for (final campo in camposPossiveis) {
      final valor = numero(widget.pedido[campo]);

      if (valor > 0) {
        return valor;
      }
    }

    final somaItens = itens.fold<double>(0, (soma, item) {
      return soma + valorItemAnterior(item);
    });

    if (somaItens > 0) {
      return somaItens;
    }

    return 0;
  }

  bool mostrarTotalAnteriorPedido() {
    final totalAtual = numero(widget.pedido['total']);
    final totalAnterior = valorTotalAnteriorPedido();

    return pedidoReajustado() &&
        totalAnterior > 0 &&
        (totalAnterior - totalAtual).abs() > 0.009;
  }

  String formatarData(dynamic valor) {
    if (valor == null) return '';

    try {
      final data = DateTime.parse(valor.toString()).toLocal();

      final dia = data.day.toString().padLeft(2, '0');
      final mes = data.month.toString().padLeft(2, '0');
      final ano = data.year.toString();
      final hora = data.hour.toString().padLeft(2, '0');
      final minuto = data.minute.toString().padLeft(2, '0');

      return '$dia/$mes/$ano às $hora:$minuto';
    } catch (_) {
      return valor.toString();
    }
  }

  String codigoEntregaPedido() {
    final codigo = widget.pedido['codigo_entrega']?.toString().trim() ?? '';
    final numeros = codigo.replaceAll(RegExp(r'[^0-9]'), '');

    if (numeros.length == 4) {
      return numeros;
    }

    return '';
  }

  Widget cardCodigoEntregaCliente() {
    final codigo = codigoEntregaPedido();

    if (codigo.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFFFA000).withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Color(0xFFFFA000),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.password, color: Colors.white, size: 24),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Código de entrega',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Informe este código ao entregador para confirmar a entrega.',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFFA000).withOpacity(0.45),
              ),
            ),
            child: Text(
              codigo,
              style: TextStyle(
                color: AppTemaService.primaria,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool statusAtivo(String passo) {
    final status =
        widget.pedido['status']?.toString().trim().toLowerCase() ?? 'novo';

    if (status == 'cancelado') {
      return passo == 'novo';
    }

    if (passo == 'novo') return true;

    if (passo == 'aceito') {
      return status == 'aceito' ||
          status == 'preparando' ||
          status == 'saiu_para_entrega' ||
          status == 'entregue';
    }

    if (passo == 'preparando') {
      return status == 'preparando' ||
          status == 'saiu_para_entrega' ||
          status == 'entregue';
    }

    if (passo == 'saiu_para_entrega') {
      return status == 'saiu_para_entrega' || status == 'entregue';
    }

    if (passo == 'entregue') {
      return status == 'entregue';
    }

    return false;
  }

  bool statusAtual(String passo) {
    final status = widget.pedido['status']?.toString() ?? 'novo';
    return status == passo;
  }

  Color corPasso(String passo) {
    if (statusAtivo(passo)) {
      if (passo == 'saiu_para_entrega') return Colors.blue;
      return Colors.green;
    }

    return Colors.grey.shade400;
  }

  IconData iconePasso(String passo) {
    if (statusAtivo(passo)) {
      if (passo == 'saiu_para_entrega') return Icons.local_shipping;
      return Icons.check;
    }

    return Icons.circle_outlined;
  }

  Widget passoPedido({
    required String passo,
    required String titulo,
    required String descricao,
  }) {
    final ativo = statusAtivo(passo);
    final atual = statusAtual(passo);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: corPasso(passo),
              child: Icon(iconePasso(passo), color: Colors.white, size: 20),
            ),
            if (passo != 'entregue')
              Container(
                width: 3,
                height: 58,
                color: ativo
                    ? Colors.green.withOpacity(0.35)
                    : Colors.grey[300],
              ),
          ],
        ),
        SizedBox(width: 18),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: atual && passo == 'saiu_para_entrega'
                        ? Colors.blue
                        : Colors.black,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  descricao,
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget cardContatoWhatsApp() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F7ED),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF25D366).withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Color(0xFF25D366),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.chat, color: Colors.white, size: 23),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Precisa de ajuda?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      'WhatsApp: ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        telefoneWhatsAppFormatado(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          ElevatedButton(
            onPressed: chamarWhatsApp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Chamar',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget cardAvisoReajustePedido() {
    if (!pedidoReajustado()) {
      return const SizedBox.shrink();
    }

    final itensReajustados = itens.where(itemReajustado).length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFFFA000).withOpacity(0.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFFFFA000),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.scale_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total do pedido reajustado',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  itensReajustados > 0
                      ? 'O mercado conferiu o peso real de $itensReajustados produto(s) de peso variável. O valor total foi atualizado.'
                      : 'O valor total foi atualizado após a conferência do mercado.',
                  style: const TextStyle(
                    color: Color(0xFF4B5563),
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Novo total: ${formatarMoeda(widget.pedido['total'])}',
                  style: const TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget cardPedidoCanceladoCliente() {
    if (!pedidoCancelado()) {
      return const SizedBox.shrink();
    }

    final canceladoPor = widget.pedido['cancelado_por']?.toString() ?? '';
    final textoOrigem = canceladoPor == 'cliente'
        ? 'Cancelado por você.'
        : 'Pedido cancelado.';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.red.withOpacity(0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cancel_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pedido cancelado',
                  style: TextStyle(
                    color: Color(0xFF991B1B),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$textoOrigem A loja já recebeu a atualização.',
                  style: const TextStyle(
                    color: Color(0xFF7F1D1D),
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget botaoCancelarPedido() {
    if (!podeCancelarPedido()) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      child: OutlinedButton.icon(
        onPressed: cancelandoPedido ? null : confirmarCancelamentoPedido,
        icon: cancelandoPedido
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cancel_outlined),
        label: Text(
          cancelandoPedido ? 'Cancelando pedido...' : 'Cancelar pedido',
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: BorderSide(color: Colors.red.withOpacity(0.45)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget itemPedido(Map<String, dynamic> item) {
    final pesoVariavel = itemPesoVariavel(item);
    final reajustado = itemReajustado(item);
    final valorExibicao = valorItemExibicao(item);
    final valorAnterior = valorItemAnterior(item);
    final mostrarValorAnterior = mostrarValorAnteriorItem(item);
    final quantidade = item['quantidade'] ?? 0;
    final unidade = item['unidade_medida']?.toString().trim().isNotEmpty == true
        ? item['unidade_medida'].toString()
        : 'un.';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pesoVariavel
            ? const Color(0xFFFFF7E6).withOpacity(0.55)
            : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: pesoVariavel
              ? const Color(0xFFFFA000).withOpacity(0.32)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: pesoVariavel
                  ? const Color(0xFFFFA000).withOpacity(0.14)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              pesoVariavel
                  ? Icons.scale_outlined
                  : Icons.shopping_basket_outlined,
              color: pesoVariavel
                  ? const Color(0xFFFFA000)
                  : AppTemaService.primaria,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['nome_produto']?.toString() ?? 'Produto',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                if (pesoVariavel) ...[
                  Text(
                    '$quantidade unidade(s) • vendido por peso variável',
                    style: const TextStyle(
                      color: Color(0xFF4B5563),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Peso estimado: ${formatarPesoKg(item['peso_estimado_kg'])}',
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12.5,
                    ),
                  ),
                  if (numero(item['peso_real_kg']) > 0) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Peso conferido: ${formatarPesoKg(item['peso_real_kg'])}',
                      style: const TextStyle(
                        color: Color(0xFF15803D),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 3),
                    const Text(
                      'Aguardando conferência do peso real',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  if (reajustado) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Valor reajustado pelo mercado',
                        style: TextStyle(
                          color: Color(0xFF166534),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ] else
                  Text(
                    '$quantidade $unidade',
                    style: const TextStyle(color: Colors.black54),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 86),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (mostrarValorAnterior) ...[
                  Text(
                    formatarMoeda(valorAnterior),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black45,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.lineThrough,
                      decorationThickness: 2,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  formatarMoeda(valorExibicao),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: reajustado
                        ? const Color(0xFF166534)
                        : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (pesoVariavel && !reajustado) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Estimado',
                    style: TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pedido = widget.pedido;
    final numero = pedido['numero_pedido']?.toString() ?? '-';

    return Scaffold(
      backgroundColor: AppTemaService.fundo,
      appBar: AppBar(
        title: Text('Pedido #$numero'),
        backgroundColor: AppTemaService.primaria,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: carregando
          ? Center(
              child: CircularProgressIndicator(color: AppTemaService.primaria),
            )
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTemaService.primaria.withValues(alpha: 0.16),
                      width: 1.6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTemaService.primaria.withValues(alpha: 0.08),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  formatarData(pedido['criado_em']),
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  pedido['cliente_nome']
                                              ?.toString()
                                              .isNotEmpty ==
                                          true
                                      ? pedido['cliente_nome'].toString()
                                      : nomeMercado(),
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (mostrarTotalAnteriorPedido()) ...[
                                Text(
                                  formatarMoeda(valorTotalAnteriorPedido()),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.black45,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.lineThrough,
                                    decorationThickness: 2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              Text(
                                formatarMoeda(pedido['total']),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: mostrarTotalAnteriorPedido()
                                      ? const Color(0xFF166534)
                                      : AppTemaService.primaria,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text('${itens.length} itens'),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 14),
                      cardContatoWhatsApp(),
                      cardCodigoEntregaCliente(),
                      cardAvisoReajustePedido(),
                      cardPedidoCanceladoCliente(),
                      botaoCancelarPedido(),
                    ],
                  ),
                ),
                SizedBox(height: 28),
                Text(
                  'Acompanhe seu pedido',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 22),
                passoPedido(
                  passo: 'novo',
                  titulo: 'Aguardando aceite',
                  descricao: 'A loja recebeu seu pedido e fará a confirmação.',
                ),
                passoPedido(
                  passo: 'aceito',
                  titulo: 'Pedido aceito',
                  descricao: 'A loja confirmou que vai atender seu pedido.',
                ),
                passoPedido(
                  passo: 'preparando',
                  titulo: 'Em preparação',
                  descricao: 'Estamos separando os produtos do seu pedido.',
                ),
                passoPedido(
                  passo: 'saiu_para_entrega',
                  titulo: 'Saiu para entrega',
                  descricao: 'Seu pedido está a caminho!',
                ),
                passoPedido(
                  passo: 'entregue',
                  titulo: 'Entregue',
                  descricao: statusAtivo('entregue')
                      ? 'Pedido entregue com sucesso.'
                      : 'Aguardando entrega.',
                ),
                Divider(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Seus itens (${itens.length})',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 18),
                if (itens.isEmpty)
                  Text('Nenhum item encontrado')
                else
                  ...itens.map(itemPedido),
              ],
            ),
    );
  }
}

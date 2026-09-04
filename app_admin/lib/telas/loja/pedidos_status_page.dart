import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/central_service.dart';
import '../../services/monitor_pedidos_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/sessao_loja.dart';
import 'scanner.dart';

String telefoneWhatsAppEntrega(dynamic valor) {
  final numeros = valor?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';

  if (numeros.isEmpty) {
    return '';
  }

  if (numeros.startsWith('55') &&
      (numeros.length == 12 || numeros.length == 13)) {
    return numeros;
  }

  if (numeros.length == 10 || numeros.length == 11) {
    return '55$numeros';
  }

  return numeros;
}

Future<bool> abrirWhatsAppEntrega(Map<String, dynamic> pedido) async {
  final telefone = telefoneWhatsAppEntrega(pedido['cliente_telefone']);

  if (telefone.isEmpty) {
    return false;
  }

  final mensagem = Uri.encodeComponent(
    'Ol\u00e1! Tenho uma entrega para voc\u00ea!',
  );
  final uriApp = Uri.parse('whatsapp://send?phone=$telefone&text=$mensagem');
  final uriWeb = Uri.parse('https://wa.me/$telefone?text=$mensagem');

  try {
    if (await launchUrl(uriApp, mode: LaunchMode.externalApplication)) {
      return true;
    }
  } catch (_) {
    // Tenta o link web abaixo quando o esquema do WhatsApp nao estiver disponivel.
  }

  try {
    return launchUrl(uriWeb, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

class PedidosStatusPage extends StatefulWidget {
  final String status;
  final String titulo;
  final Color cor;

  const PedidosStatusPage({
    super.key,
    required this.status,
    required this.titulo,
    required this.cor,
  });

  @override
  State<PedidosStatusPage> createState() => _PedidosStatusPageState();
}

class _PedidosStatusPageState extends State<PedidosStatusPage> {
  bool carregando = true;
  List<Map<String, dynamic>> pedidos = [];

  @override
  void initState() {
    super.initState();
    iniciarMonitorPedidos();
    carregarPedidos();
  }

  Color get corDestaque {
    if (widget.status == 'todos') {
      return SessaoLoja.corPrimaria;
    }

    return widget.cor;
  }

  Future<void> iniciarMonitorPedidos() async {
    await MonitorPedidosService.instance.iniciar(
      onNovoPedido: () async {
        if (!mounted) {
          return;
        }

        await carregarPedidos();
      },
    );
  }

  Future<void> carregarPedidos() async {
    if (!SessaoLoja.lojaSelecionada || SessaoLoja.supabaseLoja == null) {
      setState(() {
        carregando = false;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma loja selecionada'),
          backgroundColor: Colors.red,
        ),
      );

      return;
    }

    setState(() {
      carregando = true;
    });

    try {
      dynamic resposta;

      if (widget.status == 'todos') {
        resposta = await SessaoLoja.supabaseLoja!
            .from('pedidos')
            .select()
            .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
            .order('criado_em', ascending: false);
      } else {
        resposta = await SessaoLoja.supabaseLoja!
            .from('pedidos')
            .select()
            .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
            .eq('status', widget.status)
            .order('criado_em', ascending: false);
      }

      if (!mounted) return;

      setState(() {
        pedidos = List<Map<String, dynamic>>.from(resposta);
        carregando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao carregar pedidos: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String texto(dynamic valor) {
    final texto = valor?.toString().trim() ?? '';

    if (texto.isEmpty) {
      return '-';
    }

    return texto;
  }

  String formatarMoeda(dynamic valor) {
    final numero = double.tryParse(valor?.toString() ?? '') ?? 0;
    return 'R\$ ${numero.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String textoStatus(String status) {
    switch (status) {
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

  Future<void> abrirMapa(String? url) async {
    if (url == null || url.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido sem localização enviada')),
      );
      return;
    }

    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> abrirWhatsAppCliente(Map<String, dynamic> pedido) async {
    final abriu = await abrirWhatsAppEntrega(pedido);

    if (!mounted || abriu) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'N\u00e3o foi poss\u00edvel abrir o WhatsApp do cliente.',
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<bool> atualizarStatus(
    String pedidoId,
    String novoStatus, {
    Map<String, dynamic>? dadosExtras,
  }) async {
    if (!SessaoLoja.lojaSelecionada || SessaoLoja.supabaseLoja == null) {
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma loja selecionada'),
          backgroundColor: Colors.red,
        ),
      );

      return false;
    }

    try {
      final dadosAtualizacao = <String, dynamic>{
        'status': novoStatus,
        'atualizado_em': DateTime.now().toUtc().toIso8601String(),
        ...?dadosExtras,
      };

      dynamic consulta = SessaoLoja.supabaseLoja!
          .from('pedidos')
          .update(dadosAtualizacao)
          .eq('id', pedidoId)
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);

      if (novoStatus == 'aceito') {
        consulta = consulta.eq('status', 'novo');
      } else if (novoStatus == 'preparando') {
        consulta = consulta.eq('status', 'aceito');
      }

      final resposta = await consulta.select('id');

      if (resposta is List && resposta.isEmpty) {
        throw Exception(
          'O pedido já foi atualizado por outro funcionário. Atualize a tela.',
        );
      }

      await PushNotificationService.instance.notificarStatusPedido(
        pedidoId: pedidoId,
      );

      await carregarPedidos();

      if (!mounted) return true;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status atualizado com sucesso')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao atualizar status: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  Future<bool> recusarPedido(String pedidoId) async {
    if (!SessaoLoja.lojaSelecionada || SessaoLoja.supabaseLoja == null) {
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma loja selecionada'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    try {
      await SessaoLoja.supabaseLoja!.rpc(
        'recusar_pedido_loja_app',
        params: {
          'p_pedido_id': pedidoId,
          'p_mercado_id': SessaoLoja.mercadoIdObrigatorio,
          'p_motivo': 'Pedido recusado pela loja',
        },
      );

      await PushNotificationService.instance.notificarStatusPedido(
        pedidoId: pedidoId,
      );
      await carregarPedidos();

      if (!mounted) return true;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pedido recusado com sucesso')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao recusar pedido: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }

  void abrirDetalhes(Map<String, dynamic> pedido) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return DetalhesPedidoSheet(
          pedido: pedido,
          onAbrirMapa: abrirMapa,
          onAtualizarStatus: atualizarStatus,
          onRecusarPedido: recusarPedido,
        );
      },
    );
  }

  Widget iconeInfo({required IconData icone, required Color cor}) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: cor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icone, color: cor, size: 18),
    );
  }

  Widget cardPedido(Map<String, dynamic> pedido) {
    final numeroPedido = texto(pedido['numero_pedido']);
    final cliente = texto(pedido['cliente_nome']);
    final telefone = texto(pedido['cliente_telefone']);
    final responsavel = texto(pedido['responsavel_nome']);
    final total = formatarMoeda(pedido['total']);
    final cor = corDestaque;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => abrirDetalhes(pedido),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cor.withOpacity(0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: cor,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          iconeInfo(
                            icone: Icons.shopping_bag_outlined,
                            cor: cor,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pedido #$numeroPedido',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: cor,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  cliente,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF111827),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.grey.shade600,
                            size: 24,
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      Container(height: 1, color: Colors.grey.shade200),

                      const SizedBox(height: 5),

                      if (responsavel != '-') ...[
                        Row(
                          children: [
                            iconeInfo(
                              icone: Icons.badge_outlined,
                              cor: Colors.indigo,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Responsável pelo pedido',
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    responsavel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF111827),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                      ],

                      Row(
                        children: [
                          iconeInfo(icone: Icons.phone, cor: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Telefone',
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  telefone,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF111827),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => abrirWhatsAppCliente(pedido),
                            child: Container(
                              height: 34,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF22C55E),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  SizedBox(width: 5),
                                  Text(
                                    'WhatsApp',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 5),

                      Row(
                        children: [
                          iconeInfo(
                            icone: Icons.attach_money,
                            cor: Colors.green,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Total da compra',
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  total,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget listaVazia() {
    return ListView(
      children: const [
        SizedBox(height: 180),
        Center(
          child: Text(
            'Nenhum pedido encontrado',
            style: TextStyle(color: Colors.black54, fontSize: 15),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cor = corDestaque;

    return Scaffold(
      backgroundColor: SessaoLoja.corFundo,
      appBar: AppBar(
        title: Text(widget.titulo),
        backgroundColor: cor,
        foregroundColor: Colors.white,
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : pedidos.isEmpty
          ? RefreshIndicator(onRefresh: carregarPedidos, child: listaVazia())
          : RefreshIndicator(
              onRefresh: carregarPedidos,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                itemCount: pedidos.length,
                itemBuilder: (context, index) {
                  final pedido = pedidos[index];

                  return cardPedido(pedido);
                },
              ),
            ),
    );
  }
}

class DetalhesPedidoSheet extends StatefulWidget {
  final Map<String, dynamic> pedido;
  final Function(String?) onAbrirMapa;
  final Future<bool> Function(
    String pedidoId,
    String novoStatus, {
    Map<String, dynamic>? dadosExtras,
  })
  onAtualizarStatus;
  final Future<bool> Function(String pedidoId) onRecusarPedido;
  final bool modoPagina;

  const DetalhesPedidoSheet({
    super.key,
    required this.pedido,
    required this.onAbrirMapa,
    required this.onAtualizarStatus,
    required this.onRecusarPedido,
    this.modoPagina = false,
  });

  @override
  State<DetalhesPedidoSheet> createState() => _DetalhesPedidoSheetState();
}

class _DetalhesPedidoSheetState extends State<DetalhesPedidoSheet> {
  bool carregando = true;
  List<Map<String, dynamic>> itens = [];

  final TextEditingController codigoBarrasController = TextEditingController();
  final TextEditingController codigoEntregaController = TextEditingController();
  final TextEditingController numeroNfceController = TextEditingController();

  final FocusNode codigoBarrasFocus = FocusNode();
  final FocusNode codigoEntregaFocus = FocusNode();
  final GlobalKey botaoConfirmarEntregaKey = GlobalKey();

  String? erroCodigoEntrega;
  String? erroNumeroNfce;
  bool salvandoNfce = false;
  bool aceitandoPedido = false;
  bool recusandoPedido = false;
  bool colocandoEmPreparacao = false;
  bool permitirConferenciaManualItens = true;

  final Map<String, double> quantidadesConferidas = {};

  @override
  void initState() {
    super.initState();
    numeroNfceController.text =
        widget.pedido['numero_nfce']?.toString().trim() ??
        widget.pedido['nfce_numero']?.toString().trim() ??
        '';
    carregarItens();
  }

  @override
  void dispose() {
    codigoBarrasController.dispose();
    codigoEntregaController.dispose();
    numeroNfceController.dispose();
    codigoBarrasFocus.dispose();
    codigoEntregaFocus.dispose();
    super.dispose();
  }

  void focarLeitorWeb() {
    if (!kIsWeb) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          normalizarStatus(widget.pedido['status']) == 'preparando') {
        codigoBarrasFocus.requestFocus();
      }
    });
  }

  String categoriaItemPedido(Map<String, dynamic> item) {
    const camposCategoria = [
      'categoria',
      'categoria_nome',
      'nome_categoria',
      'grupo',
      'nome_grupo',
    ];

    for (final campo in camposCategoria) {
      final categoria = item[campo]?.toString().trim() ?? '';
      if (categoria.isNotEmpty) return categoria;
    }

    return 'Sem categoria';
  }

  void ordenarItensParaSeparacao(List<Map<String, dynamic>> listaItens) {
    if (normalizarStatus(widget.pedido['status']) != 'preparando') return;

    listaItens.sort((itemA, itemB) {
      final categoriaA = categoriaItemPedido(itemA);
      final categoriaB = categoriaItemPedido(itemB);
      final semCategoriaA = categoriaA == 'Sem categoria';
      final semCategoriaB = categoriaB == 'Sem categoria';

      if (semCategoriaA != semCategoriaB) return semCategoriaA ? 1 : -1;

      final comparacaoCategoria = categoriaA.toLowerCase().compareTo(
        categoriaB.toLowerCase(),
      );
      if (comparacaoCategoria != 0) return comparacaoCategoria;

      final nomeA =
          itemA['nome_produto']?.toString().trim().toLowerCase() ?? '';
      final nomeB =
          itemB['nome_produto']?.toString().trim().toLowerCase() ?? '';
      return nomeA.compareTo(nomeB);
    });
  }

  Future<void> carregarItens() async {
    if (!SessaoLoja.lojaSelecionada || SessaoLoja.supabaseLoja == null) {
      setState(() {
        carregando = false;
      });

      return;
    }

    try {
      await carregarPreferenciaConferenciaManualItens();

      final resposta = await SessaoLoja.supabaseLoja!
          .from('pedido_itens')
          .select()
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
          .eq('pedido_id', widget.pedido['id'])
          .order('nome_produto');

      if (!mounted) return;

      final listaItens = List<Map<String, dynamic>>.from(resposta);
      await corrigirConferenciaLegadaPreparacao(listaItens);
      ordenarItensParaSeparacao(listaItens);

      if (!mounted) return;

      setState(() {
        itens = listaItens;

        for (final item in listaItens) {
          quantidadesConferidas[chaveItem(item)] =
              quantidadeConferidaPersistida(item);
        }

        carregando = false;
      });
      focarLeitorWeb();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao carregar itens: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> carregarPreferenciaConferenciaManualItens() async {
    try {
      final resposta = await SessaoLoja.supabaseLoja!
          .from('loja_configuracoes')
          .select()
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
          .limit(1)
          .maybeSingle();

      final valor = resposta?['permitir_conferencia_manual_itens'];
      permitirConferenciaManualItens = valor == null ? true : valorBool(valor);
    } catch (_) {
      permitirConferenciaManualItens = true;
    }
  }

  bool conferenciaLegadaSemBip(Map<String, dynamic> item) {
    final conferidoEm = item['conferido_em']?.toString().trim() ?? '';
    final marcadoConferido =
        valorBool(item['conferido']) || valorBool(item['item_conferido']);
    final solicitado = quantidadeSolicitada(item);

    return !itemPesoVariavel(item) &&
        conferidoEm.isEmpty &&
        marcadoConferido &&
        solicitado > 0 &&
        quantidadeConferidaPersistida(item) >= solicitado;
  }

  Future<void> corrigirConferenciaLegadaPreparacao(
    List<Map<String, dynamic>> listaItens,
  ) async {
    if (normalizarStatus(widget.pedido['status']) != 'preparando') {
      return;
    }

    final itensParaResetar = listaItens.where(conferenciaLegadaSemBip).toList();

    if (itensParaResetar.isEmpty) {
      return;
    }

    final pedidoId = widget.pedido['id']?.toString();

    if (pedidoId == null || pedidoId.isEmpty) {
      return;
    }

    final dadosReset = {
      'quantidade_conferida': 0,
      'conferido': false,
      'item_conferido': false,
      'conferido_em': null,
    };

    for (final item in itensParaResetar) {
      final itemId = item['id']?.toString();

      if (itemId != null && itemId.isNotEmpty) {
        await SessaoLoja.supabaseLoja!
            .from('pedido_itens')
            .update(dadosReset)
            .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
            .eq('pedido_id', pedidoId)
            .eq('id', itemId);
      } else {
        await SessaoLoja.supabaseLoja!
            .from('pedido_itens')
            .update(dadosReset)
            .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
            .eq('pedido_id', pedidoId)
            .eq('ean', item['ean']);
      }

      item['quantidade_conferida'] = 0;
      item['conferido'] = false;
      item['item_conferido'] = false;
      item['conferido_em'] = null;
    }
  }

  String formatarMoeda(dynamic valor) {
    final numero = double.tryParse(valor.toString()) ?? 0;
    return 'R\$ ${numero.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String formatarQuantidade(dynamic valor) {
    final numero = double.tryParse(valor.toString().replaceAll(',', '.')) ?? 0;

    if (numero == numero.roundToDouble()) {
      return numero.toInt().toString();
    }

    var texto = numero.toStringAsFixed(3).replaceAll('.', ',');

    while (texto.endsWith('0')) {
      texto = texto.substring(0, texto.length - 1);
    }

    if (texto.endsWith(',')) {
      texto = texto.substring(0, texto.length - 1);
    }

    return texto;
  }

  double quantidadeSolicitada(Map<String, dynamic> item) {
    return double.tryParse(
          item['quantidade']?.toString().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }

  double quantidadeConferidaPersistida(Map<String, dynamic> item) {
    return double.tryParse(
          item['quantidade_conferida']?.toString().replaceAll(',', '.') ?? '',
        ) ??
        0;
  }

  double quantidadeConferida(Map<String, dynamic> item) {
    return quantidadesConferidas[chaveItem(item)] ?? 0;
  }

  String chaveItem(Map<String, dynamic> item) {
    final id = item['id']?.toString();

    if (id != null && id.isNotEmpty) {
      return id;
    }

    return '${item['ean'] ?? ''}_${item['nome_produto'] ?? ''}';
  }

  String normalizarEan(dynamic valor) {
    final somenteNumeros = (valor?.toString() ?? '').replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    final semZeros = somenteNumeros.replaceFirst(RegExp(r'^0+'), '');

    if (semZeros.isEmpty) {
      return somenteNumeros;
    }

    return semZeros;
  }

  String normalizarStatus(dynamic valor) {
    final status = (valor?.toString() ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('ç', 'c')
        .replaceAll('ã', 'a')
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll(' ', '_')
        .replaceAll('-', '_');

    if (status == 'preparacao' || status == 'em_preparacao') {
      return 'preparando';
    }

    if (status == 'pedido_aceito') {
      return 'aceito';
    }

    if (status == 'entrega' || status == 'em_entrega') {
      return 'saiu_para_entrega';
    }

    return status.isEmpty ? 'novo' : status;
  }

  void concluirAtualizacaoStatus(
    String novoStatus, {
    Map<String, dynamic>? dadosExtras,
  }) {
    if (!mounted) return;

    if (!widget.modoPagina) {
      Navigator.pop(context);
      return;
    }

    setState(() {
      widget.pedido['status'] = novoStatus;
      widget.pedido['atualizado_em'] = DateTime.now().toUtc().toIso8601String();
      if (dadosExtras != null) {
        widget.pedido.addAll(dadosExtras);
      }
    });
  }

  bool valorBool(dynamic valor) {
    if (valor is bool) return valor;

    if (valor is num) return valor == 1;

    if (valor is String) {
      final texto = valor.trim().toLowerCase();

      return texto == 'true' ||
          texto == '1' ||
          texto == 'sim' ||
          texto == 's' ||
          texto == 'yes';
    }

    return false;
  }

  double numero(dynamic valor) {
    if (valor == null) return 0;

    if (valor is num) return valor.toDouble();

    return double.tryParse(valor.toString().replaceAll(',', '.').trim()) ?? 0;
  }

  bool itemPesoVariavel(Map<String, dynamic> item) {
    return valorBool(item['peso_variavel']);
  }

  double pesoEstimadoKg(Map<String, dynamic> item) {
    return numero(item['peso_estimado_kg']);
  }

  double pesoRealKg(Map<String, dynamic> item) {
    return numero(item['peso_real_kg']);
  }

  double precoKg(Map<String, dynamic> item) {
    final precoKg = numero(item['preco_kg']);

    if (precoKg > 0) {
      return precoKg;
    }

    return numero(item['preco_unitario']);
  }

  double quantidadeUnidadePesoVariavel(Map<String, dynamic> item) {
    final quantidadeUnidade = numero(item['quantidade_unidade']);

    if (quantidadeUnidade > 0) {
      return quantidadeUnidade;
    }

    return quantidadeSolicitada(item);
  }

  double totalItemAtual(Map<String, dynamic> item) {
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

  String formatarPesoKg(dynamic valor) {
    final peso = numero(valor);

    if (peso <= 0) {
      return '-';
    }

    if (peso < 1) {
      final gramas = (peso * 1000).round();
      return '${gramas}g';
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

  bool itemConferido(Map<String, dynamic> item) {
    if (itemPesoVariavel(item)) {
      return pesoRealKg(item) > 0;
    }

    return quantidadeConferida(item) >= quantidadeSolicitada(item);
  }

  bool get todosItensConferidos {
    if (itens.isEmpty) {
      return false;
    }

    return itens.every(itemConferido);
  }

  bool get possuiPesoVariavelPendente {
    return itens.any((item) => itemPesoVariavel(item) && !itemConferido(item));
  }

  String get motivoBloqueioEntrega {
    if (possuiPesoVariavelPendente) {
      return 'Informe o peso real dos produtos de peso variável para liberar a entrega';
    }

    if (!todosItensConferidos) {
      return 'Confira todos os itens do pedido para liberar a entrega';
    }

    if (!numeroNfcePreenchido) {
      return 'Informe o número da NFC-e para liberar a entrega';
    }

    return '';
  }

  bool get numeroNfcePreenchido {
    return numeroNfceController.text.trim().isNotEmpty;
  }

  String numeroNfcePedido() {
    final texto =
        widget.pedido['numero_nfce']?.toString().trim() ??
        widget.pedido['nfce_numero']?.toString().trim() ??
        '';

    if (texto.isNotEmpty) {
      return texto;
    }

    return numeroNfceController.text.trim();
  }

  Future<void> salvarNumeroNfce() async {
    if (!SessaoLoja.lojaSelecionada || SessaoLoja.supabaseLoja == null) {
      throw Exception('Nenhuma loja selecionada');
    }

    final numeroNfce = numeroNfceController.text.trim();

    if (numeroNfce.isEmpty) {
      throw Exception('Informe o número da NFC-e antes de sair para entrega.');
    }

    setState(() {
      salvandoNfce = true;
      erroNumeroNfce = null;
    });

    try {
      await SessaoLoja.supabaseLoja!
          .from('pedidos')
          .update({
            'numero_nfce': numeroNfce,
            'nfce_registrada_em': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.pedido['id'])
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);

      widget.pedido['numero_nfce'] = numeroNfce;
      widget.pedido['nfce_registrada_em'] = DateTime.now().toIso8601String();
    } finally {
      if (mounted) {
        setState(() {
          salvandoNfce = false;
        });
      }
    }
  }

  Future<void> sairParaEntregaComNfce() async {
    FocusScope.of(context).unfocus();

    if (!todosItensConferidos) {
      setState(() {
        erroNumeroNfce = possuiPesoVariavelPendente
            ? 'Informe o peso real dos produtos de peso variável para liberar a entrega.'
            : 'Confira todos os itens do pedido para liberar a entrega.';
      });
      return;
    }

    if (!numeroNfcePreenchido) {
      setState(() {
        erroNumeroNfce =
            'Informe o número da NFC-e antes de sair para entrega.';
      });
      return;
    }

    try {
      await salvarNumeroNfce();

      final atualizado = await widget.onAtualizarStatus(
        widget.pedido['id'].toString(),
        'saiu_para_entrega',
      );

      if (mounted && atualizado) {
        concluirAtualizacaoStatus('saiu_para_entrega');
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        erroNumeroNfce = CentralService.mensagemErroUsuario(e);
      });
    }
  }

  Widget campoNumeroNfce() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NFC-e do pedido',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          const Text(
            'Digite o número da NFC-e gerada no caixa. A entrega só será liberada após preencher este campo.',
            style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.25),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: numeroNfceController,
            enabled: !salvandoNfce,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Número da NFC-e',
              hintText: 'Ex: 123456',
              prefixIcon: Icon(Icons.receipt_long),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              setState(() {
                erroNumeroNfce = null;
              });
            },
          ),
          if (erroNumeroNfce != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    erroNumeroNfce!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget botaoSairParaEntregaComNfce() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        icon: salvandoNfce
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.delivery_dining),
        label: Text(salvandoNfce ? 'Salvando NFC-e...' : 'Saiu para entrega'),
        style: ElevatedButton.styleFrom(
          backgroundColor: corStatusDetalhe('saiu_para_entrega'),
          foregroundColor: Colors.white,
        ),
        onPressed: salvandoNfce ? null : sairParaEntregaComNfce,
      ),
    );
  }

  int get totalItensConferidos {
    return itens.where(itemConferido).length;
  }

  Future<void> salvarConferenciaItem(
    Map<String, dynamic> item,
    double quantidadeInformada,
  ) async {
    if (!SessaoLoja.lojaSelecionada || SessaoLoja.supabaseLoja == null) {
      throw Exception('Nenhuma loja selecionada');
    }

    final completo = quantidadeInformada >= quantidadeSolicitada(item);

    final dados = {
      'quantidade_conferida': quantidadeInformada,
      'conferido': completo,
      'conferido_em': completo ? DateTime.now().toIso8601String() : null,
    };

    final itemId = item['id']?.toString();

    dynamic resposta;

    if (itemId != null && itemId.isNotEmpty) {
      resposta = await SessaoLoja.supabaseLoja!
          .from('pedido_itens')
          .update(dados)
          .eq('id', itemId)
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
          .select('id, quantidade_conferida, conferido, conferido_em');
    } else {
      resposta = await SessaoLoja.supabaseLoja!
          .from('pedido_itens')
          .update(dados)
          .eq('pedido_id', widget.pedido['id'])
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
          .eq('ean', item['ean'])
          .select('id, quantidade_conferida, conferido, conferido_em');
    }

    final listaAtualizada = List<Map<String, dynamic>>.from(resposta);

    if (listaAtualizada.isEmpty) {
      throw Exception(
        'Nenhum item foi atualizado. Verifique se existe política de UPDATE na tabela pedido_itens.',
      );
    }

    final itemAtualizado = listaAtualizada.first;

    item['quantidade_conferida'] = itemAtualizado['quantidade_conferida'];
    item['conferido'] = itemAtualizado['conferido'];
    item['conferido_em'] = itemAtualizado['conferido_em'];
  }

  Future<double?> salvarPesoRealItem(
    Map<String, dynamic> item,
    double pesoReal,
  ) async {
    if (!SessaoLoja.lojaSelecionada || SessaoLoja.supabaseLoja == null) {
      throw Exception('Nenhuma loja selecionada');
    }

    final itemId = item['id']?.toString();
    final pedidoId = widget.pedido['id']?.toString();

    if (pedidoId == null || pedidoId.isEmpty) {
      throw Exception('Pedido sem ID. Reabra o pedido e tente novamente.');
    }

    if (itemId == null || itemId.isEmpty) {
      throw Exception('Item sem ID. Reabra o pedido e tente novamente.');
    }

    final totalItem = double.parse(
      (precoKg(item) * pesoReal).toStringAsFixed(2),
    );

    final agora = DateTime.now().toIso8601String();

    final dadosItem = {
      'peso_real_kg': pesoReal,
      'total_final': totalItem,
      'total': totalItem,
      'item_conferido': true,
      'conferido': true,
      'quantidade_conferida': quantidadeSolicitada(item),
      'conferido_em': agora,
    };

    var respostaItem = await SessaoLoja.supabaseLoja!
        .from('pedido_itens')
        .update(dadosItem)
        .eq('id', itemId)
        .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
        .select(
          'id, pedido_id, peso_real_kg, total_final, total, '
          'item_conferido, conferido, quantidade_conferida, conferido_em',
        );

    var listaItemAtualizado = List<Map<String, dynamic>>.from(respostaItem);

    if (listaItemAtualizado.isEmpty) {
      respostaItem = await SessaoLoja.supabaseLoja!
          .from('pedido_itens')
          .update(dadosItem)
          .eq('pedido_id', pedidoId)
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
          .eq('ean', item['ean'])
          .select(
            'id, pedido_id, peso_real_kg, total_final, total, '
            'item_conferido, conferido, quantidade_conferida, conferido_em',
          );

      listaItemAtualizado = List<Map<String, dynamic>>.from(respostaItem);
    }

    if (listaItemAtualizado.isEmpty) {
      throw Exception(
        'O item não foi atualizado no banco. Verifique UPDATE em pedido_itens.',
      );
    }

    final itemAtualizado = listaItemAtualizado.first;

    item['peso_real_kg'] = itemAtualizado['peso_real_kg'];
    item['total_final'] = itemAtualizado['total_final'];
    item['total'] = itemAtualizado['total'];
    item['item_conferido'] = itemAtualizado['item_conferido'];
    item['conferido'] = itemAtualizado['conferido'];
    item['quantidade_conferida'] = itemAtualizado['quantidade_conferida'];
    item['conferido_em'] = itemAtualizado['conferido_em'];

    final respostaItensPedido = await SessaoLoja.supabaseLoja!
        .from('pedido_itens')
        .select('total_final, total_estimado, total')
        .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
        .eq('pedido_id', pedidoId);

    final itensPedido = List<Map<String, dynamic>>.from(respostaItensPedido);

    double subtotalItens = 0;

    for (final itemPedido in itensPedido) {
      final totalFinal = numero(itemPedido['total_final']);

      if (totalFinal > 0) {
        subtotalItens += totalFinal;
        continue;
      }

      final totalEstimado = numero(itemPedido['total_estimado']);

      if (totalEstimado > 0) {
        subtotalItens += totalEstimado;
        continue;
      }

      subtotalItens += numero(itemPedido['total']);
    }

    subtotalItens = double.parse(subtotalItens.toStringAsFixed(2));

    final taxaEntrega = numero(widget.pedido['taxa_entrega']);
    final desconto = numero(widget.pedido['desconto']);

    final totalPedido = double.parse(
      (subtotalItens + taxaEntrega - desconto).toStringAsFixed(2),
    );

    final respostaPedido = await SessaoLoja.supabaseLoja!
        .from('pedidos')
        .update({
          'subtotal': subtotalItens,
          'total': totalPedido,
          'total_recalculado': true,
          'atualizado_em': agora,
        })
        .eq('id', pedidoId)
        .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
        .select('id, subtotal, total, total_recalculado, atualizado_em');

    final listaPedidoAtualizado = List<Map<String, dynamic>>.from(
      respostaPedido,
    );

    if (listaPedidoAtualizado.isEmpty) {
      throw Exception(
        'O item foi atualizado, mas o total do pedido não foi atualizado.',
      );
    }

    final pedidoAtualizado = listaPedidoAtualizado.first;

    widget.pedido['subtotal'] = pedidoAtualizado['subtotal'];
    widget.pedido['total'] = pedidoAtualizado['total'];
    widget.pedido['total_recalculado'] = pedidoAtualizado['total_recalculado'];
    widget.pedido['atualizado_em'] = pedidoAtualizado['atualizado_em'];

    await carregarItens();

    return numero(pedidoAtualizado['total']);
  }

  Future<void> abrirDialogPesoReal(Map<String, dynamic> item) async {
    final pesoAtual = pesoRealKg(item);
    final pesoEstimado = pesoEstimadoKg(item);

    final controller = TextEditingController(
      text: pesoAtual > 0
          ? formatarQuantidade(pesoAtual)
          : pesoEstimado > 0
          ? formatarQuantidade(pesoEstimado)
          : '',
    );

    final pesoInformado = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Informar peso real'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['nome_produto']?.toString() ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text('EAN: ${item['ean'] ?? '-'}'),
              Text(
                'Quantidade: ${formatarQuantidade(quantidadeUnidadePesoVariavel(item))} un',
              ),
              Text('Peso estimado: ${formatarPesoKg(pesoEstimado)}'),
              Text('Preço por KG: ${formatarMoeda(precoKg(item))}'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Peso real em KG',
                  hintText: 'Ex: 2,350',
                  prefixIcon: Icon(Icons.scale_outlined),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) {
                  final valor = double.tryParse(
                    controller.text.trim().replaceAll(',', '.'),
                  );

                  FocusScope.of(context).unfocus();
                  Navigator.of(context).pop(valor);
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Esse peso será usado para recalcular o valor final do item e o total do pedido do cliente.',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(context).unfocus();
                Navigator.of(context).pop();
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final valor = double.tryParse(
                  controller.text.trim().replaceAll(',', '.'),
                );

                FocusScope.of(context).unfocus();
                Navigator.of(context).pop(valor);
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar peso'),
            ),
          ],
        );
      },
    );

    if (pesoInformado == null) {
      return;
    }

    if (pesoInformado <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe um peso real maior que zero'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final totalPedido = await salvarPesoRealItem(item, pesoInformado);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            totalPedido == null
                ? 'Peso real salvo e item recalculado'
                : 'Peso real salvo. Novo total: ${formatarMoeda(totalPedido)}',
          ),
          backgroundColor: Colors.green,
        ),
      );

      if (todosItensConferidos) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Todos os itens foram conferidos'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao salvar peso real: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 150));
        codigoBarrasFocus.requestFocus();
      }
    }
  }

  Future<void> biparProduto(String codigo) async {
    final codigoNormalizado = normalizarEan(codigo);

    if (codigoNormalizado.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe ou bipe o código de barras')),
      );
      return;
    }

    final itensEncontrados = itens.where((item) {
      final eanItem = normalizarEan(item['ean']);
      return eanItem == codigoNormalizado;
    }).toList();

    codigoBarrasController.clear();
    codigoBarrasFocus.requestFocus();

    if (itensEncontrados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Produto não pertence a este pedido'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final itemParaConferir = itensEncontrados.firstWhere(
      (item) => !itemConferido(item),
      orElse: () => itensEncontrados.first,
    );

    await abrirDialogQuantidade(itemParaConferir);
  }

  Future<void> abrirDialogQuantidade(Map<String, dynamic> item) async {
    if (itemPesoVariavel(item)) {
      await abrirDialogPesoReal(item);
      return;
    }

    final quantidadePedido = quantidadeSolicitada(item);
    final quantidadeAtual = quantidadeConferida(item);

    final controller = TextEditingController(
      text: quantidadeAtual > 0
          ? formatarQuantidade(quantidadeAtual)
          : formatarQuantidade(quantidadePedido),
    );

    final quantidadeInformada = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Conferir item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['nome_produto']?.toString() ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text('EAN: ${item['ean'] ?? '-'}'),
              Text(
                'Quantidade do pedido: ${formatarQuantidade(quantidadePedido)}',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Quantidade separada',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) {
                  final valor = double.tryParse(
                    controller.text.trim().replaceAll(',', '.'),
                  );

                  FocusScope.of(context).unfocus();
                  Navigator.of(context).pop(valor);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(context).unfocus();
                Navigator.of(context).pop();
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final valor = double.tryParse(
                  controller.text.trim().replaceAll(',', '.'),
                );

                FocusScope.of(context).unfocus();
                Navigator.of(context).pop(valor);
              },
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    if (quantidadeInformada == null) {
      return;
    }

    if (quantidadeInformada <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe uma quantidade maior que zero'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (quantidadeInformada > quantidadePedido) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quantidade maior que a quantidade do pedido'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await salvarConferenciaItem(item, quantidadeInformada);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao salvar conferência: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      quantidadesConferidas[chaveItem(item)] = quantidadeInformada;
    });

    if (todosItensConferidos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Todos os itens foram conferidos'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (itemConferido(item)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item conferido'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quantidade parcial registrada'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    await Future.delayed(const Duration(milliseconds: 150));

    if (mounted) {
      codigoBarrasFocus.requestFocus();
    }
  }

  Future<void> abrirScannerCamera() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          onDetect: (codigo) {
            codigoBarrasController.text = codigo;
            biparProduto(codigo);
          },
        ),
      ),
    );
    focarLeitorWeb();
  }

  Widget campoBipagem() {
    final pendentes = itens.length - totalItensConferidos;
    final cor = todosItensConferidos
        ? Colors.green
        : corStatusDetalhe('preparando');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cor.withOpacity(0.26), width: 1.3),
        boxShadow: [
          BoxShadow(
            color: cor.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.qr_code_scanner, color: cor, size: 24),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: cor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$totalItensConferidos/${itens.length}',
                  style: TextStyle(
                    color: cor,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Conferência dos itens',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            todosItensConferidos
                ? 'Todos os itens foram conferidos. O envio para entrega está liberado.'
                : 'Bipe cada produto. Para peso variável, informe o peso real. Pendentes: $pendentes',
            style: TextStyle(
              color: todosItensConferidos ? Colors.green : Colors.black54,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: codigoBarrasController,
            focusNode: codigoBarrasFocus,
            autofocus: kIsWeb,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Bipar ou digitar EAN',
              hintText: 'Leia o código de barras do produto',
              prefixIcon: Icon(Icons.qr_code_scanner, color: cor),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!kIsWeb)
                    IconButton(
                      tooltip: 'Abrir câmera',
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: abrirScannerCamera,
                    ),
                  IconButton(
                    tooltip: 'Confirmar código',
                    icon: const Icon(Icons.check),
                    onPressed: () => biparProduto(codigoBarrasController.text),
                  ),
                ],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.black.withOpacity(0.10)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: cor, width: 1.5),
              ),
            ),
            onSubmitted: biparProduto,
            onTapOutside: (_) => focarLeitorWeb(),
          ),
          if (kIsWeb) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: abrirScannerCamera,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Usar câmera'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Digite o EAN ou use um leitor USB/Bluetooth. A leitura será confirmada automaticamente quando o leitor enviar Enter.',
              style: TextStyle(
                color: Color(0xFF667085),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget chipConferencia(String texto, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withOpacity(0.18)),
      ),
      child: Text(
        texto,
        style: TextStyle(color: cor, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget itemConferenciaTile(Map<String, dynamic> item) {
    if (itemPesoVariavel(item)) {
      return itemPesoVariavelConferenciaTile(item);
    }

    final solicitado = quantidadeSolicitada(item);
    final conferido = quantidadeConferida(item);
    final completo = itemConferido(item);
    final parcial = conferido > 0 && !completo;

    Color corStatus = Colors.orange;
    IconData iconeStatus = Icons.pending;
    String textoStatus = 'Pendente';

    if (completo) {
      corStatus = Colors.green;
      iconeStatus = Icons.check_circle;
      textoStatus = 'Conferido';
    } else if (parcial) {
      corStatus = Colors.orange;
      iconeStatus = Icons.warning_amber_rounded;
      textoStatus = 'Parcial';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: permitirConferenciaManualItens
            ? () => abrirDialogQuantidade(item)
            : null,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: completo
                ? Colors.green.withOpacity(0.05)
                : parcial
                ? Colors.orange.withOpacity(0.06)
                : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: corStatus.withOpacity(0.24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.045),
                blurRadius: 9,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: corStatus.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(iconeStatus, color: corStatus, size: 23),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['nome_produto']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'EAN: ${item['ean'] ?? '-'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        chipConferencia(
                          'Pedido: ${formatarQuantidade(solicitado)}',
                          Colors.blueGrey,
                        ),
                        chipConferencia(
                          'Conferido: ${formatarQuantidade(conferido)}',
                          corStatus,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(iconeStatus, color: corStatus, size: 24),
                  const SizedBox(height: 2),
                  Text(
                    textoStatus,
                    style: TextStyle(
                      color: corStatus,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget itemPesoVariavelConferenciaTile(Map<String, dynamic> item) {
    final completo = itemConferido(item);
    final pesoEstimado = pesoEstimadoKg(item);
    final pesoReal = pesoRealKg(item);
    final valorEstimado = numero(item['total_estimado']);
    final valorAtual = totalItemAtual(item);
    final unidades = quantidadeUnidadePesoVariavel(item);
    final corStatus = completo ? Colors.green : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: completo
          ? Colors.green.withOpacity(0.04)
          : Colors.orange.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: corStatus.withOpacity(0.22)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: permitirConferenciaManualItens
            ? () => abrirDialogPesoReal(item)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: corStatus.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  completo ? Icons.check_circle : Icons.scale_outlined,
                  color: corStatus,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['nome_produto']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'EAN: ${item['ean'] ?? '-'}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${formatarQuantidade(unidades)} un • '
                      'estimado ${formatarPesoKg(pesoEstimado)} • '
                      'R\$/kg ${formatarMoeda(precoKg(item))}',
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.20,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      completo
                          ? 'Peso real: ${formatarPesoKg(pesoReal)} • Total final: ${formatarMoeda(valorAtual)}'
                          : 'Informe o peso real para recalcular o pedido',
                      style: TextStyle(
                        color: corStatus,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        height: 1.20,
                      ),
                    ),
                    if (!completo && valorEstimado > 0) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Valor estimado: ${formatarMoeda(valorEstimado)}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Icon(
                    completo ? Icons.edit_outlined : Icons.add_circle_outline,
                    color: corStatus,
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    completo ? 'Editar' : 'Pesar',
                    style: TextStyle(
                      color: corStatus,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget botaoStatusDesabilitado({
    required String texto,
    required IconData icone,
    required String motivo,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            icon: Icon(icone),
            label: Text(texto),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade400,
              foregroundColor: Colors.white,
            ),
            onPressed: null,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          motivo,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.red,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String textoPedido(dynamic valor) {
    return valor?.toString().trim() ?? '';
  }

  double? coordenadaPedido(dynamic valor) {
    final texto = valor?.toString().replaceAll(',', '.').trim() ?? '';

    if (texto.isEmpty) {
      return null;
    }

    final numero = double.tryParse(texto);

    if (numero == null || numero == 0) {
      return null;
    }

    return numero;
  }

  String enderecoEntregaPedido() {
    final pedido = widget.pedido;

    final formatado = textoPedido(pedido['endereco_entrega_formatado']);

    if (formatado.isNotEmpty) {
      return formatado;
    }

    final endereco = textoPedido(pedido['endereco']);
    final numero = textoPedido(pedido['numero']);
    final bairro = textoPedido(pedido['bairro']);
    final cidade = textoPedido(pedido['cidade']);
    final referencia = textoPedido(pedido['referencia']);

    final linha1 = [
      endereco,
      numero,
    ].where((item) => item.isNotEmpty).join(', ');

    final linha2 = [
      bairro,
      cidade,
    ].where((item) => item.isNotEmpty).join(' - ');

    final partes = [
      linha1,
      linha2,
      referencia,
    ].where((item) => item.isNotEmpty).toList();

    return partes.join(' | ');
  }

  String tipoEntregaPedido() {
    final tipo = textoPedido(widget.pedido['local_entrega']);

    if (tipo.isNotEmpty) {
      return tipo;
    }

    return 'Endereço de entrega';
  }

  String? urlGoogleMapsPorCoordenadas(double? lat, double? lng) {
    if (lat == null || lng == null) {
      return null;
    }

    return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
  }

  String? urlGoogleMapsPorEndereco(String endereco) {
    final texto = endereco
        .replaceAll('|', ',')
        .replaceAll('\n', ',')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (texto.isEmpty) {
      return null;
    }

    return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(texto)}';
  }

  String? linkMapaPedido() {
    final pedido = widget.pedido;

    final mapaUrl = textoPedido(pedido['mapa_url']);

    if (mapaUrl.isNotEmpty) {
      return mapaUrl;
    }

    final entregaLatitude = coordenadaPedido(pedido['entrega_latitude']);
    final entregaLongitude = coordenadaPedido(pedido['entrega_longitude']);

    final linkEntrega = urlGoogleMapsPorCoordenadas(
      entregaLatitude,
      entregaLongitude,
    );

    if (linkEntrega != null) {
      return linkEntrega;
    }

    final latitude = coordenadaPedido(pedido['latitude']);
    final longitude = coordenadaPedido(pedido['longitude']);

    final linkAntigo = urlGoogleMapsPorCoordenadas(latitude, longitude);

    if (linkAntigo != null) {
      return linkAntigo;
    }

    return urlGoogleMapsPorEndereco(enderecoEntregaPedido());
  }

  Future<void> compartilharLocalizacao() async {
    final pedido = widget.pedido;
    final endereco = enderecoEntregaPedido();
    final tipoEntrega = tipoEntregaPedido();
    final linkLocalizacao = linkMapaPedido();

    if ((linkLocalizacao == null || linkLocalizacao.isEmpty) &&
        endereco.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido sem endereço ou localização de entrega'),
        ),
      );
      return;
    }

    await Share.share('''
Pedido #${pedido['numero_pedido'] ?? '-'}

Cliente: ${pedido['cliente_nome'] ?? ''}
Telefone: ${pedido['cliente_telefone'] ?? ''}

Tipo de entrega:
$tipoEntrega

Endereço:
${endereco.isNotEmpty ? endereco : 'Não informado'}

Mapa:
${linkLocalizacao ?? 'Não informado'}
''');
  }

  Future<void> abrirWhatsAppCliente() async {
    final abriu = await abrirWhatsAppEntrega(widget.pedido);

    if (!mounted || abriu) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'N\u00e3o foi poss\u00edvel abrir o WhatsApp do cliente.',
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> resetarConferenciaItensPedido() async {
    if (!SessaoLoja.lojaSelecionada || SessaoLoja.supabaseLoja == null) {
      throw Exception('Nenhuma loja selecionada');
    }

    final pedidoId = widget.pedido['id']?.toString();

    if (pedidoId == null || pedidoId.isEmpty) {
      throw Exception('Pedido sem ID. Reabra o pedido e tente novamente.');
    }

    await SessaoLoja.supabaseLoja!
        .from('pedido_itens')
        .update({
          'quantidade_conferida': 0,
          'conferido': false,
          'item_conferido': false,
          'conferido_em': null,
        })
        .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
        .eq('pedido_id', pedidoId);

    for (final item in itens) {
      item['quantidade_conferida'] = 0;
      item['conferido'] = false;
      item['item_conferido'] = false;
      item['conferido_em'] = null;
      quantidadesConferidas[chaveItem(item)] = 0;
    }
  }

  String nomeResponsavelPedido() {
    for (final valor in [
      SessaoLoja.usuarioNome,
      SessaoLoja.usuarioLogin,
      SessaoLoja.usuarioEmail,
    ]) {
      final nome = valor?.trim() ?? '';

      if (nome.isNotEmpty) {
        return nome;
      }
    }

    return 'Funcionário da loja';
  }

  Future<void> aceitarPedido() async {
    if (aceitandoPedido) {
      return;
    }

    setState(() {
      aceitandoPedido = true;
    });

    try {
      final agora = DateTime.now().toUtc().toIso8601String();
      final dadosAceite = <String, dynamic>{
        'responsavel_user_id': SessaoLoja.usuarioId,
        'responsavel_nome': nomeResponsavelPedido(),
        'pedido_aceito_em': agora,
      };
      final atualizado = await widget.onAtualizarStatus(
        widget.pedido['id'].toString(),
        'aceito',
        dadosExtras: dadosAceite,
      );

      if (!mounted || !atualizado) return;

      concluirAtualizacaoStatus('aceito', dadosExtras: dadosAceite);
    } finally {
      if (mounted) {
        setState(() {
          aceitandoPedido = false;
        });
      }
    }
  }

  Future<void> recusarPedido() async {
    if (recusandoPedido) {
      return;
    }

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Recusar pedido?'),
          content: const Text(
            'O cliente será avisado do cancelamento e, quando aplicável, '
            'os itens serão devolvidos ao estoque.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Recusar pedido'),
            ),
          ],
        );
      },
    );

    if (confirmou != true || !mounted) {
      return;
    }

    setState(() {
      recusandoPedido = true;
    });

    try {
      final recusado = await widget.onRecusarPedido(
        widget.pedido['id'].toString(),
      );

      if (!mounted || !recusado) return;

      concluirAtualizacaoStatus('cancelado');
    } finally {
      if (mounted) {
        setState(() {
          recusandoPedido = false;
        });
      }
    }
  }

  Widget botoesAceitarOuRecusarPedido() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: aceitandoPedido || recusandoPedido
                  ? null
                  : recusarPedido,
              icon: recusandoPedido
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.red,
                      ),
                    )
                  : const Icon(Icons.cancel_outlined),
              label: Text(recusandoPedido ? 'Recusando...' : 'Recusar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: botaoStatus(
            texto: 'Aceitar pedido',
            icone: Icons.verified_outlined,
            cor: Colors.green,
            novoStatus: 'aceito',
          ),
        ),
      ],
    );
  }

  Future<void> colocarPedidoEmPreparacao() async {
    if (colocandoEmPreparacao) {
      return;
    }

    setState(() {
      colocandoEmPreparacao = true;
    });

    try {
      await resetarConferenciaItensPedido();
      final atualizado = await widget.onAtualizarStatus(
        widget.pedido['id'].toString(),
        'preparando',
      );

      if (!mounted || !atualizado) return;

      concluirAtualizacaoStatus('preparando');
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao colocar pedido em preparaÃ§Ã£o: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          colocandoEmPreparacao = false;
        });
      }
    }
  }

  Widget botaoStatus({
    required String texto,
    required IconData icone,
    required Color cor,
    required String novoStatus,
  }) {
    final processandoAceite = aceitandoPedido && novoStatus == 'aceito';
    final processandoPreparacao =
        colocandoEmPreparacao && novoStatus == 'preparando';
    final processando = processandoAceite || processandoPreparacao;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        icon: processando
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icone),
        label: Text(
          processandoAceite
              ? 'Aceitando...'
              : processandoPreparacao
              ? 'Preparando...'
              : texto,
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: cor,
          foregroundColor: Colors.white,
        ),
        onPressed: aceitandoPedido || recusandoPedido || colocandoEmPreparacao
            ? null
            : () async {
                if (novoStatus == 'aceito') {
                  await aceitarPedido();
                  return;
                }

                if (novoStatus == 'preparando') {
                  await colocarPedidoEmPreparacao();
                  return;
                }

                final atualizado = await widget.onAtualizarStatus(
                  widget.pedido['id'].toString(),
                  novoStatus,
                );

                if (!mounted || !atualizado) return;

                concluirAtualizacaoStatus(novoStatus);
              },
      ),
    );
  }

  String codigoEntregaPedido() {
    final codigo = widget.pedido['codigo_entrega']?.toString().trim() ?? '';
    final numeros = codigo.replaceAll(RegExp(r'[^0-9]'), '');

    if (numeros.length == 4) {
      return numeros;
    }

    // Compatibilidade para pedidos antigos criados antes do código aleatório.
    final telefone = widget.pedido['cliente_telefone']?.toString() ?? '';
    final telefoneNumeros = telefone.replaceAll(RegExp(r'[^0-9]'), '');

    if (telefoneNumeros.length >= 4) {
      return telefoneNumeros.substring(telefoneNumeros.length - 4);
    }

    return '';
  }

  bool codigoEntregaValido() {
    final codigoCorreto = codigoEntregaPedido();
    final codigoInformado = codigoEntregaController.text.trim();

    return codigoCorreto.length == 4 && codigoInformado == codigoCorreto;
  }

  Future<void> validarCodigoEEntregar() async {
    FocusScope.of(context).unfocus();

    final codigoCorreto = codigoEntregaPedido();
    final codigoInformado = codigoEntregaController.text.trim();

    if (codigoCorreto.length < 4) {
      setState(() {
        erroCodigoEntrega = 'Pedido sem código de entrega válido.';
      });
      return;
    }

    if (codigoInformado.length < 4) {
      setState(() {
        erroCodigoEntrega = 'Informe o código de entrega com 4 dígitos.';
      });
      return;
    }

    if (codigoInformado != codigoCorreto) {
      setState(() {
        erroCodigoEntrega = 'Código inválido. Entrega não confirmada.';
        codigoEntregaController.clear();
      });

      codigoEntregaFocus.requestFocus();
      return;
    }

    setState(() {
      erroCodigoEntrega = null;
    });

    final atualizado = await widget.onAtualizarStatus(
      widget.pedido['id'].toString(),
      'entregue',
    );

    if (mounted && atualizado) {
      concluirAtualizacaoStatus('entregue');
    }
  }

  Widget campoCodigoEntrega() {
    final codigoCorreto = codigoEntregaPedido();

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Código de validação da entrega',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            codigoCorreto.length == 4
                ? 'Digite o código de 4 dígitos informado pelo cliente.'
                : 'Este pedido ainda não possui código aleatório. Para pedidos antigos, o sistema usa compatibilidade pelos últimos dígitos do telefone.',
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: codigoEntregaController,
            focusNode: codigoEntregaFocus,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            textInputAction: TextInputAction.done,
            scrollPadding: const EdgeInsets.only(bottom: 260),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: const InputDecoration(
              labelText: 'Código de entrega',
              hintText: '0000',
              helperText: 'Peça ao cliente o código exibido no app',
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(),
              counterText: '',
            ),
            onChanged: (_) {
              setState(() {
                erroCodigoEntrega = null;
              });
            },
            onSubmitted: (_) => validarCodigoEEntregar(),
          ),

          if (erroCodigoEntrega != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    erroCodigoEntrega!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget botaoMarcarComoEntregueComValidacao() {
    return SizedBox(
      key: botaoConfirmarEntregaKey,
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.verified),
        label: const Text('Validar código e marcar como entregue'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        ),
        onPressed: validarCodigoEEntregar,
      ),
    );
  }

  Color corStatusDetalhe(String status) {
    switch (status) {
      case 'novo':
        return Colors.red;
      case 'aceito':
        return Colors.green;
      case 'preparando':
        return Colors.blue;
      case 'saiu_para_entrega':
        return Colors.purple;
      case 'entregue':
        return Colors.green;
      case 'cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData iconeStatusDetalhe(String status) {
    switch (status) {
      case 'novo':
        return Icons.shopping_cart_outlined;
      case 'aceito':
        return Icons.verified_outlined;
      case 'preparando':
        return Icons.inventory_2_outlined;
      case 'saiu_para_entrega':
        return Icons.delivery_dining;
      case 'entregue':
        return Icons.check_circle_outline;
      case 'cancelado':
        return Icons.cancel_outlined;
      default:
        return Icons.receipt_long;
    }
  }

  String tituloStatusDetalhe(String status) {
    switch (status) {
      case 'novo':
        return 'AGUARDANDO ACEITE';
      case 'aceito':
        return 'PEDIDO ACEITO';
      case 'preparando':
        return 'PREPARAÇÃO';
      case 'saiu_para_entrega':
        return 'ENTREGA';
      case 'entregue':
        return 'ENTREGUE';
      case 'cancelado':
        return 'CANCELADO';
      default:
        return status.toUpperCase();
    }
  }

  Widget cardDetalhe({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
  }) {
    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.only(bottom: 10),
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget linhaInfoDetalhe({
    required IconData icone,
    required Color cor,
    required String titulo,
    required String valor,
    VoidCallback? onTap,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: cor.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icone, color: cor, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                valor,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 13,
                  height: 1.20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                titulo.toLowerCase().contains('telefone')
                    ? Icons.phone
                    : Icons.navigation,
                size: 20,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget topoPedidoDetalhe({
    required Map<String, dynamic> pedido,
    required String status,
  }) {
    final cor = corStatusDetalhe(status);

    return cardDetalhe(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: cor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(iconeStatusDetalhe(status), color: cor, size: 31),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pedido #${pedido['numero_pedido'] ?? '-'}',
                  style: TextStyle(
                    color: cor,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  pedido['cliente_nome']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: cor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              tituloStatusDetalhe(status),
              style: TextStyle(
                color: cor,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget cardClienteEndereco({
    required Map<String, dynamic> pedido,
    required String status,
  }) {
    final cor = corStatusDetalhe(status);

    final endereco = enderecoEntregaPedido();

    return cardDetalhe(
      child: Column(
        children: [
          linhaInfoDetalhe(
            icone: Icons.phone,
            cor: cor,
            titulo: 'Telefone',
            valor: pedido['cliente_telefone']?.toString() ?? '-',
            onTap: abrirWhatsAppCliente,
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 10),
          linhaInfoDetalhe(
            icone: Icons.location_on_outlined,
            cor: cor,
            titulo: 'Endereço de entrega',
            valor: endereco,
            onTap: () => widget.onAbrirMapa(linkMapaPedido()),
          ),
          if ((pedido['referencia'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.grey.shade200),
            const SizedBox(height: 10),
            linhaInfoDetalhe(
              icone: Icons.info_outline,
              cor: cor,
              titulo: 'Referência',
              valor: pedido['referencia'].toString(),
            ),
          ],
        ],
      ),
    );
  }

  Widget botaoCompartilharLocalizacaoModerno(String status) {
    final cor = corStatusDetalhe(status);

    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        icon: Icon(Icons.share_location, color: cor, size: 20),
        label: Text(
          'Compartilhar localização',
          style: TextStyle(color: cor, fontWeight: FontWeight.w800),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: cor.withOpacity(0.35)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: compartilharLocalizacao,
      ),
    );
  }

  Widget itemResumoTile(Map<String, dynamic> item) {
    final pesoVariavel = itemPesoVariavel(item);
    final valorAtual = totalItemAtual(item);
    final pesoReal = pesoRealKg(item);
    final textoPeso = pesoReal > 0
        ? formatarPesoKg(pesoReal)
        : 'estimado ${formatarPesoKg(pesoEstimadoKg(item))}';

    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
      title: Text(
        item['nome_produto'] ?? '',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        pesoVariavel
            ? 'EAN: ${item['ean'] ?? '-'}\n'
                  '${formatarQuantidade(quantidadeUnidadePesoVariavel(item))} un • '
                  'peso $textoPeso • '
                  '${formatarMoeda(precoKg(item))}/kg'
            : 'EAN: ${item['ean'] ?? '-'}\n'
                  '${item['quantidade']} x ${formatarMoeda(item['preco_unitario'])}',
        style: const TextStyle(fontSize: 12, height: 1.20),
      ),
      trailing: Text(
        formatarMoeda(valorAtual),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      isThreeLine: true,
    );
  }

  Widget listaItensModerna(String status) {
    final cor = corStatusDetalhe(status);

    return cardDetalhe(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Itens do pedido',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                ),
                if (status == 'preparando')
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: cor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$totalItensConferidos/${itens.length} separados',
                      style: TextStyle(
                        color: cor,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${itens.length} itens',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          if (itens.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Nenhum item encontrado'),
            )
          else if (status == 'preparando')
            ...itensSeparacaoAgrupadosPorCategoria()
          else
            ...itens.map(itemResumoTile),
        ],
      ),
    );
  }

  List<Widget> itensSeparacaoAgrupadosPorCategoria() {
    final widgets = <Widget>[];
    String? categoriaAnterior;

    for (final item in itens) {
      final categoria = categoriaItemPedido(item);

      if (categoria != categoriaAnterior) {
        widgets.add(
          Container(
            width: double.infinity,
            margin: EdgeInsets.only(top: widgets.isEmpty ? 0 : 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                Icon(
                  Icons.category_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    categoria.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        categoriaAnterior = categoria;
      }

      widgets.add(itemConferenciaTile(item));
    }

    return widgets;
  }

  Widget entregaConcluidaCard() {
    return cardDetalhe(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.green, size: 32),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Entrega concluída',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Pedido entregue com sucesso',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
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
    final statusOriginal = pedido['status']?.toString() ?? 'novo';
    final status = normalizarStatus(statusOriginal);

    if (widget.modoPagina) {
      return _conteudoDetalhes(
        pedido: pedido,
        status: status,
        controller: null,
        mostrarAlca: false,
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      maxChildSize: 0.96,
      minChildSize: 0.55,
      builder: (_, controller) {
        return _conteudoDetalhes(
          pedido: pedido,
          status: status,
          controller: controller,
          mostrarAlca: true,
        );
      },
    );
  }

  Widget _conteudoDetalhes({
    required Map<String, dynamic> pedido,
    required String status,
    required ScrollController? controller,
    required bool mostrarAlca,
  }) {
    return Container(
      color: const Color(0xFFF7F4FA),
      child: Column(
        children: [
          if (mostrarAlca)
            Container(
              height: 4,
              width: 48,
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          Expanded(
            child: ListView(
              controller: controller,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                12,
                mostrarAlca ? 8 : 18,
                12,
                MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              children: [
                topoPedidoDetalhe(pedido: pedido, status: status),
                cardClienteEndereco(pedido: pedido, status: status),
                botaoCompartilharLocalizacaoModerno(status),
                const SizedBox(height: 12),
                if (status == 'saiu_para_entrega') ...[
                  campoCodigoEntrega(),
                  botaoMarcarComoEntregueComValidacao(),
                  const SizedBox(height: 8),
                ],
                if (status == 'preparando') campoNumeroNfce(),
                if (status == 'preparando' && !carregando && itens.isNotEmpty)
                  campoBipagem(),
                if (carregando)
                  const Padding(
                    padding: EdgeInsets.only(top: 18),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (status != 'saiu_para_entrega' && status != 'entregue')
                  listaItensModerna(status),
                if (status == 'entregue') entregaConcluidaCard(),
                const SizedBox(height: 8),
                if (status == 'novo') botoesAceitarOuRecusarPedido(),
                if (status == 'aceito')
                  botaoStatus(
                    texto: 'Colocar em preparação',
                    icone: Icons.restaurant_menu,
                    cor: Colors.blue,
                    novoStatus: 'preparando',
                  ),
                if (status == 'preparando' &&
                    todosItensConferidos &&
                    numeroNfcePreenchido)
                  botaoSairParaEntregaComNfce(),
                if (status == 'preparando' &&
                    (!todosItensConferidos || !numeroNfcePreenchido))
                  botaoStatusDesabilitado(
                    texto: 'Saiu para entrega',
                    icone: Icons.delivery_dining,
                    motivo: motivoBloqueioEntrega,
                  ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../services/central_service.dart';

import '../../services/monitor_pedidos_service.dart';
import '../../services/sessao_loja.dart';
import 'pedidos_status_page.dart';

class PedidosMercadoPage extends StatefulWidget {
  const PedidosMercadoPage({super.key});

  @override
  State<PedidosMercadoPage> createState() => _PedidosMercadoPageState();
}

class _PedidosMercadoPageState extends State<PedidosMercadoPage> {
  static Color get vermelho => SessaoLoja.corPrimaria;
  static Color get fundoInicio => SessaoLoja.corFundo;

  bool carregando = true;
  bool alertaNovosPedidos = false;

  int novos = 0;
  int aceitos = 0;
  int preparando = 0;
  int entrega = 0;
  int entregues = 0;

  @override
  void initState() {
    super.initState();
    iniciarMonitorPedidos();
    carregarResumo();
  }

  Future<void> iniciarMonitorPedidos() async {
    try {
      await MonitorPedidosService.instance.iniciar(
        onNovoPedido: () async {
          if (!mounted) return;

          setState(() {
            alertaNovosPedidos = true;
          });

          await carregarResumo();

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Novo pedido recebido'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        },
      );
    } catch (_) {
      // Não trava a tela caso o monitor não consiga iniciar.
    }
  }

  Future<void> carregarResumo() async {
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
      final resposta = await SessaoLoja.supabaseLoja!
          .from('pedidos')
          .select('status')
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);

      final lista = List<Map<String, dynamic>>.from(resposta);

      final qtdNovos = lista.where((p) => p['status'] == 'novo').length;
      final qtdAceitos = lista.where((p) => p['status'] == 'aceito').length;
      final qtdPreparando = lista
          .where((p) => p['status'] == 'preparando')
          .length;
      final qtdEntrega = lista
          .where((p) => p['status'] == 'saiu_para_entrega')
          .length;
      final qtdEntregues = lista.where((p) => p['status'] == 'entregue').length;

      if (!mounted) return;

      setState(() {
        novos = SessaoLoja.usuarioEntregador ? 0 : qtdNovos;
        aceitos = SessaoLoja.usuarioEntregador ? 0 : qtdAceitos;
        preparando = SessaoLoja.usuarioEntregador ? 0 : qtdPreparando;
        entrega = qtdEntrega;
        entregues = SessaoLoja.usuarioEntregador ? 0 : qtdEntregues;

        if (SessaoLoja.usuarioEntregador || novos <= 0) {
          alertaNovosPedidos = false;
        }

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
            'Erro ao carregar resumo: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> abrirStatus({
    required BuildContext context,
    required String status,
    required String titulo,
    required Color cor,
  }) async {
    final statusEfetivo = SessaoLoja.usuarioEntregador
        ? 'saiu_para_entrega'
        : status;
    final tituloEfetivo = SessaoLoja.usuarioEntregador ? 'Entrega' : titulo;
    final corEfetiva = SessaoLoja.usuarioEntregador ? Colors.purple : cor;

    if (statusEfetivo == 'novo') {
      setState(() {
        alertaNovosPedidos = false;
      });
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PedidosStatusPage(
          status: statusEfetivo,
          titulo: tituloEfetivo,
          cor: corEfetiva,
        ),
      ),
    );

    carregarResumo();
  }

  Future<void> abrirTodos(BuildContext context) async {
    if (SessaoLoja.usuarioEntregador) {
      await abrirStatus(
        context: context,
        status: 'saiu_para_entrega',
        titulo: 'Entrega',
        cor: Colors.purple,
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const PedidosStatusPage(
          status: 'todos',
          titulo: 'Todos os Pedidos',
          cor: Colors.black,
        ),
      ),
    );

    carregarResumo();
  }

  Widget topoResumo({required int total}) {
    final nomeLoja = SessaoLoja.mercadoNome ?? 'Mercado São Mateus';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [SessaoLoja.corPrimaria, SessaoLoja.corSecundaria],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: SessaoLoja.corPrimaria.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.receipt_long, color: vermelho, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pedidos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nomeLoja,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                total.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  height: 0.95,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Total de pedidos',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget cardStatus({
    required BuildContext context,
    required String titulo,
    required String subtitulo,
    required int quantidade,
    required Color cor,
    required IconData icone,
    required String status,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        abrirStatus(context: context, status: status, titulo: titulo, cor: cor);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: cor.withOpacity(0.20),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 84,
              decoration: BoxDecoration(
                color: cor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: cor.withOpacity(0.45),
                    blurRadius: 16,
                    offset: const Offset(2, 0),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: cor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icone, color: cor, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            titulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cor,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            subtitulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                              height: 1.15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          quantidade.toString(),
                          style: TextStyle(
                            color: cor,
                            fontSize: 32,
                            height: 0.95,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          quantidade == 1 ? 'pedido' : 'pedidos',
                          style: TextStyle(
                            color: cor,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.grey.shade500,
                      size: 26,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget cardTodos({required BuildContext context, required int total}) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => abrirTodos(context),
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [SessaoLoja.corPrimaria, SessaoLoja.corSecundaria],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: SessaoLoja.corSecundaria.withValues(alpha: 0.30),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.list_alt, color: Colors.white, size: 27),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ver todos os pedidos',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total geral: $total ${total == 1 ? 'pedido' : 'pedidos'}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white70, size: 30),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entregador = SessaoLoja.usuarioEntregador;
    final total = entregador
        ? entrega
        : novos + aceitos + preparando + entrega + entregues;

    final corNovos = alertaNovosPedidos || novos > 0
        ? Colors.red
        : Colors.orange;

    return Scaffold(
      backgroundColor: fundoInicio,
      appBar: AppBar(
        title: Text(
          SessaoLoja.mercadoNome == null
              ? 'Pedidos do Mercado'
              : 'Pedidos - ${SessaoLoja.mercadoNome}',
        ),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: carregarResumo,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  topoResumo(total: total),
                  if (!entregador)
                    cardStatus(
                      context: context,
                      titulo: 'Aguardando aceite',
                      subtitulo: 'Pedidos aguardando confirmação',
                      quantidade: novos,
                      cor: corNovos,
                      icone: Icons.shopping_bag_outlined,
                      status: 'novo',
                    ),
                  if (!entregador)
                    cardStatus(
                      context: context,
                      titulo: 'Aceitos',
                      subtitulo: 'Aguardando início da preparação',
                      quantidade: aceitos,
                      cor: Colors.green,
                      icone: Icons.verified_outlined,
                      status: 'aceito',
                    ),
                  if (!entregador)
                    cardStatus(
                      context: context,
                      titulo: 'Preparação',
                      subtitulo: 'Pedidos sendo separados',
                      quantidade: preparando,
                      cor: Colors.blue,
                      icone: Icons.restaurant_menu,
                      status: 'preparando',
                    ),
                  cardStatus(
                    context: context,
                    titulo: 'Entrega',
                    subtitulo: 'Pedidos que saíram para entrega',
                    quantidade: entrega,
                    cor: Colors.purple,
                    icone: Icons.delivery_dining,
                    status: 'saiu_para_entrega',
                  ),
                  if (!entregador)
                    cardStatus(
                      context: context,
                      titulo: 'Entregues',
                      subtitulo: 'Pedidos finalizados',
                      quantidade: entregues,
                      cor: Colors.green,
                      icone: Icons.check_circle,
                      status: 'entregue',
                    ),
                  if (!entregador) cardTodos(context: context, total: total),
                ],
              ),
            ),
    );
  }
}

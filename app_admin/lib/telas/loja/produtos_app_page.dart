import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/central_service.dart';
import '../../services/sessao_loja.dart';

class ProdutosAppPage extends StatefulWidget {
  const ProdutosAppPage({super.key});

  @override
  State<ProdutosAppPage> createState() => _ProdutosAppPageState();
}

class _ProdutosAppPageState extends State<ProdutosAppPage> {
  static Color get vermelho => SessaoLoja.corPrimaria;

  final buscaController = TextEditingController();
  final centralService = CentralService();

  bool carregando = true;
  bool salvando = false;

  Color corPrimaria = vermelho;
  Color corSecundaria = SessaoLoja.corSecundaria;
  Color corFundo = SessaoLoja.corFundo;

  List<Map<String, dynamic>> produtos = [];

  SupabaseClient get supabase {
    return SessaoLoja.supabaseLoja ?? Supabase.instance.client;
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      carregarTemaDinamico();
      carregarProdutos();
    });
  }

  @override
  void dispose() {
    buscaController.dispose();
    super.dispose();
  }

  String texto(dynamic valor) {
    return valor?.toString().trim() ?? '';
  }

  double numero(dynamic valor) {
    if (valor == null) return 0;

    if (valor is num) return valor.toDouble();

    var t = valor.toString().trim();

    if (t.isEmpty) return 0;

    t = t
        .replaceAll('R\$', '')
        .replaceAll('KG', '')
        .replaceAll('UN', '')
        .trim();

    if (t.contains(',') && t.contains('.')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else if (t.contains(',')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    }

    return double.tryParse(t) ?? 0;
  }

  String moeda(dynamic valor) {
    final n = numero(valor);
    return 'R\$ ${n.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String quantidade(dynamic valor) {
    final n = numero(valor);

    if (n == n.roundToDouble()) {
      return n.round().toString();
    }

    return n.toStringAsFixed(3).replaceAll('.', ',');
  }

  String normalizarTipoProduto(dynamic valor) {
    final tipo = valor?.toString().trim().toUpperCase() ?? '';

    if (tipo == 'INSUMO' || tipo == 'PRODUZIDO' || tipo == 'VENDA_E_INSUMO') {
      return tipo;
    }

    return 'VENDA';
  }

  String rotuloTipoProduto(String tipo) {
    switch (normalizarTipoProduto(tipo)) {
      case 'INSUMO':
        return 'Insumo / consumo';
      case 'PRODUZIDO':
        return 'Produto produzido';
      case 'VENDA_E_INSUMO':
        return 'Venda e insumo';
      case 'VENDA':
      default:
        return 'Produto de venda';
    }
  }

  bool produtoEhProduzido(Map<String, dynamic> produto) {
    return produto['produto_produzido'] == true ||
        normalizarTipoProduto(produto['tipo_produto']) == 'PRODUZIDO';
  }

  Color corHexParaColor(dynamic valor, Color fallback) {
    var textoCor = valor?.toString().trim() ?? '';

    if (textoCor.isEmpty) {
      return fallback;
    }

    if (!textoCor.startsWith('#')) {
      textoCor = '#$textoCor';
    }

    final valido = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(textoCor);

    if (!valido) {
      return fallback;
    }

    try {
      return Color(int.parse('FF${textoCor.substring(1)}', radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  Future<void> carregarTemaDinamico() async {
    try {
      final mercadoId = SessaoLoja.mercadoIdObrigatorio;

      final data = await Supabase.instance.client
          .from('mercados')
          .select('admin_cor_primaria, admin_cor_secundaria, admin_cor_fundo')
          .eq('id', mercadoId)
          .maybeSingle();

      if (!mounted || data == null) {
        return;
      }

      setState(() {
        corPrimaria = corHexParaColor(data['admin_cor_primaria'], vermelho);
        corSecundaria = corHexParaColor(
          data['admin_cor_secundaria'],
          SessaoLoja.corSecundaria,
        );
        corFundo = corHexParaColor(
          data['admin_cor_fundo'],
          const Color(0xFFF5F7FA),
        );
      });
    } catch (_) {
      // Mantém o vermelho padrão se não conseguir buscar as cores.
    }
  }

  void mostrarMensagem({required String texto, Color cor = Colors.green}) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(texto), backgroundColor: cor));
  }

  Future<void> carregarProdutos() async {
    if (!mounted) return;

    if (SessaoLoja.supabaseLoja == null) {
      setState(() {
        carregando = false;
      });

      mostrarMensagem(
        texto: 'Conexão da loja não carregada. Entre na loja novamente.',
        cor: Colors.red,
      );
      return;
    }

    setState(() {
      carregando = true;
    });

    try {
      final resposta = await centralService.listarProdutosApp(
        mercadoId: SessaoLoja.mercadoIdObrigatorio,
        mercadoCodigo: SessaoLoja.mercadoCodigo,
        busca: buscaController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        produtos = resposta;
      });
    } catch (e) {
      mostrarMensagem(
        texto:
            'Erro ao carregar produtos: ${CentralService.mensagemErroUsuario(e)}',
        cor: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          carregando = false;
        });
      }
    }
  }

  Future<void> alternarAtivo(Map<String, dynamic> produto, bool ativo) async {
    final id = texto(produto['id']);

    if (id.isEmpty) return;

    try {
      await centralService.alternarProdutoApp(
        mercadoId: SessaoLoja.mercadoIdObrigatorio,
        mercadoCodigo: SessaoLoja.mercadoCodigo,
        id: id,
        ativo: ativo,
      );

      await carregarProdutos();
    } catch (e) {
      mostrarMensagem(
        texto:
            'Erro ao alterar produto: ${CentralService.mensagemErroUsuario(e)}',
        cor: Colors.red,
      );
    }
  }

  Future<bool> produtoPossuiVinculos(String produtoId) async {
    final mercadoId = SessaoLoja.mercadoIdObrigatorio;

    final vinculosReceitaComoInsumo = await supabase
        .from('produto_receita_itens')
        .select('id')
        .eq('mercado_id', mercadoId)
        .eq('produto_insumo_id', produtoId)
        .limit(1);

    if (List<dynamic>.from(vinculosReceitaComoInsumo).isNotEmpty) {
      return true;
    }

    final vinculosReceitaComoFinal = await supabase
        .from('produto_receitas')
        .select('id')
        .eq('mercado_id', mercadoId)
        .eq('produto_final_id', produtoId)
        .limit(1);

    if (List<dynamic>.from(vinculosReceitaComoFinal).isNotEmpty) {
      return true;
    }

    final vinculosProducao = await supabase
        .from('produto_producoes')
        .select('id')
        .eq('mercado_id', mercadoId)
        .eq('produto_final_id', produtoId)
        .limit(1);

    if (List<dynamic>.from(vinculosProducao).isNotEmpty) {
      return true;
    }

    final vinculosMovimentacao = await supabase
        .from('produto_movimentacoes_app')
        .select('id')
        .eq('mercado_id', mercadoId)
        .eq('produto_id', produtoId)
        .limit(1);

    return List<dynamic>.from(vinculosMovimentacao).isNotEmpty;
  }

  Future<bool> confirmarInativarProdutoVinculado(String nome) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Produto vinculado'),
          content: Text(
            'O produto "$nome" está vinculado a uma receita, produção ou movimentação de estoque.\n\n'
            'Por segurança, ele não pode ser apagado fisicamente do banco.\n\n'
            'Deseja inativar o produto? Ele sai do app Mercado e não aparece mais como ativo, mas o histórico continua correto.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Inativar produto'),
            ),
          ],
        );
      },
    );

    return confirmar == true;
  }

  Future<void> inativarProdutoVinculado({
    required String id,
    required String nome,
  }) async {
    final confirmar = await confirmarInativarProdutoVinculado(nome);

    if (!confirmar) return;

    await supabase
        .from('produtos_app')
        .update({
          'ativo': false,
          'vende_no_app': false,
          'destaque': false,
          'atualizado_em': DateTime.now().toIso8601String(),
        })
        .eq('id', id)
        .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);

    await carregarProdutos();

    mostrarMensagem(
      texto: 'Produto inativado. Ele não aparecerá mais no app Mercado.',
      cor: Colors.orange,
    );
  }

  Future<void> excluirProduto(Map<String, dynamic> produto) async {
    final id = texto(produto['id']);
    final nome = texto(produto['nome_produto']);

    if (id.isEmpty) return;

    if (produtoEhProduzido(produto) && numero(produto['estoque']) > 0) {
      await showDialog<void>(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: const Text('Produto com estoque'),
            content: Text(
              'O produto produzido "$nome" ainda possui estoque.\n\n'
              'Zere ou baixe o estoque antes de excluir esse produto.',
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: corPrimaria,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendi'),
              ),
            ],
          );
        },
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Excluir produto'),
          content: Text(
            'Deseja excluir o produto "$nome"?\n\n'
            'Esse cadastro sera removido do banco.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    try {
      await centralService.excluirProdutoApp(
        mercadoId: SessaoLoja.mercadoIdObrigatorio,
        mercadoCodigo: SessaoLoja.mercadoCodigo,
        id: id,
      );

      await carregarProdutos();

      mostrarMensagem(texto: 'Produto excluído.');
    } catch (e) {
      final mensagem = e.toString().toLowerCase();

      if (mensagem.contains('foreign key') ||
          mensagem.contains('23503') ||
          mensagem.contains('produto_receita_itens_produto_insumo_id_fkey') ||
          mensagem.contains('produto_receitas_produto_final_id_fkey')) {
        mostrarMensagem(
          texto:
              'O banco ainda bloqueou a exclusao por vinculo de receita, producao ou movimentacao. Remova o vinculo ou ajuste as chaves estrangeiras antes de excluir.',
          cor: Colors.red,
        );
        return;
      }

      mostrarMensagem(
        texto:
            'Erro ao excluir produto: ${CentralService.mensagemErroUsuario(e)}',
        cor: Colors.red,
      );
    }
  }

  Future<void> abrirFormulario({Map<String, dynamic>? produto}) async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProdutoAppFormularioPage(
          produto: produto,
          corPrimaria: corPrimaria,
          corSecundaria: corSecundaria,
          corFundo: corFundo,
        ),
      ),
    );

    if (salvou == true) {
      await carregarProdutos();
      mostrarMensagem(
        texto: produto == null ? 'Produto cadastrado.' : 'Produto atualizado.',
      );
    }
  }

  Widget campoDialog({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool enabled,
    bool somenteNumero = false,
    bool decimal = false,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: somenteNumero || decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: [
        if (somenteNumero) FilteringTextInputFormatter.digitsOnly,
        if (decimal) FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget topo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [vermelho, vermelho.withValues(alpha: 0.82)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: corPrimaria.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.shopping_basket,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Produtos do app',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 21,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Cadastro usado quando a fonte de produtos for BANCO_LOJA.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget barraBusca() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: buscaController,
            onSubmitted: (_) => carregarProdutos(),
            decoration: InputDecoration(
              hintText: 'Buscar por nome, EAN, código ou categoria',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 54,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: corPrimaria,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: carregando ? null : carregarProdutos,
            icon: const Icon(Icons.search),
            label: const Text('Buscar'),
          ),
        ),
      ],
    );
  }

  Widget cardProduto(Map<String, dynamic> produto) {
    final ativo = produto['ativo'] != false;
    final destaque = produto['destaque'] == true;
    final pesoVariavel = produto['peso_variavel'] == true;
    final tipoProduto = normalizarTipoProduto(produto['tipo_produto']);
    final vendeNoApp = produto['vende_no_app'] != false;
    final consumoProducao = produto['consumo_producao'] == true;
    final produtoProduzido = produto['produto_produzido'] == true;
    final imagemUrl = texto(produto['imagem_url']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ativo
              ? Colors.black.withValues(alpha: 0.08)
              : Colors.red.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: imagemUrl.isEmpty
                ? Icon(
                    Icons.shopping_basket,
                    color: corPrimaria.withValues(alpha: 0.70),
                    size: 34,
                  )
                : Image.network(
                    imagemUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.image_not_supported_outlined,
                      color: corPrimaria.withValues(alpha: 0.70),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  texto(produto['nome_produto']),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15.5,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (texto(produto['ean']).isNotEmpty)
                      chipInfo('EAN ${texto(produto['ean'])}'),
                    chipInfo(
                      rotuloTipoProduto(tipoProduto),
                      cor: Colors.indigo,
                    ),
                    if (texto(produto['categoria']).isNotEmpty)
                      chipInfo(texto(produto['categoria'])),
                    if (vendeNoApp) chipInfo('Vende no app', cor: Colors.green),
                    if (!vendeNoApp)
                      chipInfo('Não vende no app', cor: Colors.orange),
                    if (consumoProducao) chipInfo('Insumo'),
                    if (produtoProduzido) chipInfo('Produzido'),
                    if (pesoVariavel) chipInfo('Peso variável'),
                    if (destaque) chipInfo('Destaque'),
                    if (!ativo) chipInfo('Inativo', cor: Colors.red),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      moeda(produto['preco_promocional'] ?? produto['preco']),
                      style: TextStyle(
                        color: corPrimaria,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Estoque: ${quantidade(produto['estoque'])} ${texto(produto['unidade']).isEmpty ? 'UN' : texto(produto['unidade'])}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Switch(
                value: ativo,
                activeThumbColor: corPrimaria,
                onChanged: (valor) => alternarAtivo(produto, valor),
              ),
              PopupMenuButton<String>(
                onSelected: (acao) {
                  if (acao == 'editar') {
                    abrirFormulario(produto: produto);
                  } else if (acao == 'excluir') {
                    excluirProduto(produto);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'editar',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined),
                        SizedBox(width: 8),
                        Text('Editar'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'excluir',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Excluir'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget chipInfo(String texto, {Color? cor}) {
    final chipCor = cor ?? vermelho;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipCor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: chipCor.withValues(alpha: 0.18)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: chipCor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget listaProdutos() {
    if (carregando) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (produtos.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: const Column(
          children: [
            Icon(Icons.inventory_2_outlined, size: 46, color: Colors.black38),
            SizedBox(height: 10),
            Text(
              'Nenhum produto encontrado',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 4),
            Text(
              'Cadastre produtos para lojas que usam a fonte BANCO_LOJA.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      );
    }

    return Column(children: produtos.map(cardProduto).toList());
  }

  @override
  Widget build(BuildContext context) {
    final nomeLoja = SessaoLoja.mercadoNome ?? 'Loja';

    return Scaffold(
      backgroundColor: SessaoLoja.corFundo,
      appBar: AppBar(
        title: Text('Produtos - $nomeLoja'),
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: carregando ? null : carregarProdutos,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
        onPressed: salvando ? null : () => abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Novo produto'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: carregarProdutos,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              topo(),
              const SizedBox(height: 18),
              barraBusca(),
              const SizedBox(height: 18),
              Text(
                '${produtos.length} produto(s) carregado(s)',
                style: const TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              listaProdutos(),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}

class ProdutoAppFormularioPage extends StatefulWidget {
  final Map<String, dynamic>? produto;
  final Color corPrimaria;
  final Color corSecundaria;
  final Color corFundo;

  const ProdutoAppFormularioPage({
    super.key,
    this.produto,
    required this.corPrimaria,
    required this.corSecundaria,
    required this.corFundo,
  });

  @override
  State<ProdutoAppFormularioPage> createState() =>
      _ProdutoAppFormularioPageState();
}

class _ProdutoAppFormularioPageState extends State<ProdutoAppFormularioPage> {
  final centralService = CentralService();
  final imagePicker = ImagePicker();

  final eanController = TextEditingController();
  final codigoBarrasController = TextEditingController();
  final nomeController = TextEditingController();
  final descricaoController = TextEditingController();
  final categoriaController = TextEditingController();
  final subcategoriaController = TextEditingController();
  final marcaController = TextEditingController();
  final precoController = TextEditingController();
  final precoPromocionalController = TextEditingController();
  final unidadeController = TextEditingController(text: 'UN');
  final estoqueController = TextEditingController(text: '0');
  final imagemUrlController = TextEditingController();
  final pesoMedioController = TextEditingController();

  bool salvando = false;
  bool buscandoImagem = false;
  bool enviandoImagem = false;
  bool ativo = true;
  bool destaque = false;
  bool pesoVariavel = false;
  bool vendeNoApp = true;
  bool consumoProducao = false;
  bool produtoProduzido = false;
  bool controlaEstoque = true;
  String tipoProduto = 'VENDA';

  bool get editando => widget.produto != null;

  Color get corPrimaria => widget.corPrimaria;
  Color get corSecundaria => widget.corSecundaria;
  Color get corFundo => widget.corFundo;

  @override
  void initState() {
    super.initState();

    final produto = widget.produto;

    if (produto != null) {
      eanController.text = texto(produto['ean']);
      codigoBarrasController.text = texto(produto['codigo_barras']).isNotEmpty
          ? texto(produto['codigo_barras'])
          : texto(produto['ean']);
      nomeController.text = texto(produto['nome_produto']);
      descricaoController.text = texto(produto['descricao']);
      categoriaController.text = texto(produto['categoria']);
      subcategoriaController.text = texto(produto['subcategoria']);
      marcaController.text = texto(produto['marca']);
      precoController.text = moeda(produto['preco']).replaceAll('R\$ ', '');
      precoPromocionalController.text = produto['preco_promocional'] == null
          ? ''
          : moeda(produto['preco_promocional']).replaceAll('R\$ ', '');
      unidadeController.text = texto(produto['unidade']).isEmpty
          ? 'UN'
          : texto(produto['unidade']);
      estoqueController.text = quantidade(produto['estoque']);
      imagemUrlController.text = texto(produto['imagem_url']);
      pesoMedioController.text = produto['peso_medio_kg'] == null
          ? ''
          : quantidade(produto['peso_medio_kg']);

      tipoProduto = normalizarTipoProduto(produto['tipo_produto']);
      ativo = produto['ativo'] != false;
      destaque = produto['destaque'] == true;
      pesoVariavel = produto['peso_variavel'] == true;
      vendeNoApp = produto['vende_no_app'] != false;
      consumoProducao = produto['consumo_producao'] == true;
      produtoProduzido = produto['produto_produzido'] == true;
      controlaEstoque = produto['controla_estoque'] != false;
    }

    imagemUrlController.addListener(atualizarPreviewImagem);
  }

  @override
  void dispose() {
    imagemUrlController.removeListener(atualizarPreviewImagem);
    eanController.dispose();
    codigoBarrasController.dispose();
    nomeController.dispose();
    descricaoController.dispose();
    categoriaController.dispose();
    subcategoriaController.dispose();
    marcaController.dispose();
    precoController.dispose();
    precoPromocionalController.dispose();
    unidadeController.dispose();
    estoqueController.dispose();
    imagemUrlController.dispose();
    pesoMedioController.dispose();
    super.dispose();
  }

  void atualizarPreviewImagem() {
    if (!mounted) return;
    setState(() {});
  }

  String texto(dynamic valor) {
    return valor?.toString().trim() ?? '';
  }

  double numero(dynamic valor) {
    if (valor == null) return 0;
    if (valor is num) return valor.toDouble();

    var t = valor.toString().trim();

    if (t.isEmpty) return 0;

    t = t
        .replaceAll('R\$', '')
        .replaceAll('KG', '')
        .replaceAll('UN', '')
        .trim();

    if (t.contains(',') && t.contains('.')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else if (t.contains(',')) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    }

    return double.tryParse(t) ?? 0;
  }

  String moeda(dynamic valor) {
    final n = numero(valor);
    return 'R\$ ${n.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String quantidade(dynamic valor) {
    final n = numero(valor);

    if (n == n.roundToDouble()) {
      return n.round().toString();
    }

    return n.toStringAsFixed(3).replaceAll('.', ',');
  }

  String normalizarTipoProduto(dynamic valor) {
    final tipo = valor?.toString().trim().toUpperCase() ?? '';

    if (tipo == 'INSUMO' || tipo == 'PRODUZIDO' || tipo == 'VENDA_E_INSUMO') {
      return tipo;
    }

    return 'VENDA';
  }

  String rotuloTipoProduto(String tipo) {
    switch (normalizarTipoProduto(tipo)) {
      case 'INSUMO':
        return 'Insumo / consumo';
      case 'PRODUZIDO':
        return 'Produto produzido';
      case 'VENDA_E_INSUMO':
        return 'Venda e insumo';
      case 'VENDA':
      default:
        return 'Produto de venda';
    }
  }

  void aplicarRegraTipo(String valor) {
    setState(() {
      tipoProduto = valor;

      if (valor == 'VENDA') {
        vendeNoApp = true;
        consumoProducao = false;
        produtoProduzido = false;
      } else if (valor == 'INSUMO') {
        vendeNoApp = false;
        consumoProducao = true;
        produtoProduzido = false;
      } else if (valor == 'PRODUZIDO') {
        vendeNoApp = true;
        consumoProducao = false;
        produtoProduzido = true;
      } else if (valor == 'VENDA_E_INSUMO') {
        vendeNoApp = true;
        consumoProducao = true;
        produtoProduzido = false;
      }
    });
  }

  void mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: Colors.red),
    );
  }

  void mostrarMensagem(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: corPrimaria),
    );
  }

  String codigoImagemProduto() {
    final codigoBarras = codigoBarrasController.text.trim();
    final ean = eanController.text.trim();

    if (codigoBarras.isNotEmpty) {
      return codigoBarras;
    }

    return ean;
  }

  Future<void> buscarImagemCentral() async {
    if (buscandoImagem || enviandoImagem || salvando) return;

    final codigo = codigoImagemProduto();
    final nome = nomeController.text.trim();

    if (codigo.isEmpty && nome.isEmpty) {
      mostrarErro('Informe o EAN/codigo ou o nome do produto.');
      return;
    }

    setState(() {
      buscandoImagem = true;
    });

    try {
      final resposta = await centralService.buscarImagemProdutoCentral(
        mercadoId: SessaoLoja.mercadoIdObrigatorio,
        mercadoCodigo: SessaoLoja.mercadoCodigo,
        ean: codigo.isEmpty ? null : codigo,
        codigoBarras: codigo.isEmpty ? null : codigo,
        nomeProduto: nome.isEmpty ? null : nome,
      );

      final url = texto(
        resposta['imagem_url'] ??
            resposta['url'] ??
            resposta['image'] ??
            resposta['thumbnail'],
      );

      if (url.isNotEmpty) {
        imagemUrlController.text = url;
        mostrarMensagem('Imagem encontrada no Central.');
        return;
      }

      if (mounted) {
        setState(() {
          buscandoImagem = false;
        });
      }

      await mostrarOpcoesImagemNaoEncontrada();
    } catch (e) {
      mostrarErro(
        'Erro ao buscar imagem: ${CentralService.mensagemErroUsuario(e)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          buscandoImagem = false;
        });
      }
    }
  }

  Future<void> selecionarEEnviarImagem() async {
    if (buscandoImagem || enviandoImagem || salvando) return;

    try {
      final imagem = await imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        imageQuality: 88,
      );

      if (imagem == null) return;

      setState(() {
        enviandoImagem = true;
      });

      final resposta = await centralService.uploadImagemProdutoApp(
        mercadoId: SessaoLoja.mercadoIdObrigatorio,
        mercadoCodigo: SessaoLoja.mercadoCodigo,
        imagemFile: File(imagem.path),
        ean: eanController.text.trim(),
        codigoBarras: codigoBarrasController.text.trim(),
        nomeProduto: nomeController.text.trim(),
      );

      final url = texto(resposta['imagem_url']);

      if (url.isEmpty) {
        mostrarErro('Upload concluido, mas a URL da imagem nao retornou.');
        return;
      }

      imagemUrlController.text = url;
      mostrarMensagem('Imagem enviada com sucesso.');
    } catch (e) {
      mostrarErro(
        'Erro ao enviar imagem: ${CentralService.mensagemErroUsuario(e)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          enviandoImagem = false;
        });
      }
    }
  }

  Future<void> informarUrlImagem() async {
    var urlDigitada = imagemUrlController.text;

    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('URL da imagem'),
          content: TextFormField(
            initialValue: urlDigitada,
            autofocus: true,
            onChanged: (valor) => urlDigitada = valor,
            onFieldSubmitted: (valor) {
              FocusScope.of(dialogContext).unfocus();
              Navigator.pop(dialogContext, valor.trim());
            },
            decoration: const InputDecoration(
              labelText: 'Cole a URL da imagem',
              prefixIcon: Icon(Icons.link),
            ),
            keyboardType: TextInputType.url,
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.pop(dialogContext, urlDigitada.trim());
              },
              child: const Text('Aplicar'),
            ),
          ],
        );
      },
    );

    if (url == null) return;

    imagemUrlController.text = url;
  }

  Future<void> mostrarOpcoesImagemNaoEncontrada() async {
    if (!mounted) return;

    final escolha = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (bottomContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Imagem nao encontrada no Central',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Escolha uma imagem do aparelho ou informe uma URL manualmente.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 14),
                ListTile(
                  leading: Icon(Icons.upload_file, color: corPrimaria),
                  title: const Text('Fazer upload da imagem'),
                  onTap: () {
                    Navigator.pop(bottomContext, 'upload');
                  },
                ),
                ListTile(
                  leading: Icon(Icons.link, color: corPrimaria),
                  title: const Text('Informar URL da imagem'),
                  onTap: () {
                    Navigator.pop(bottomContext, 'url');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || escolha == null) return;

    await Future<void>.delayed(Duration.zero);

    if (!mounted) return;

    if (escolha == 'upload') {
      await selecionarEEnviarImagem();
    } else if (escolha == 'url') {
      await informarUrlImagem();
    }
  }

  Future<void> salvar() async {
    final ean = eanController.text.trim();
    final codigoBarras = codigoBarrasController.text.trim();
    final nome = nomeController.text.trim();
    final preco = numero(precoController.text);
    final precoPromocionalTexto = precoPromocionalController.text.trim();
    final precoPromocional = precoPromocionalTexto.isEmpty
        ? null
        : numero(precoPromocionalTexto);
    final unidade = unidadeController.text.trim().toUpperCase();
    final estoque = numero(estoqueController.text);
    final pesoMedioTexto = pesoMedioController.text.trim();
    final pesoMedio = pesoMedioTexto.isEmpty ? null : numero(pesoMedioTexto);

    if (nome.isEmpty) {
      mostrarErro('Informe o nome do produto.');
      return;
    }

    if (preco <= 0) {
      mostrarErro('Informe o preço do produto.');
      return;
    }

    if (unidade.isEmpty) {
      mostrarErro('Informe a unidade. Ex: UN, KG, CX.');
      return;
    }

    if (pesoVariavel && pesoMedio != null && pesoMedio <= 0) {
      mostrarErro('Peso médio precisa ser maior que zero.');
      return;
    }

    setState(() {
      salvando = true;
    });

    final dados = <String, dynamic>{
      ...SessaoLoja.dadosMercadoRegistro,
      'ean': ean.isEmpty ? null : ean,
      'codigo_barras': codigoBarras.isEmpty
          ? (ean.isEmpty ? null : ean)
          : codigoBarras,
      'nome_produto': nome,
      'descricao': descricaoController.text.trim().isEmpty
          ? null
          : descricaoController.text.trim(),
      'categoria': categoriaController.text.trim().isEmpty
          ? null
          : categoriaController.text.trim(),
      'subcategoria': subcategoriaController.text.trim().isEmpty
          ? null
          : subcategoriaController.text.trim(),
      'marca': marcaController.text.trim().isEmpty
          ? null
          : marcaController.text.trim(),
      'preco': preco,
      'preco_promocional': precoPromocional,
      'unidade': unidade,
      'estoque': estoque,
      'imagem_url': imagemUrlController.text.trim().isEmpty
          ? null
          : imagemUrlController.text.trim(),
      'peso_variavel': pesoVariavel,
      'peso_medio_kg': pesoVariavel ? pesoMedio : null,
      'tipo_produto': tipoProduto,
      'vende_no_app': vendeNoApp,
      'consumo_producao': consumoProducao,
      'produto_produzido': produtoProduzido,
      'controla_estoque': controlaEstoque,
      'destaque': destaque,
      'ativo': ativo,
      'origem': 'BANCO_LOJA',
      'atualizado_em': DateTime.now().toIso8601String(),
    };

    try {
      await centralService.salvarProdutoApp(
        mercadoId: SessaoLoja.mercadoIdObrigatorio,
        mercadoCodigo: SessaoLoja.mercadoCodigo,
        id: editando ? widget.produto!['id']?.toString() : null,
        produto: dados,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      mostrarErro(
        'Erro ao salvar produto: ${CentralService.mensagemErroUsuario(e)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          salvando = false;
        });
      }
    }
  }

  Widget campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool somenteNumero = false,
    bool decimal = false,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      enabled: !salvando,
      maxLines: maxLines,
      keyboardType: somenteNumero || decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: [
        if (somenteNumero) FilteringTextInputFormatter.digitsOnly,
        if (decimal) FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Padding(
          padding: const EdgeInsets.all(9),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: corPrimaria.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: corPrimaria, size: 21),
          ),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: corPrimaria, width: 1.8),
        ),
      ),
    );
  }

  Widget painelImagemProduto() {
    final imagemUrl = imagemUrlController.text.trim();
    final ocupado = salvando || buscandoImagem || enviandoImagem;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: corPrimaria.withValues(alpha: 0.16),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: imagemUrl.isEmpty
                    ? Icon(
                        Icons.image_outlined,
                        color: corPrimaria.withValues(alpha: 0.55),
                        size: 34,
                      )
                    : Image.network(
                        imagemUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.broken_image_outlined,
                            color: corPrimaria.withValues(alpha: 0.65),
                            size: 34,
                          );
                        },
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Imagem do produto',
                      style: TextStyle(
                        color: Color(0xFF1F2937),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      imagemUrl.isEmpty
                          ? 'Busque no Central, envie uma imagem ou informe uma URL.'
                          : 'Imagem definida para este produto.',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: ocupado ? null : buscarImagemCentral,
                          icon: buscandoImagem
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.search),
                          label: Text(
                            buscandoImagem ? 'Buscando...' : 'Buscar Central',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: corPrimaria,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: ocupado ? null : selecionarEEnviarImagem,
                          icon: enviandoImagem
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: corPrimaria,
                                  ),
                                )
                              : const Icon(Icons.upload_file),
                          label: Text(
                            enviandoImagem ? 'Enviando...' : 'Upload',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: corPrimaria,
                            side: BorderSide(color: corPrimaria),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: ocupado ? null : informarUrlImagem,
                          icon: const Icon(Icons.link),
                          label: const Text('URL'),
                          style: TextButton.styleFrom(
                            foregroundColor: corPrimaria,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          campo(
            controller: imagemUrlController,
            label: 'URL da imagem',
            icon: Icons.image_outlined,
          ),
        ],
      ),
    );
  }

  Widget cardSecao({
    required String titulo,
    required IconData icone,
    required List<Widget> children,
    String? subtitulo,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: corPrimaria.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icone, color: corPrimaria),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (subtitulo != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget seletorTipo() {
    return DropdownButtonFormField<String>(
      value: tipoProduto,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Tipo do produto',
        prefixIcon: Icon(Icons.tune, color: corPrimaria),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: corPrimaria, width: 1.8),
        ),
      ),
      items: const [
        DropdownMenuItem(value: 'VENDA', child: Text('Produto de venda')),
        DropdownMenuItem(value: 'INSUMO', child: Text('Insumo / consumo')),
        DropdownMenuItem(value: 'PRODUZIDO', child: Text('Produto produzido')),
        DropdownMenuItem(
          value: 'VENDA_E_INSUMO',
          child: Text('Venda e insumo'),
        ),
      ],
      onChanged: salvando
          ? null
          : (valor) {
              if (valor == null) return;
              aplicarRegraTipo(valor);
            },
    );
  }

  Widget switchCard({
    required bool value,
    required String titulo,
    required String subtitulo,
    required IconData icone,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.only(left: 12, right: 4, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: value
            ? corPrimaria.withValues(alpha: 0.06)
            : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: value
              ? corPrimaria.withValues(alpha: 0.18)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Icon(icone, color: value ? corPrimaria : Colors.black38),
          const SizedBox(width: 10),
          Expanded(
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                titulo,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(subtitulo),
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: corPrimaria,
            onChanged: salvando ? null : onChanged,
          ),
        ],
      ),
    );
  }

  Widget topo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [corPrimaria, corSecundaria],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: corPrimaria.withValues(alpha: 0.25),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.shopping_basket, color: corPrimaria, size: 34),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editando ? 'Editar produto' : 'Novo produto',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${SessaoLoja.mercadoNome ?? 'Loja'} • ${rotuloTipoProduto(tipoProduto)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget botoesRodape() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: salvando ? null : () => Navigator.pop(context, false),
            icon: const Icon(Icons.close),
            label: const Text('Cancelar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: corPrimaria,
              side: BorderSide(color: corPrimaria),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: salvando ? null : salvar,
            icon: salvando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(salvando ? 'Salvando...' : 'Salvar produto'),
            style: ElevatedButton.styleFrom(
              backgroundColor: corPrimaria,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.of(context).size.width;
    final duasColunas = largura >= 760;

    return Scaffold(
      backgroundColor: corFundo,
      appBar: AppBar(
        title: Text(editando ? 'Editar produto' : 'Novo produto'),
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            topo(),
            const SizedBox(height: 18),
            cardSecao(
              titulo: 'Informações principais',
              subtitulo: 'Nome, código de barras e descrição do produto.',
              icone: Icons.info_outline,
              children: [
                if (duasColunas)
                  Row(
                    children: [
                      Expanded(
                        child: campo(
                          controller: eanController,
                          label: 'EAN',
                          icon: Icons.qr_code,
                          somenteNumero: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: campo(
                          controller: codigoBarrasController,
                          label: 'Código barras',
                          icon: Icons.barcode_reader,
                          somenteNumero: true,
                        ),
                      ),
                    ],
                  )
                else ...[
                  campo(
                    controller: eanController,
                    label: 'EAN',
                    icon: Icons.qr_code,
                    somenteNumero: true,
                  ),
                  const SizedBox(height: 12),
                  campo(
                    controller: codigoBarrasController,
                    label: 'Código barras',
                    icon: Icons.barcode_reader,
                    somenteNumero: true,
                  ),
                ],
                const SizedBox(height: 12),
                campo(
                  controller: nomeController,
                  label: 'Nome do produto *',
                  icon: Icons.shopping_basket,
                ),
                const SizedBox(height: 12),
                campo(
                  controller: descricaoController,
                  label: 'Descrição',
                  icon: Icons.description_outlined,
                  maxLines: 2,
                ),
              ],
            ),
            cardSecao(
              titulo: 'Classificação',
              subtitulo: 'Define se aparece no app ou se é usado como insumo.',
              icone: Icons.category,
              children: [
                seletorTipo(),
                const SizedBox(height: 12),
                if (duasColunas)
                  Row(
                    children: [
                      Expanded(
                        child: campo(
                          controller: categoriaController,
                          label: 'Categoria',
                          icon: Icons.category_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: campo(
                          controller: subcategoriaController,
                          label: 'Subcategoria',
                          icon: Icons.account_tree_outlined,
                        ),
                      ),
                    ],
                  )
                else ...[
                  campo(
                    controller: categoriaController,
                    label: 'Categoria',
                    icon: Icons.category_outlined,
                  ),
                  const SizedBox(height: 12),
                  campo(
                    controller: subcategoriaController,
                    label: 'Subcategoria',
                    icon: Icons.account_tree_outlined,
                  ),
                ],
                const SizedBox(height: 12),
                campo(
                  controller: marcaController,
                  label: 'Marca',
                  icon: Icons.label_outline,
                ),
              ],
            ),
            cardSecao(
              titulo: 'Preço e estoque',
              subtitulo:
                  'Valores usados no app Mercado quando for produto de venda.',
              icone: Icons.attach_money,
              children: [
                if (duasColunas)
                  Row(
                    children: [
                      Expanded(
                        child: campo(
                          controller: precoController,
                          label: 'Preço *',
                          icon: Icons.payments_outlined,
                          decimal: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: campo(
                          controller: precoPromocionalController,
                          label: 'Preço promocional',
                          icon: Icons.local_offer_outlined,
                          decimal: true,
                        ),
                      ),
                    ],
                  )
                else ...[
                  campo(
                    controller: precoController,
                    label: 'Preço *',
                    icon: Icons.payments_outlined,
                    decimal: true,
                  ),
                  const SizedBox(height: 12),
                  campo(
                    controller: precoPromocionalController,
                    label: 'Preço promocional',
                    icon: Icons.local_offer_outlined,
                    decimal: true,
                  ),
                ],
                const SizedBox(height: 12),
                if (duasColunas)
                  Row(
                    children: [
                      Expanded(
                        child: campo(
                          controller: unidadeController,
                          label: 'Unidade *',
                          icon: Icons.straighten,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: campo(
                          controller: estoqueController,
                          label: 'Estoque',
                          icon: Icons.inventory_2_outlined,
                          decimal: true,
                        ),
                      ),
                    ],
                  )
                else ...[
                  campo(
                    controller: unidadeController,
                    label: 'Unidade *',
                    icon: Icons.straighten,
                  ),
                  const SizedBox(height: 12),
                  campo(
                    controller: estoqueController,
                    label: 'Estoque',
                    icon: Icons.inventory_2_outlined,
                    decimal: true,
                  ),
                ],
              ],
            ),
            cardSecao(
              titulo: 'Imagem e regras',
              subtitulo: 'Controle de exibição no app, produção e estoque.',
              icone: Icons.tune,
              children: [
                painelImagemProduto(),
                const SizedBox(height: 12),
                switchCard(
                  value: vendeNoApp,
                  titulo: 'Vender no app Mercado',
                  subtitulo:
                      'Quando desligado, o produto não aparece para o cliente.',
                  icone: Icons.storefront,
                  onChanged: (valor) => setState(() => vendeNoApp = valor),
                ),
                switchCard(
                  value: consumoProducao,
                  titulo: 'Usar como insumo/consumo',
                  subtitulo: 'Farinha, ovo, leite e itens usados em produção.',
                  icone: Icons.restaurant,
                  onChanged: (valor) => setState(() => consumoProducao = valor),
                ),
                switchCard(
                  value: produtoProduzido,
                  titulo: 'Produto produzido',
                  subtitulo:
                      'Bolos, pães, salgados e produtos fabricados pela loja.',
                  icone: Icons.bakery_dining,
                  onChanged: (valor) =>
                      setState(() => produtoProduzido = valor),
                ),
                switchCard(
                  value: controlaEstoque,
                  titulo: 'Controlar estoque',
                  subtitulo:
                      'Usado para controle de saldo e futura ficha técnica.',
                  icone: Icons.inventory,
                  onChanged: (valor) => setState(() => controlaEstoque = valor),
                ),
                switchCard(
                  value: pesoVariavel,
                  titulo: 'Produto de peso variável',
                  subtitulo: 'Use para produtos vendidos por KG.',
                  icone: Icons.scale,
                  onChanged: (valor) => setState(() => pesoVariavel = valor),
                ),
                if (pesoVariavel) ...[
                  const SizedBox(height: 4),
                  campo(
                    controller: pesoMedioController,
                    label: 'Peso médio KG',
                    icon: Icons.scale_outlined,
                    decimal: true,
                  ),
                ],
                switchCard(
                  value: destaque,
                  titulo: 'Produto em destaque',
                  subtitulo: 'Destaca o produto nas listagens do app.',
                  icone: Icons.star_outline,
                  onChanged: (valor) => setState(() => destaque = valor),
                ),
                switchCard(
                  value: ativo,
                  titulo: 'Produto ativo',
                  subtitulo: 'Produtos inativos não aparecem no app.',
                  icone: Icons.check_circle_outline,
                  onChanged: (valor) => setState(() => ativo = valor),
                ),
              ],
            ),
            const SizedBox(height: 4),
            botoesRodape(),
            const SizedBox(height: 26),
          ],
        ),
      ),
    );
  }
}

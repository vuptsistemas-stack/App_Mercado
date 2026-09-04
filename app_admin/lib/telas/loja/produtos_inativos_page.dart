import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/central_service.dart';
import '../../services/sessao_loja.dart';

class ProdutosInativosPage extends StatefulWidget {
  final String busca;
  final List<Map<String, dynamic>> produtos;

  const ProdutosInativosPage({
    super.key,
    required this.busca,
    required this.produtos,
  });

  @override
  State<ProdutosInativosPage> createState() => _ProdutosInativosPageState();
}

class _ProdutosInativosPageState extends State<ProdutosInativosPage> {
  final centralService = CentralService();

  late List<Map<String, dynamic>> produtos;

  bool carregandoToken = true;
  bool tokenUpdateAtivo = false;
  bool houveAtivacao = false;
  String tokenUpdate = '';
  String? ativandoProdutoId;

  static Color get corPrimaria => SessaoLoja.corPrimaria;
  static Color get fundo => SessaoLoja.corFundo;

  @override
  void initState() {
    super.initState();
    produtos = List<Map<String, dynamic>>.from(widget.produtos);
    carregarTokenUpdate();
  }

  Future<void> carregarTokenUpdate() async {
    final mercadoId = SessaoLoja.mercadoId?.trim() ?? '';

    if (mercadoId.isEmpty) {
      setState(() {
        carregandoToken = false;
      });
      return;
    }

    try {
      final conexao = await centralService.buscarConexaoMercado(mercadoId);

      if (!mounted) return;

      setState(() {
        tokenUpdate = conexao['estoque_update_token']?.toString().trim() ?? '';
        tokenUpdateAtivo = SessaoLoja.booleanoDinamico(
          conexao['estoque_update_token_ativo'],
          padrao: false,
        );
        carregandoToken = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        tokenUpdate = '';
        tokenUpdateAtivo = false;
        carregandoToken = false;
      });
    }
  }

  String texto(dynamic valor) {
    return valor?.toString().trim() ?? '';
  }

  String nomeProduto(Map<String, dynamic> produto) {
    final nome = texto(produto['nome_produto'] ?? produto['descricao']);
    return nome.isEmpty ? 'Produto sem nome' : nome;
  }

  String eanProduto(Map<String, dynamic> produto) {
    final ean = texto(produto['ean_principal'] ?? produto['ean']);
    return ean.isEmpty ? '-' : ean;
  }

  String estoqueProduto(Map<String, dynamic> produto) {
    final bruto = produto['estoque_atual'] ?? produto['estoque'] ?? 0;
    final numero = double.tryParse(texto(bruto).replaceAll(',', '.'));

    if (numero == null) {
      return texto(bruto).isEmpty ? '0' : texto(bruto);
    }

    if (numero == numero.roundToDouble()) {
      return numero.toStringAsFixed(0);
    }

    return numero.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  }

  String produtoId(Map<String, dynamic> produto) {
    return texto(produto['produto_id'] ?? produto['id']);
  }

  Map<String, String> headersAtivacao() {
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (tokenUpdate.isNotEmpty) {
      headers['x-api-key'] = tokenUpdate;
    }

    return headers;
  }

  void mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: erro ? Colors.red : Colors.green,
        content: Text(mensagem),
      ),
    );
  }

  Future<bool> confirmarAtivacao(Map<String, dynamic> produto) async {
    final resposta = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ativar produto'),
          content: Text(
            'Deseja ativar "${nomeProduto(produto)}" na API da loja?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: corPrimaria,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ativar'),
            ),
          ],
        );
      },
    );

    return resposta == true;
  }

  Future<void> ativarProduto(Map<String, dynamic> produto) async {
    final api = SessaoLoja.apiBaseUrl?.trim() ?? '';
    final id = produtoId(produto);

    if (api.isEmpty) {
      mostrarMensagem('API da loja nao configurada.', erro: true);
      return;
    }

    if (id.isEmpty) {
      mostrarMensagem('Produto sem produto_id.', erro: true);
      return;
    }

    if (tokenUpdateAtivo && tokenUpdate.isEmpty) {
      mostrarMensagem(
        'Token de update nao carregado. Verifique a configuracao da loja.',
        erro: true,
      );
      return;
    }

    final confirmar = await confirmarAtivacao(produto);

    if (!mounted || !confirmar) return;

    setState(() {
      ativandoProdutoId = id;
    });

    try {
      final resposta = await http
          .patch(
            Uri.parse('$api/produto/inativos/$id/ativar'),
            headers: headersAtivacao(),
            body: jsonEncode({}),
          )
          .timeout(const Duration(seconds: 20));

      dynamic data;

      try {
        data = jsonDecode(resposta.body);
      } catch (_) {
        data = null;
      }

      if (!mounted) return;

      if (resposta.statusCode >= 200 && resposta.statusCode < 300) {
        setState(() {
          produtos.removeWhere((item) => produtoId(item) == id);
          houveAtivacao = true;
        });

        mostrarMensagem('Produto ativado.');
        return;
      }

      final detalhe = data is Map
          ? texto(data['erro'] ?? data['error'] ?? data['mensagem'])
          : '';

      mostrarMensagem(
        detalhe.isEmpty
            ? 'Nao foi possivel ativar o produto.'
            : 'Nao foi possivel ativar: $detalhe',
        erro: true,
      );
    } catch (_) {
      mostrarMensagem('Erro de conexao ao ativar produto.', erro: true);
    } finally {
      if (mounted) {
        setState(() {
          ativandoProdutoId = null;
        });
      }
    }
  }

  void voltar() {
    Navigator.pop(context, houveAtivacao);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fundo,
      appBar: AppBar(
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
        title: const Text('Produtos inativos'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: voltar,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: corPrimaria.withValues(alpha: 0.18)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: corPrimaria.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.inventory_2_outlined, color: corPrimaria),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Busca: ${widget.busca}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${produtos.length} produto(s) inativo(s)',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (carregandoToken)
              const LinearProgressIndicator(minHeight: 3)
            else
              const SizedBox.shrink(),
            const SizedBox(height: 12),
            if (produtos.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black12),
                ),
                child: const Text(
                  'Nenhum produto inativo encontrado.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              ...produtos.map((produto) {
                final id = produtoId(produto);
                final ativando = id.isNotEmpty && ativandoProdutoId == id;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: corPrimaria.withValues(alpha: 0.22),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nomeProduto(produto),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InfoChip(
                            icon: Icons.qr_code_2,
                            label: 'EAN',
                            value: eanProduto(produto),
                            color: corPrimaria,
                          ),
                          _InfoChip(
                            icon: Icons.inventory_outlined,
                            label: 'EST',
                            value: estoqueProduto(produto),
                            color: Colors.teal,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: corPrimaria,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: carregandoToken || ativando
                              ? null
                              : () => ativarProduto(produto),
                          icon: ativando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: Text(ativando ? 'Ativando...' : 'Ativar item'),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

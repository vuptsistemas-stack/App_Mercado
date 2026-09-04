import 'package:flutter/material.dart';

import '../../services/central_service.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/sessao_loja.dart';

class ReceitasProducaoPage extends StatefulWidget {
  const ReceitasProducaoPage({super.key});

  @override
  State<ReceitasProducaoPage> createState() => _ReceitasProducaoPageState();
}

class _ReceitasProducaoPageState extends State<ReceitasProducaoPage> {
  static Color get vermelho => SessaoLoja.corPrimaria;

  bool carregando = true;
  bool mostrarInativas = true;
  Color corPrimaria = vermelho;
  Color corSecundaria = SessaoLoja.corSecundaria;
  Color corFundo = SessaoLoja.corFundo;

  List<Map<String, dynamic>> receitas = [];
  Map<String, Map<String, dynamic>> produtosPorId = {};

  SupabaseClient get supabase {
    return SessaoLoja.supabaseLoja ?? Supabase.instance.client;
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      carregarTudo();
    });
  }

  String texto(dynamic valor) => valor?.toString().trim() ?? '';

  String mensagemErroProducao(Object e) {
    String formatarQtd(double valor) {
      var textoFormatado = valor.toStringAsFixed(3);

      while (textoFormatado.contains('.') && textoFormatado.endsWith('0')) {
        textoFormatado = textoFormatado.substring(0, textoFormatado.length - 1);
      }

      if (textoFormatado.endsWith('.')) {
        textoFormatado = textoFormatado.substring(0, textoFormatado.length - 1);
      }

      return textoFormatado.replaceAll('.', ',');
    }

    final mensagemCentral = CentralService.mensagemErroUsuario(e);
    if (mensagemCentral == CentralService.mensagemSemInternet ||
        mensagemCentral.contains('sessão expirou') ||
        mensagemCentral.contains('não tem permissão')) {
      return mensagemCentral;
    }

    var msg = e.toString();

    msg = msg.replaceFirst('Exception: ', '');
    msg = msg.replaceFirst('PostgrestException(message: ', '');

    final messageMatch = RegExp(
      r'message:\s*([^,]+(?:,[^,]+)*?)(?:,\s*code:|,\s*details:|,\s*hint:|\))',
    ).firstMatch(msg);

    if (messageMatch != null) {
      msg = messageMatch.group(1)?.trim() ?? msg;
    }

    msg = msg
        .replaceAll(RegExp(r',?\s*code:\s*[^,)]*'), '')
        .replaceAll(RegExp(r',?\s*details:\s*[^,)]*'), '')
        .replaceAll(RegExp(r',?\s*hint:\s*[^,)]*'), '')
        .replaceAll('Bad Request', '')
        .replaceAll('null', '')
        .trim();

    final estoqueMatch = RegExp(
      r'Estoque insuficiente para\s+(.+?)\.\s+Estoque atual:\s+([0-9]+(?:\.[0-9]+)?)\s*,\s*necessário:\s+([0-9]+(?:\.[0-9]+)?)',
      caseSensitive: false,
    ).firstMatch(msg);

    if (estoqueMatch != null) {
      final produto = estoqueMatch.group(1)?.trim() ?? 'produto';
      final estoqueAtual = numero(estoqueMatch.group(2));
      final necessario = numero(estoqueMatch.group(3));
      final falta = necessario - estoqueAtual;

      return 'Estoque insuficiente para $produto.\n\n'
          'Disponível: ${estoqueAtual.toStringAsFixed(3).replaceAll('.', ',')}\n'
          'Necessário: ${necessario.toStringAsFixed(3).replaceAll('.', ',')}\n'
          'Faltando: ${falta.toStringAsFixed(3).replaceAll('.', ',')}\n\n'
          'Ajuste a quantidade produzida ou dê entrada no estoque do ingrediente.';
    }

    if (msg.toLowerCase().contains('estoque insuficiente')) {
      return msg;
    }

    return msg;
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

  String quantidade(dynamic valor) {
    final n = numero(valor);

    if (n == n.roundToDouble()) {
      return n.round().toString();
    }

    return n.toStringAsFixed(3).replaceAll('.', ',');
  }

  String moeda(dynamic valor) {
    final n = numero(valor);
    return 'R\$ ${n.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  Color corHexParaColor(dynamic valor, Color fallback) {
    var textoCor = valor?.toString().trim() ?? '';

    if (textoCor.isEmpty) {
      return fallback;
    }

    if (!textoCor.startsWith('#')) {
      textoCor = '#$textoCor';
    }

    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(textoCor)) {
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
      final data = await Supabase.instance.client
          .from('mercados')
          .select('admin_cor_primaria, admin_cor_secundaria, admin_cor_fundo')
          .eq('id', SessaoLoja.mercadoIdObrigatorio)
          .maybeSingle();

      if (!mounted || data == null) return;

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
    } catch (_) {}
  }

  Future<void> carregarTudo() async {
    setState(() {
      carregando = true;
    });

    await carregarTemaDinamico();

    try {
      final produtosResp = await supabase
          .from('produtos_app')
          .select()
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
          .order('nome_produto', ascending: true);

      final produtos = List<Map<String, dynamic>>.from(
        produtosResp.map((item) => Map<String, dynamic>.from(item)),
      );

      produtosPorId = {
        for (final produto in produtos) texto(produto['id']): produto,
      };

      final receitasResp = await supabase
          .from('produto_receitas')
          .select()
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
          .order('criado_em', ascending: false);

      if (!mounted) return;

      setState(() {
        receitas = List<Map<String, dynamic>>.from(
          receitasResp.map((item) => Map<String, dynamic>.from(item)),
        );
      });
    } catch (e) {
      mostrarMensagem(
        'Erro ao carregar receitas: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          carregando = false;
        });
      }
    }
  }

  void mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? Colors.red : Colors.green,
      ),
    );
  }

  String nomeProduto(String? produtoId) {
    if (produtoId == null) return 'Produto não encontrado';

    final produto = produtosPorId[produtoId];

    return texto(produto?['nome_produto']).isEmpty
        ? 'Produto não encontrado'
        : texto(produto?['nome_produto']);
  }

  Future<void> abrirNovaReceita() async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReceitaFormularioPage(
          corPrimaria: corPrimaria,
          corSecundaria: corSecundaria,
          corFundo: corFundo,
        ),
      ),
    );

    if (salvou == true) {
      await carregarTudo();
      mostrarMensagem('Receita cadastrada.');
    }
  }

  Future<void> abrirItensReceita(Map<String, dynamic> receita) async {
    final receitaId = texto(receita['id']);

    try {
      final itensResp = await supabase
          .from('produto_receita_itens')
          .select()
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
          .eq('receita_id', receitaId)
          .order('criado_em', ascending: true);

      final itens = List<Map<String, dynamic>>.from(
        itensResp.map((item) => Map<String, dynamic>.from(item)),
      );

      if (!mounted) return;

      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) {
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Text(
                  texto(receita['nome_receita']),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Produto final: ${nomeProduto(texto(receita['produto_final_id']))}',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Ingredientes',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                if (itens.isEmpty)
                  const Text('Nenhum ingrediente cadastrado.')
                else
                  ...itens.map((item) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: corPrimaria.withValues(alpha: 0.10),
                        child: Icon(Icons.restaurant, color: corPrimaria),
                      ),
                      title: Text(
                        nomeProduto(texto(item['produto_insumo_id'])),
                      ),
                      subtitle: Text(
                        '${quantidade(item['quantidade'])} ${texto(item['unidade']).isEmpty ? 'UN' : texto(item['unidade'])}',
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      );
    } catch (e) {
      mostrarMensagem(
        'Erro ao abrir receita: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    }
  }

  Future<bool> confirmarExcluirHistoricoProducao(String nomeReceita) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Excluir histórico da produção?'),
          content: Text(
            'A receita "$nomeReceita" já tem produção registrada.\n\n'
            'Para excluir a receita, será necessário apagar também:\n'
            '- movimentações de estoque dessa produção\n'
            '- histórico de produção\n'
            '- ingredientes da receita\n'
            '- ficha técnica\n\n'
            'Atenção: essa ação NÃO recalcula automaticamente o estoque atual. '
            'Use apenas para limpar testes ou cadastros criados por engano.',
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
              child: const Text('Excluir tudo'),
            ),
          ],
        );
      },
    );

    return confirmar == true;
  }

  Future<void> excluirReceitaComHistorico({
    required String receitaId,
    required String nomeReceita,
  }) async {
    final confirmar = await confirmarExcluirHistoricoProducao(nomeReceita);

    if (!confirmar) return;

    try {
      final mercadoId = SessaoLoja.mercadoIdObrigatorio;

      final producoesResp = await supabase
          .from('produto_producoes')
          .select('id')
          .eq('mercado_id', mercadoId)
          .eq('receita_id', receitaId);

      final producoes = List<Map<String, dynamic>>.from(
        producoesResp.map((item) => Map<String, dynamic>.from(item)),
      );

      final producaoIds = producoes
          .map((producao) => texto(producao['id']))
          .where((id) => id.isNotEmpty)
          .toList();

      if (producaoIds.isNotEmpty) {
        await supabase
            .from('produto_movimentacoes_app')
            .delete()
            .eq('mercado_id', mercadoId)
            .inFilter('producao_id', producaoIds);
      }

      await supabase
          .from('produto_producoes')
          .delete()
          .eq('mercado_id', mercadoId)
          .eq('receita_id', receitaId);

      await supabase
          .from('produto_receita_itens')
          .delete()
          .eq('mercado_id', mercadoId)
          .eq('receita_id', receitaId);

      await supabase
          .from('produto_receitas')
          .delete()
          .eq('mercado_id', mercadoId)
          .eq('id', receitaId);

      await carregarTudo();

      mostrarMensagem(
        'Receita, ingredientes e histórico de produção excluídos.',
      );
    } catch (e) {
      mostrarMensagem(
        'Erro ao excluir histórico e receita: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    }
  }

  Future<void> excluirReceita(Map<String, dynamic> receita) async {
    final receitaId = texto(receita['id']);
    final nomeReceita = texto(receita['nome_receita']);

    if (receitaId.isEmpty) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Excluir receita'),
          content: Text(
            'Deseja excluir definitivamente "$nomeReceita"?\n\n'
            'Isso remove a ficha técnica e os ingredientes vinculados a ela.\n\n'
            'Se a receita já tiver produção registrada, o sistema vai perguntar se você também deseja excluir o histórico da produção.',
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
              child: const Text('Excluir definitivamente'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    try {
      // Primeiro remove os itens/ingredientes da receita.
      // Assim libera produtos que estavam vinculados como insumo.
      await supabase
          .from('produto_receita_itens')
          .delete()
          .eq('receita_id', receitaId)
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);

      // Depois remove a receita.
      await supabase
          .from('produto_receitas')
          .delete()
          .eq('id', receitaId)
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);

      await carregarTudo();

      mostrarMensagem('Receita excluída definitivamente.');
    } catch (e) {
      final mensagem = e.toString().toLowerCase();

      if (mensagem.contains('foreign key') ||
          mensagem.contains('23503') ||
          mensagem.contains('produto_producoes_receita_id_fkey')) {
        await excluirReceitaComHistorico(
          receitaId: receitaId,
          nomeReceita: nomeReceita,
        );
        return;
      }

      mostrarMensagem(
        'Erro ao excluir receita: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    }
  }

  Future<void> produzirReceita(Map<String, dynamic> receita) async {
    final quantidadeController = TextEditingController(text: '1');

    final quantidadeProduzir = await showDialog<double>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Produzir receita'),
          content: TextField(
            controller: quantidadeController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Quantidade a produzir',
              hintText: 'Ex: 10',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: corPrimaria,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context, numero(quantidadeController.text));
              },
              child: const Text('Produzir'),
            ),
          ],
        );
      },
    );

    // Não damos dispose aqui porque o AlertDialog/TextField ainda pode estar
    // finalizando a animação/rebuild quando o Navigator.pop retorna.
    // Dar dispose nesse momento pode gerar:
    // "A TextEditingController was used after being disposed."
    if (quantidadeProduzir == null || quantidadeProduzir <= 0) {
      return;
    }

    await _executarBaixaReceita(
      receita: receita,
      quantidadeProduzir: quantidadeProduzir,
    );
  }

  Future<Map<String, dynamic>> buscarProdutoEstoqueObrigatorio({
    required String produtoId,
    required String descricaoErro,
  }) async {
    final resposta = await supabase
        .from('produtos_app')
        .select('id, nome_produto, estoque, controla_estoque')
        .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
        .eq('id', produtoId)
        .limit(1);

    final lista = List<Map<String, dynamic>>.from(
      resposta.map((item) => Map<String, dynamic>.from(item)),
    );

    if (lista.isEmpty) {
      throw Exception('$descricaoErro não encontrado no estoque da loja.');
    }

    return lista.first;
  }

  Future<void> atualizarEstoqueProdutoObrigatorio({
    required String produtoId,
    required double novoEstoque,
    required String agora,
    required String descricaoErro,
  }) async {
    final resposta = await supabase
        .from('produtos_app')
        .update({'estoque': novoEstoque, 'atualizado_em': agora})
        .eq('id', produtoId)
        .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
        .select('id');

    final lista = List<Map<String, dynamic>>.from(
      resposta.map((item) => Map<String, dynamic>.from(item)),
    );

    if (lista.isEmpty) {
      throw Exception(
        'Não foi possível atualizar o estoque de $descricaoErro. '
        'O update retornou 0 linhas. Confira RLS/permissão e se o produto pertence à loja atual.',
      );
    }
  }

  Future<void> inserirMovimentacaoEstoque({
    required String produtoId,
    required String producaoId,
    required String tipo,
    required double quantidade,
    required double estoqueAnterior,
    required double estoqueNovo,
    required String observacao,
  }) async {
    await supabase.from('produto_movimentacoes_app').insert({
      ...SessaoLoja.dadosMercadoRegistro,
      'produto_id': produtoId,
      'producao_id': producaoId,
      'tipo': tipo,
      'quantidade': quantidade,
      'estoque_anterior': estoqueAnterior,
      'estoque_novo': estoqueNovo,
      'observacao': observacao,
    });
  }

  Future<void> _executarBaixaReceita({
    required Map<String, dynamic> receita,
    required double quantidadeProduzir,
  }) async {
    final receitaId = texto(receita['id']);

    if (receitaId.isEmpty) {
      mostrarMensagem('Receita inválida. Receita sem ID.', erro: true);
      return;
    }

    setState(() {
      carregando = true;
    });

    try {
      await supabase.rpc(
        'registrar_producao_receita_app',
        params: {
          'p_mercado_id': SessaoLoja.mercadoIdObrigatorio,
          'p_receita_id': receitaId,
          'p_quantidade_produzir': quantidadeProduzir,
        },
      );

      await carregarTudo();

      mostrarMensagem(
        'Produção concluída. Produto produzido aumentou e insumos foram baixados.',
      );
    } catch (e) {
      mostrarMensagem(mensagemErroProducao(e), erro: true);
    } finally {
      if (mounted) {
        setState(() {
          carregando = false;
        });
      }
    }
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
            color: corPrimaria.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 9),
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
            child: Icon(Icons.receipt_long, color: corPrimaria, size: 34),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Receitas e produção',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 23,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Crie ficha técnica e produza baixando ingredientes automaticamente.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget cardReceita(Map<String, dynamic> receita) {
    final produtoFinalId = texto(receita['produto_final_id']);
    final produtoFinal = produtosPorId[produtoFinalId];
    final ativo = receita['ativo'] != false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ativo ? Colors.white : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ativo
              ? Colors.black.withValues(alpha: 0.07)
              : Colors.orange.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: corPrimaria.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.bakery_dining, color: corPrimaria, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => abrirItensReceita(receita),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          texto(receita['nome_receita']),
                          style: const TextStyle(
                            color: Color(0xFF1F2937),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (!ativo)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Inativa',
                            style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Produto final: ${texto(produtoFinal?['nome_produto'])}',
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rendimento base: ${quantidade(receita['rendimento'])} ${texto(receita['unidade_rendimento']).isEmpty ? 'UN' : texto(receita['unidade_rendimento'])}',
                    style: const TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              ElevatedButton.icon(
                onPressed: carregando || !ativo
                    ? null
                    : () => produzirReceita(receita),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Produzir'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: corPrimaria,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (valor) {
                  if (valor == 'ver') {
                    abrirItensReceita(receita);
                  } else if (valor == 'excluir') {
                    excluirReceita(receita);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'ver',
                    child: Row(
                      children: [
                        Icon(Icons.visibility_outlined),
                        SizedBox(width: 8),
                        Text('Ver ingredientes'),
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

  Widget corpo() {
    if (carregando) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(42),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final receitasVisiveis = mostrarInativas
        ? receitas
        : receitas.where((receita) => receita['ativo'] != false).toList();

    if (receitasVisiveis.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
        ),
        child: const Column(
          children: [
            Icon(Icons.receipt_long_outlined, color: Colors.black38, size: 48),
            SizedBox(height: 10),
            Text(
              'Nenhuma receita cadastrada',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 4),
            Text(
              'Cadastre uma ficha técnica para produzir e baixar o estoque dos insumos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      );
    }

    return Column(children: receitasVisiveis.map(cardReceita).toList());
  }

  Widget filtroReceitas() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.only(left: 14, right: 6, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined, color: corPrimaria),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Mostrar receitas inativas',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Switch(
            value: mostrarInativas,
            activeThumbColor: corPrimaria,
            onChanged: (valor) {
              setState(() {
                mostrarInativas = valor;
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: corFundo,
      appBar: AppBar(
        title: const Text('Receitas e produção'),
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: carregando ? null : carregarTudo,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
        onPressed: carregando ? null : abrirNovaReceita,
        icon: const Icon(Icons.add),
        label: const Text('Nova receita'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: carregarTudo,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              topo(),
              const SizedBox(height: 18),
              filtroReceitas(),
              corpo(),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}

class ReceitaIngredienteForm {
  String? produtoId;
  final quantidadeController = TextEditingController(text: '1');
  final unidadeController = TextEditingController(text: 'UN');

  void dispose() {
    quantidadeController.dispose();
    unidadeController.dispose();
  }
}

class ReceitaFormularioPage extends StatefulWidget {
  final Color corPrimaria;
  final Color corSecundaria;
  final Color corFundo;

  const ReceitaFormularioPage({
    super.key,
    required this.corPrimaria,
    required this.corSecundaria,
    required this.corFundo,
  });

  @override
  State<ReceitaFormularioPage> createState() => _ReceitaFormularioPageState();
}

class _ReceitaFormularioPageState extends State<ReceitaFormularioPage> {
  final nomeReceitaController = TextEditingController();
  final rendimentoController = TextEditingController(text: '1');
  final unidadeRendimentoController = TextEditingController(text: 'UN');

  bool carregando = true;
  bool salvando = false;

  String? produtoFinalId;
  List<Map<String, dynamic>> produtos = [];
  List<ReceitaIngredienteForm> ingredientes = [ReceitaIngredienteForm()];

  SupabaseClient get supabase {
    return SessaoLoja.supabaseLoja ?? Supabase.instance.client;
  }

  Color get corPrimaria => widget.corPrimaria;
  Color get corSecundaria => widget.corSecundaria;
  Color get corFundo => widget.corFundo;

  @override
  void initState() {
    super.initState();
    carregarProdutos();
  }

  @override
  void dispose() {
    nomeReceitaController.dispose();
    rendimentoController.dispose();
    unidadeRendimentoController.dispose();

    for (final ingrediente in ingredientes) {
      ingrediente.dispose();
    }

    super.dispose();
  }

  String texto(dynamic valor) => valor?.toString().trim() ?? '';

  String mensagemErroProducao(Object e) {
    final mensagemCentral = CentralService.mensagemErroUsuario(e);
    if (mensagemCentral == CentralService.mensagemSemInternet ||
        mensagemCentral.contains('sessão expirou') ||
        mensagemCentral.contains('não tem permissão')) {
      return mensagemCentral;
    }

    var msg = e.toString();

    msg = msg.replaceFirst('Exception: ', '');
    msg = msg.replaceFirst('PostgrestException(message: ', '');

    final messageMatch = RegExp(
      r'message:\s*([^,]+(?:,[^,]+)*?)(?:,\s*code:|,\s*details:|,\s*hint:|\))',
    ).firstMatch(msg);

    if (messageMatch != null) {
      msg = messageMatch.group(1)?.trim() ?? msg;
    }

    msg = msg
        .replaceAll(RegExp(r',?\s*code:\s*[^,)]*'), '')
        .replaceAll(RegExp(r',?\s*details:\s*[^,)]*'), '')
        .replaceAll(RegExp(r',?\s*hint:\s*[^,)]*'), '')
        .replaceAll('Bad Request', '')
        .replaceAll('null', '')
        .trim();

    final estoqueMatch = RegExp(
      r'Estoque insuficiente para\s+(.+?)\.\s+Estoque atual:\s+([0-9]+(?:\.[0-9]+)?)\s*,\s*necessário:\s+([0-9]+(?:\.[0-9]+)?)',
      caseSensitive: false,
    ).firstMatch(msg);

    if (estoqueMatch != null) {
      final produto = estoqueMatch.group(1)?.trim() ?? 'produto';
      final estoqueAtual = numero(estoqueMatch.group(2));
      final necessario = numero(estoqueMatch.group(3));
      final falta = necessario - estoqueAtual;

      return 'Estoque insuficiente para $produto.\n\n'
          'Disponível: ${estoqueAtual.toStringAsFixed(3).replaceAll('.', ',')}\n'
          'Necessário: ${necessario.toStringAsFixed(3).replaceAll('.', ',')}\n'
          'Faltando: ${falta.toStringAsFixed(3).replaceAll('.', ',')}\n\n'
          'Ajuste a quantidade produzida ou dê entrada no estoque do ingrediente.';
    }

    if (msg.toLowerCase().contains('estoque insuficiente')) {
      return msg;
    }

    return msg;
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

  bool ehProdutoFinal(Map<String, dynamic> produto) {
    final tipo = texto(produto['tipo_produto']).toUpperCase();

    return produto['produto_produzido'] == true ||
        tipo == 'PRODUZIDO' ||
        tipo == 'VENDA' ||
        tipo == 'VENDA_E_INSUMO';
  }

  bool ehInsumo(Map<String, dynamic> produto) {
    final tipo = texto(produto['tipo_produto']).toUpperCase();

    return produto['consumo_producao'] == true ||
        tipo == 'INSUMO' ||
        tipo == 'VENDA_E_INSUMO';
  }

  List<Map<String, dynamic>> get produtosFinais {
    final lista = produtos.where(ehProdutoFinal).toList();

    if (lista.isNotEmpty) {
      return lista;
    }

    return produtos;
  }

  List<Map<String, dynamic>> get produtosInsumos {
    final lista = produtos.where(ehInsumo).toList();

    if (lista.isNotEmpty) {
      return lista;
    }

    return produtos;
  }

  Future<void> carregarProdutos() async {
    setState(() {
      carregando = true;
    });

    try {
      final resposta = await supabase
          .from('produtos_app')
          .select()
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
          .eq('ativo', true)
          .order('nome_produto', ascending: true);

      if (!mounted) return;

      setState(() {
        produtos = List<Map<String, dynamic>>.from(
          resposta.map((item) => Map<String, dynamic>.from(item)),
        );

        if (produtoFinalId == null && produtosFinais.isNotEmpty) {
          produtoFinalId = texto(produtosFinais.first['id']);
        }

        for (final ingrediente in ingredientes) {
          ingrediente.produtoId ??= produtosInsumos.isNotEmpty
              ? texto(produtosInsumos.first['id'])
              : null;
        }
      });
    } catch (e) {
      mostrarErro(
        'Erro ao carregar produtos: ${CentralService.mensagemErroUsuario(e)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          carregando = false;
        });
      }
    }
  }

  void mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: Colors.red),
    );
  }

  void adicionarIngrediente() {
    setState(() {
      final item = ReceitaIngredienteForm();

      item.produtoId = produtosInsumos.isNotEmpty
          ? texto(produtosInsumos.first['id'])
          : null;

      ingredientes.add(item);
    });
  }

  void removerIngrediente(int index) {
    if (ingredientes.length <= 1) {
      mostrarErro('A receita precisa ter pelo menos um ingrediente.');
      return;
    }

    setState(() {
      final item = ingredientes.removeAt(index);
      item.dispose();
    });
  }

  Future<void> salvar() async {
    final nomeReceita = nomeReceitaController.text.trim();
    final rendimento = numero(rendimentoController.text);
    final unidadeRendimento = unidadeRendimentoController.text
        .trim()
        .toUpperCase();

    if (produtoFinalId == null || produtoFinalId!.isEmpty) {
      mostrarErro('Selecione o produto final produzido.');
      return;
    }

    if (nomeReceita.isEmpty) {
      mostrarErro('Informe o nome da receita.');
      return;
    }

    if (rendimento <= 0) {
      mostrarErro('Informe o rendimento da receita.');
      return;
    }

    final itensValidos = ingredientes.where((item) {
      final produtoId = item.produtoId?.trim() ?? '';
      final quantidade = numero(item.quantidadeController.text);

      return produtoId.isNotEmpty && quantidade > 0;
    }).toList();

    if (itensValidos.isEmpty) {
      mostrarErro('Informe pelo menos um ingrediente com quantidade.');
      return;
    }

    setState(() {
      salvando = true;
    });

    try {
      final receitaInserida = await supabase
          .from('produto_receitas')
          .insert({
            ...SessaoLoja.dadosMercadoRegistro,
            'produto_final_id': produtoFinalId,
            'nome_receita': nomeReceita,
            'rendimento': rendimento,
            'unidade_rendimento': unidadeRendimento.isEmpty
                ? 'UN'
                : unidadeRendimento,
            'ativo': true,
          })
          .select('id')
          .single();

      final receitaId = texto(receitaInserida['id']);

      final itens = itensValidos.map((item) {
        final unidade = item.unidadeController.text.trim().toUpperCase();

        return {
          ...SessaoLoja.dadosMercadoRegistro,
          'receita_id': receitaId,
          'produto_insumo_id': item.produtoId,
          'quantidade': numero(item.quantidadeController.text),
          'unidade': unidade.isEmpty ? 'UN' : unidade,
        };
      }).toList();

      await supabase.from('produto_receita_itens').insert(itens);

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      mostrarErro(
        'Erro ao salvar receita: ${CentralService.mensagemErroUsuario(e)}',
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
    bool decimal = false,
  }) {
    return TextField(
      controller: controller,
      enabled: !salvando,
      keyboardType: decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: [
        if (decimal) FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: corPrimaria),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: corPrimaria, width: 1.8),
        ),
      ),
    );
  }

  Widget dropdownProduto({
    required String? value,
    required String label,
    required List<Map<String, dynamic>> lista,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(Icons.shopping_basket, color: corPrimaria),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      ),
      items: lista.map((produto) {
        return DropdownMenuItem<String>(
          value: texto(produto['id']),
          child: Text(
            texto(produto['nome_produto']),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: salvando ? null : onChanged,
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

  Widget cardIngrediente(int index) {
    final ingrediente = ingredientes[index];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: dropdownProduto(
                  value: ingrediente.produtoId,
                  label: 'Ingrediente',
                  lista: produtosInsumos,
                  onChanged: (valor) {
                    setState(() {
                      ingrediente.produtoId = valor;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: salvando ? null : () => removerIngrediente(index),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: campo(
                  controller: ingrediente.quantidadeController,
                  label: 'Quantidade',
                  icon: Icons.scale,
                  decimal: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: campo(
                  controller: ingrediente.unidadeController,
                  label: 'Unidade',
                  icon: Icons.straighten,
                ),
              ),
            ],
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
            color: corPrimaria.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.receipt_long, color: Colors.white, size: 42),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nova receita',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 23,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Monte a ficha técnica do produto produzido.',
                  style: TextStyle(color: Colors.white70),
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
            label: Text(salvando ? 'Salvando...' : 'Salvar receita'),
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
        title: const Text('Nova receita'),
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  topo(),
                  const SizedBox(height: 18),
                  cardSecao(
                    titulo: 'Produto final',
                    subtitulo:
                        'Produto que será produzido e entrará no estoque.',
                    icone: Icons.bakery_dining,
                    children: [
                      dropdownProduto(
                        value: produtoFinalId,
                        label: 'Produto final produzido',
                        lista: produtosFinais,
                        onChanged: (valor) {
                          setState(() {
                            produtoFinalId = valor;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      campo(
                        controller: nomeReceitaController,
                        label: 'Nome da receita',
                        icon: Icons.receipt_long,
                      ),
                      const SizedBox(height: 12),
                      if (duasColunas)
                        Row(
                          children: [
                            Expanded(
                              child: campo(
                                controller: rendimentoController,
                                label: 'Rendimento base',
                                icon: Icons.production_quantity_limits,
                                decimal: true,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: campo(
                                controller: unidadeRendimentoController,
                                label: 'Unidade rendimento',
                                icon: Icons.straighten,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        campo(
                          controller: rendimentoController,
                          label: 'Rendimento base',
                          icon: Icons.production_quantity_limits,
                          decimal: true,
                        ),
                        const SizedBox(height: 12),
                        campo(
                          controller: unidadeRendimentoController,
                          label: 'Unidade rendimento',
                          icon: Icons.straighten,
                        ),
                      ],
                    ],
                  ),
                  cardSecao(
                    titulo: 'Ingredientes',
                    subtitulo:
                        'Itens que serão baixados do estoque quando produzir.',
                    icone: Icons.restaurant,
                    children: [
                      ...List.generate(ingredientes.length, cardIngrediente),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        onPressed: salvando ? null : adicionarIngrediente,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar ingrediente'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: corPrimaria,
                          side: BorderSide(color: corPrimaria),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ],
                  ),
                  botoesRodape(),
                  const SizedBox(height: 28),
                ],
              ),
            ),
    );
  }
}

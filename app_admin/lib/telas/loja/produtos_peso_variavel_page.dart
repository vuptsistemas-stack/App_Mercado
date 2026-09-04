import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/central_service.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/sessao_loja.dart';

class ProdutosPesoVariavelPage extends StatefulWidget {
  const ProdutosPesoVariavelPage({super.key});

  @override
  State<ProdutosPesoVariavelPage> createState() =>
      _ProdutosPesoVariavelPageState();
}

class _ProdutosPesoVariavelPageState extends State<ProdutosPesoVariavelPage> {
  static Color get vermelho => SessaoLoja.corPrimaria;
  static const Color verde = Color(0xFF16A34A);
  static Color get fundo => SessaoLoja.corFundo;
  static const Color textoForte = Color(0xFF111827);
  static const Color textoFraco = Color(0xFF6B7280);

  final TextEditingController buscaController = TextEditingController();
  final Map<String, bool> pesoVariavelPorEan = {};
  final Map<String, TextEditingController> pesoMedioControllers = {};

  Timer? debounce;

  bool carregandoBusca = false;
  bool carregandoMarcados = true;
  bool salvando = false;

  List<Map<String, dynamic>> produtosBusca = [];
  List<Map<String, dynamic>> produtosMarcados = [];

  String? get apiBaseUrl {
    final url = SessaoLoja.apiBaseUrl?.trim();

    if (url == null || url.isEmpty) return null;
    if (url.endsWith('/')) return url.substring(0, url.length - 1);

    return url;
  }

  SupabaseClient get supabaseLoja {
    final clienteLoja = SessaoLoja.supabaseLoja;

    if (clienteLoja != null) {
      return clienteLoja;
    }

    return Supabase.instance.client;
  }

  bool get exibindoBusca => buscaController.text.trim().length >= 3;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        carregarProdutosMarcados();
      }
    });
  }

  @override
  void dispose() {
    debounce?.cancel();
    buscaController.dispose();

    for (final controller in pesoMedioControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  void mostrarMensagem({required String texto, Color? cor}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: cor ?? vermelho,
        behavior: SnackBarBehavior.floating,
        content: Text(texto),
      ),
    );
  }

  List extrairLista(dynamic data) {
    if (data is List) return data;

    if (data is Map && data['produtos'] is List) return data['produtos'];
    if (data is Map && data['data'] is List) return data['data'];
    if (data is Map && data['resultado'] is List) return data['resultado'];
    if (data is Map && data['results'] is List) return data['results'];

    // Quando a API retorna apenas um produto direto em JSON:
    // { produto_id, nome_produto, ean_principal, unidade_medida, ... }
    if (data is Map &&
        (data['nome_produto'] != null ||
            data['descricao'] != null ||
            data['ean_principal'] != null ||
            data['ean'] != null)) {
      return [data];
    }

    return [];
  }

  String textoCampo(Map<String, dynamic> produto, List<String> campos) {
    for (final campo in campos) {
      final valor = produto[campo];

      if (valor != null && valor.toString().trim().isNotEmpty) {
        return valor.toString().trim();
      }
    }

    return '';
  }

  String nomeProduto(Map<String, dynamic> produto) {
    final nome = textoCampo(produto, [
      'nome_produto',
      'descricao',
      'produto',
      'nome',
    ]);

    return nome.isEmpty ? 'Produto sem descrição' : nome;
  }

  String normalizarEan(String valor) {
    final texto = valor.trim();
    final numeros = texto.replaceAll(RegExp(r'[^0-9]'), '');

    if (numeros.isEmpty) return texto;
    if (numeros.length < 14) return numeros.padLeft(14, '0');

    return numeros;
  }

  String eanSemZerosAEsquerda(String ean) {
    final numeros = ean.replaceAll(RegExp(r'[^0-9]'), '');
    final semZeros = numeros.replaceFirst(RegExp(r'^0+'), '');
    return semZeros.isEmpty ? numeros : semZeros;
  }

  Set<String> candidatosEan(String ean) {
    final normalizado = normalizarEan(ean);
    final semZeros = eanSemZerosAEsquerda(normalizado);

    return {
      ean.trim(),
      normalizado,
      semZeros,
    }.where((item) => item.trim().isNotEmpty).toSet();
  }

  String eanProduto(Map<String, dynamic> produto) {
    final ean = textoCampo(produto, [
      'ean_principal',
      'ean',
      'codigo_barras',
      'codigo_barra',
      'cod_barras',
    ]);

    return normalizarEan(ean);
  }

  String normalizarUnidade(String valor) {
    return valor
        .toUpperCase()
        .replaceAll('Á', 'A')
        .replaceAll('À', 'A')
        .replaceAll('Â', 'A')
        .replaceAll('Ã', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Ê', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ô', 'O')
        .replaceAll('Õ', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll(RegExp(r'[^A-Z0-9]'), '')
        .trim();
  }

  String unidadeProduto(Map<String, dynamic> produto) {
    final direto = textoCampo(produto, [
      'unidade_medida',
      'unidadeMedida',
      'unidade_medida_sigla',
      'unidadeMedidaSigla',
      'unidade_venda',
      'unidadeVenda',
      'unidade',
      'sigla_unidade',
      'siglaUnidade',
      'unidade_sigla',
      'unidadeSigla',
      'sigla_saida',
      'siglaSaida',
      'sigla',
      'und',
      'un',
      'um',
      'UN',
      'UM',
    ]);

    if (direto.isNotEmpty) {
      return normalizarUnidade(direto);
    }

    // Algumas APIs retornam nomes diferentes para unidade.
    // Aqui procuramos qualquer campo que tenha "unidade", "sigla" ou "medida".
    for (final entry in produto.entries) {
      final chave = entry.key.toString().toLowerCase();
      final valor = entry.value?.toString().trim() ?? '';

      if (valor.isEmpty) continue;

      final pareceCampoUnidade =
          chave.contains('unidade') ||
          chave.contains('medida') ||
          chave == 'sigla' ||
          chave == 'und' ||
          chave == 'un' ||
          chave == 'um';

      if (pareceCampoUnidade) {
        return normalizarUnidade(valor);
      }
    }

    return '';
  }

  int? produtoId(Map<String, dynamic> produto) {
    final valor =
        produto['produto_id'] ??
        produto['id_produto'] ??
        produto['id'] ??
        produto['codigo'];

    if (valor == null) return null;

    return int.tryParse(valor.toString());
  }

  double precoProduto(Map<String, dynamic> produto) {
    final valor =
        produto['preco_venda'] ??
        produto['preco'] ??
        produto['valor'] ??
        produto['preco_unitario'];

    if (valor == null) return 0;

    return double.tryParse(valor.toString().replaceAll(',', '.').trim()) ?? 0;
  }

  String formatarMoeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String formatarPeso(dynamic valor) {
    if (valor == null) return '';

    final numero = double.tryParse(valor.toString().replaceAll(',', '.'));

    if (numero == null) return valor.toString();

    return numero.toStringAsFixed(3).replaceAll('.', ',');
  }

  bool produtoKg(Map<String, dynamic> produto) {
    final unidade = unidadeProduto(produto);

    return unidade == 'KG' ||
        unidade == 'KGS' ||
        unidade == 'KILO' ||
        unidade == 'KILOS' ||
        unidade == 'QUILO' ||
        unidade == 'QUILOS' ||
        unidade == 'KILOGRAMA' ||
        unidade == 'KILOGRAMAS';
  }

  bool produtoVeioDaConfiguracao(Map<String, dynamic> produto) {
    return produto['origem_configuracao_salva'] == true;
  }

  bool somenteNumeros(String texto) {
    return RegExp(r'^[0-9]+$').hasMatch(texto);
  }

  void prepararController(String ean, {String? pesoMedio}) {
    pesoMedioControllers.putIfAbsent(ean, () => TextEditingController());

    if (pesoMedio != null && pesoMedioControllers[ean]!.text.trim().isEmpty) {
      pesoMedioControllers[ean]!.text = pesoMedio;
    }
  }

  void aplicarConfiguracaoNoEstado({
    required String ean,
    required dynamic pesoVariavel,
    required dynamic pesoMedio,
  }) {
    final ativo = pesoVariavel == true;

    pesoVariavelPorEan[ean] = ativo;
    prepararController(ean);

    if (ativo) {
      pesoMedioControllers[ean]!.text = formatarPeso(pesoMedio);
    } else {
      pesoMedioControllers[ean]!.text = '';
    }
  }

  Future<Map<String, dynamic>?> buscarConfiguracaoPorEan(String ean) async {
    for (final candidato in candidatosEan(ean)) {
      try {
        final config = await supabaseLoja
            .from('produto_configuracoes_app')
            .select(
              'id, produto_id, ean, nome_produto, peso_variavel, peso_medio_kg, ativo, atualizado_em',
            )
            .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
            .eq('ean', candidato)
            .limit(1)
            .maybeSingle();

        if (config != null) {
          return Map<String, dynamic>.from(config);
        }
      } catch (_) {
        // Tenta o próximo formato de EAN, caso exista diferença entre API e tabela.
      }
    }

    return null;
  }

  Future<void> carregarProdutosMarcados({bool mostrarErro = true}) async {
    if (!mounted) return;

    setState(() => carregandoMarcados = true);

    try {
      final resposta = await supabaseLoja
          .from('produto_configuracoes_app')
          .select(
            'id, produto_id, ean, nome_produto, peso_variavel, peso_medio_kg, ativo, atualizado_em',
          )
          .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio)
          .eq('peso_variavel', true)
          .order('nome_produto', ascending: true);

      final lista = (resposta as List)
          .whereType<Map>()
          .where((item) => item['ativo'] != false)
          .map((item) {
            final ean = normalizarEan(item['ean']?.toString() ?? '');
            final pesoMedio = formatarPeso(item['peso_medio_kg']);

            aplicarConfiguracaoNoEstado(
              ean: ean,
              pesoVariavel: true,
              pesoMedio: item['peso_medio_kg'],
            );

            return <String, dynamic>{
              'id': item['id'],
              'produto_id': item['produto_id'],
              'ean': ean,
              'nome_produto': item['nome_produto'] ?? 'Produto sem descrição',
              'peso_variavel': true,
              'peso_medio_kg': item['peso_medio_kg'],
              'unidade_medida': 'KG',
              'origem_configuracao_salva': true,
              'peso_medio_formatado': pesoMedio,
            };
          })
          .toList();

      if (!mounted) return;

      setState(() => produtosMarcados = lista);
    } catch (e) {
      if (mostrarErro) {
        mostrarMensagem(
          texto:
              'Erro ao carregar produtos marcados: ${CentralService.mensagemErroUsuario(e)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => carregandoMarcados = false);
      }
    }
  }

  void aoDigitar(String texto) {
    debounce?.cancel();

    debounce = Timer(const Duration(milliseconds: 450), () {
      final busca = texto.trim();

      if (busca.length < 3) {
        setState(() => produtosBusca = []);
        return;
      }

      buscarProdutos(busca);
    });
  }

  Future<void> buscarProdutos(String busca) async {
    final baseUrl = apiBaseUrl;

    if (baseUrl == null) {
      mostrarMensagem(texto: 'Nenhuma API configurada para esta loja.');
      return;
    }

    setState(() {
      carregandoBusca = true;
      produtosBusca = [];
    });

    try {
      late final Uri url;

      if (somenteNumeros(busca)) {
        final codigo = normalizarEan(busca);
        url = Uri.parse('$baseUrl/produto/ean/$codigo');
      } else {
        final descricao = Uri.encodeComponent(busca);
        url = Uri.parse('$baseUrl/produto/descricao/$descricao');
      }

      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('Erro HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final listaApi = extrairLista(data)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => eanProduto(item).isNotEmpty)
          .toList();

      await carregarConfiguracoes(listaApi);

      if (!mounted) return;

      setState(() => produtosBusca = listaApi);
    } catch (e) {
      mostrarMensagem(
        texto:
            'Erro ao buscar produtos: ${CentralService.mensagemErroUsuario(e)}',
      );
    } finally {
      if (mounted) {
        setState(() => carregandoBusca = false);
      }
    }
  }

  Future<void> carregarConfiguracoes(List<Map<String, dynamic>> lista) async {
    for (final produto in lista) {
      final ean = eanProduto(produto);

      if (ean.isEmpty) continue;

      prepararController(ean);

      try {
        final config = await buscarConfiguracaoPorEan(ean);

        if (config == null) {
          pesoVariavelPorEan[ean] = false;
          pesoMedioControllers[ean]!.text = '';
          continue;
        }

        aplicarConfiguracaoNoEstado(
          ean: ean,
          pesoVariavel: config['peso_variavel'],
          pesoMedio: config['peso_medio_kg'],
        );
      } catch (_) {
        pesoVariavelPorEan[ean] = false;
      }
    }
  }

  double? lerPesoMedioKg(String ean) {
    final texto = pesoMedioControllers[ean]?.text ?? '';

    if (texto.trim().isEmpty) return null;

    return double.tryParse(
      texto.replaceAll('.', '').replaceAll(',', '.').trim(),
    );
  }

  Future<void> salvarProduto(Map<String, dynamic> produto) async {
    final ean = eanProduto(produto);

    if (ean.isEmpty) {
      mostrarMensagem(
        texto: 'Produto sem EAN. Não é possível salvar.',
        cor: Colors.orange.shade700,
      );
      return;
    }

    final pesoVariavel = pesoVariavelPorEan[ean] == true;
    final pesoMedio = lerPesoMedioKg(ean);

    if (pesoVariavel && (pesoMedio == null || pesoMedio <= 0)) {
      mostrarMensagem(
        texto: 'Informe o peso médio em KG. Exemplo: 2,000',
        cor: Colors.orange.shade700,
      );
      return;
    }

    setState(() => salvando = true);

    try {
      final existente = await buscarConfiguracaoPorEan(ean);

      final dados = {
        'produto_id': produtoId(produto),
        'ean': ean,
        'nome_produto': nomeProduto(produto),
        'peso_variavel': pesoVariavel,
        'peso_medio_kg': pesoVariavel ? pesoMedio : null,
        'ativo': true,
        'atualizado_em': DateTime.now().toIso8601String(),
      };

      if (existente == null) {
        await supabaseLoja
            .from('produto_configuracoes_app')
            .insert(SessaoLoja.dadosComMercado(dados));
      } else {
        await supabaseLoja
            .from('produto_configuracoes_app')
            .update(dados)
            .eq('id', existente['id'])
            .eq('mercado_id', SessaoLoja.mercadoIdObrigatorio);
      }

      await carregarProdutosMarcados(mostrarErro: false);

      if (!mounted) return;

      mostrarMensagem(
        texto: pesoVariavel
            ? 'Produto marcado como peso variável.'
            : 'Produto removido de peso variável.',
        cor: verde,
      );
    } catch (e) {
      mostrarMensagem(
        texto:
            'Erro ao salvar configuração: ${CentralService.mensagemErroUsuario(e)}',
      );
    } finally {
      if (mounted) {
        setState(() => salvando = false);
      }
    }
  }

  void limparBusca() {
    debounce?.cancel();
    buscaController.clear();

    setState(() => produtosBusca = []);
  }

  Widget chipInfo({
    Key? key,
    required IconData icon,
    required String texto,
    Color cor = textoFraco,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cor.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: cor),
          const SizedBox(width: 6),
          Text(
            texto,
            style: TextStyle(
              color: cor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget resumoTopo() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [SessaoLoja.corPrimaria, SessaoLoja.corSecundaria],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: vermelho.withOpacity(0.24),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.scale_outlined,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Peso variável',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${produtosMarcados.length} produto(s) marcado(s). Busque para adicionar novos itens.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                    height: 1.25,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Atualizar marcados',
            onPressed: carregandoMarcados || salvando
                ? null
                : () => carregarProdutosMarcados(),
            icon: carregandoMarcados
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget campoBusca() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: TextField(
        controller: buscaController,
        onChanged: aoDigitar,
        textInputAction: TextInputAction.search,
        onSubmitted: (value) {
          final busca = value.trim();
          if (busca.length >= 3) buscarProdutos(busca);
        },
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          labelText: 'Buscar produto por nome ou EAN',
          hintText: 'Ex: frango, melancia, picanha, 789...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: buscaController.text.trim().isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpar busca',
                  onPressed: limparBusca,
                  icon: const Icon(Icons.close),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.black.withOpacity(0.06)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: vermelho, width: 1.3),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget barraModoLista() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: exibindoBusca
                  ? chipInfo(
                      key: const ValueKey('busca'),
                      icon: Icons.manage_search,
                      texto: 'Resultado da busca',
                      cor: vermelho,
                    )
                  : chipInfo(
                      key: const ValueKey('marcados'),
                      icon: Icons.check_circle_outline,
                      texto: 'Produtos já marcados',
                      cor: verde,
                    ),
            ),
          ),
          if (exibindoBusca)
            TextButton.icon(
              onPressed: limparBusca,
              icon: const Icon(Icons.list_alt, size: 18),
              label: const Text('Ver marcados'),
              style: TextButton.styleFrom(foregroundColor: vermelho),
            ),
        ],
      ),
    );
  }

  Widget produtoCard(Map<String, dynamic> produto) {
    final nome = nomeProduto(produto);
    final ean = eanProduto(produto);
    final unidade = unidadeProduto(produto);
    final preco = precoProduto(produto);
    final ehKg = produtoKg(produto);
    final origemSalva = produtoVeioDaConfiguracao(produto);

    prepararController(ean);

    final pesoVariavel = pesoVariavelPorEan[ean] == true;
    final podeSalvar = ean.isNotEmpty && !salvando;
    final corStatus = pesoVariavel ? verde : textoFraco;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: pesoVariavel
              ? verde.withOpacity(0.20)
              : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: corStatus.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    pesoVariavel ? Icons.check_circle : Icons.scale_outlined,
                    color: corStatus,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: textoForte,
                          fontSize: 15.8,
                          height: 1.2,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          chipInfo(
                            icon: Icons.qr_code_2,
                            texto: ean.isEmpty ? 'Sem EAN' : ean,
                          ),
                          chipInfo(
                            icon: Icons.straighten,
                            texto: unidade.isEmpty
                                ? 'Unidade não informada'
                                : unidade,
                            cor: ehKg ? verde : Colors.orange.shade700,
                          ),
                          if (origemSalva)
                            chipInfo(
                              icon: Icons.bookmark_added_outlined,
                              texto: 'Já configurado',
                              cor: verde,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (preco > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: fundo,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.sell_outlined,
                      size: 18,
                      color: textoFraco,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ehKg
                          ? '${formatarMoeda(preco)}/kg'
                          : formatarMoeda(preco),
                      style: const TextStyle(
                        color: textoForte,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!ehKg && !origemSalva) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.orange.withOpacity(0.24)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 19,
                      color: Colors.orange.shade800,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'A API não retornou unidade KG para este item. Mesmo assim você pode marcar como peso variável se este produto deve aparecer por unidade com peso médio no app cliente.',
                        style: TextStyle(
                          color: Color(0xFF7C2D12),
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: fundo,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Peso variável',
                          style: TextStyle(
                            color: Color(0xFF111827),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Vende por unidade usando peso médio em KG.',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: pesoVariavel,
                    activeColor: verde,
                    onChanged: salvando || ean.isEmpty
                        ? null
                        : (value) {
                            setState(() {
                              pesoVariavelPorEan[ean] = value;
                              if (!value) {
                                pesoMedioControllers[ean]!.text = '';
                              }
                            });
                          },
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: pesoVariavel
                  ? Padding(
                      key: const ValueKey('campo_peso'),
                      padding: const EdgeInsets.only(top: 12),
                      child: TextField(
                        controller: pesoMedioControllers[ean],
                        enabled: !salvando,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                        ],
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          labelText: 'Peso médio em KG',
                          hintText: 'Ex: 2,000',
                          helperText:
                              'Exemplo: frango inteiro médio 2,000 kg; melancia média 5,000 kg.',
                          prefixIcon: const Icon(Icons.monitor_weight_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: verde,
                              width: 1.3,
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('sem_peso')),
            ),
            const SizedBox(height: 13),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: podeSalvar ? () => salvarProduto(produto) : null,
                icon: salvando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        pesoVariavel
                            ? Icons.save_outlined
                            : Icons.remove_circle_outline,
                      ),
                label: Text(
                  pesoVariavel
                      ? 'Salvar como peso variável'
                      : 'Salvar removido',
                ),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: pesoVariavel ? verde : textoFraco,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget estadoVazioMarcados() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: vermelho.withOpacity(0.08),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(Icons.scale_outlined, color: vermelho, size: 34),
            ),
            const SizedBox(height: 14),
            const Text(
              'Nenhum produto marcado ainda',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textoForte,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Busque um produto pelo nome ou EAN, ative peso variável e informe o peso médio em KG.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textoFraco, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  Widget estadoVazioBusca() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.10),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                Icons.search_off_outlined,
                color: Colors.orange.shade800,
                size: 34,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Nenhum produto encontrado',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textoForte,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tente buscar por outro nome ou pelo EAN do produto.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textoFraco, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  Widget listaProdutos() {
    final lista = exibindoBusca ? produtosBusca : produtosMarcados;
    final carregando = exibindoBusca ? carregandoBusca : carregandoMarcados;

    if (carregando) {
      return Center(child: CircularProgressIndicator(color: vermelho));
    }

    if (lista.isEmpty) {
      return exibindoBusca ? estadoVazioBusca() : estadoVazioMarcados();
    }

    return RefreshIndicator(
      color: vermelho,
      onRefresh: () async {
        if (exibindoBusca) {
          final busca = buscaController.text.trim();
          if (busca.length >= 3) await buscarProdutos(busca);
        } else {
          await carregarProdutosMarcados();
        }
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 18),
        itemCount: lista.length,
        itemBuilder: (context, index) {
          return produtoCard(lista[index]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: fundo,
      appBar: AppBar(
        title: const Text(
          'Produtos peso variável',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: carregandoMarcados || salvando
                ? null
                : () {
                    if (exibindoBusca) {
                      final busca = buscaController.text.trim();
                      buscarProdutos(busca);
                    } else {
                      carregarProdutosMarcados();
                    }
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            resumoTopo(),
            campoBusca(),
            barraModoLista(),
            Expanded(child: listaProdutos()),
          ],
        ),
      ),
    );
  }
}

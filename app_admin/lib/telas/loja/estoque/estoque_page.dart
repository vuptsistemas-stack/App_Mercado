import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/central_service.dart';
import '../../../services/sessao_loja.dart';
import '../scanner.dart';
import 'estoque_auditoria_page.dart';
import 'estoque_diferencas_page.dart';

bool lerBooleanoDinamico(dynamic valor, {required bool padrao}) {
  if (valor == true) {
    return true;
  }

  if (valor == false) {
    return false;
  }

  if (valor is String) {
    final texto = valor.trim().toLowerCase();

    if (texto == 'true' || texto == '1' || texto == 'sim' || texto == 's') {
      return true;
    }

    if (texto == 'false' ||
        texto == '0' ||
        texto == 'nao' ||
        texto == 'não' ||
        texto == 'n') {
      return false;
    }
  }

  if (valor is num) {
    return valor == 1;
  }

  return padrao;
}

bool usuarioTemAcessoTotalEstoque({bool masterCentralConfirmado = false}) {
  SessaoLoja.sincronizarSessaoAtual();

  final perfil = SessaoLoja.usuarioPerfil?.trim().toLowerCase() ?? '';

  return masterCentralConfirmado ||
      SessaoLoja.usuarioAdminLoja ||
      perfil == 'master' ||
      perfil == 'admin_master' ||
      perfil == 'master_central' ||
      perfil == 'super_admin';
}

bool usuarioPodePermissaoEstoque(
  String permissao, {
  bool masterCentralConfirmado = false,
}) {
  if (usuarioTemAcessoTotalEstoque(
    masterCentralConfirmado: masterCentralConfirmado,
  )) {
    return true;
  }

  return SessaoLoja.temPermissao(permissao);
}

bool usuarioPodeAlgumaPermissaoEstoque(
  List<String> permissoes, {
  bool masterCentralConfirmado = false,
}) {
  if (usuarioTemAcessoTotalEstoque(
    masterCentralConfirmado: masterCentralConfirmado,
  )) {
    return true;
  }

  return SessaoLoja.temAlgumaPermissao(permissoes);
}

class EstoquePage extends StatefulWidget {
  const EstoquePage({super.key});

  @override
  State<EstoquePage> createState() => _EstoquePageState();
}

class _EstoquePageState extends State<EstoquePage> {
  final CentralService centralService = CentralService();

  bool verificandoMasterCentral = true;
  bool usuarioMasterCentral = false;

  @override
  void initState() {
    super.initState();
    verificarUsuarioMasterCentral();
  }

  Future<void> verificarUsuarioMasterCentral() async {
    try {
      SessaoLoja.sincronizarSessaoAtual();

      final ehMaster = await centralService.usuarioEhMaster();

      if (!mounted) return;

      setState(() {
        usuarioMasterCentral = ehMaster;
        verificandoMasterCentral = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        usuarioMasterCentral = false;
        verificandoMasterCentral = false;
      });
    }
  }

  static Color get vermelho => SessaoLoja.corPrimaria;
  static Color get fundo => SessaoLoja.corFundo;

  void abrirTelaConsulta({
    required BuildContext context,
    required String titulo,
    required String subtitulo,
    required String tipo,
    required String permissao,
    required Color cor,
    required IconData icone,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConsultaEstoquePage(
          titulo: titulo,
          subtitulo: subtitulo,
          tipo: tipo,
          permissao: permissao,
          cor: cor,
          icone: icone,
          ignorarPermissao: usuarioMasterCentral,
        ),
      ),
    );
  }

  Widget cardOpcao({
    required String titulo,
    required String subtitulo,
    required IconData icone,
    required Color cor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: cor.withValues(alpha: 0.12),
              child: Icon(icone, color: cor, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitulo,
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black45),
          ],
        ),
      ),
    );
  }

  Widget avisoSemPermissaoEstoque() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: const Column(
        children: [
          Icon(Icons.lock_outline, size: 42, color: Colors.black38),
          SizedBox(height: 12),
          Text(
            'Nenhuma permissão de estoque liberada',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Peça para o administrador liberar uma das permissões de estoque.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget topo() {
    final nomeLoja = SessaoLoja.mercadoNome ?? 'Loja';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [SessaoLoja.corPrimaria, SessaoLoja.corSecundaria],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: vermelho.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
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
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.inventory_2, color: vermelho, size: 36),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Controle de Estoque',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  nomeLoja,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
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
    return Scaffold(
      backgroundColor: fundo,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Estoque'),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
      ),
      body: verificandoMasterCentral
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                topo(),
                const SizedBox(height: 24),
                const Text(
                  'Movimentações de estoque',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use a busca ou o scanner para localizar o produto.',
                  style: TextStyle(color: Colors.black54, fontSize: 14),
                ),
                const SizedBox(height: 16),
                if (usuarioPodePermissaoEstoque(
                  'estoque_entrada',
                  masterCentralConfirmado: usuarioMasterCentral,
                ))
                  cardOpcao(
                    titulo: 'Entrada de Estoque',
                    subtitulo: 'Tela pronta para registrar entrada depois',
                    icone: Icons.add_box,
                    cor: Colors.green,
                    onTap: () => abrirTelaConsulta(
                      context: context,
                      titulo: 'Entrada de Estoque',
                      subtitulo:
                          'Consulte o produto e veja o esboço da entrada.',
                      tipo: 'ENTRADA',
                      permissao: 'estoque_entrada',
                      cor: Colors.green,
                      icone: Icons.add_box,
                    ),
                  ),
                if (usuarioPodePermissaoEstoque(
                  'estoque_correcao',
                  masterCentralConfirmado: usuarioMasterCentral,
                ))
                  cardOpcao(
                    titulo: 'Correção de Estoque',
                    subtitulo: 'Tela pronta para corrigir estoque depois',
                    icone: Icons.edit_note,
                    cor: Colors.blue,
                    onTap: () => abrirTelaConsulta(
                      context: context,
                      titulo: 'Correção de Estoque',
                      subtitulo:
                          'Consulte o produto e veja o esboço da correção.',
                      tipo: 'CORRECAO',
                      permissao: 'estoque_correcao',
                      cor: Colors.blue,
                      icone: Icons.edit_note,
                    ),
                  ),
                if (usuarioPodeAlgumaPermissaoEstoque([
                  'estoque_entrada',
                  'estoque_correcao',
                ], masterCentralConfirmado: usuarioMasterCentral))
                  cardOpcao(
                    titulo: 'Estoque produtos app',
                    subtitulo: 'Entrada e correcao na tabela produtos_app',
                    icone: Icons.storefront,
                    cor: Colors.teal,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EstoqueProdutosAppPage(
                          ignorarPermissao: usuarioMasterCentral,
                        ),
                      ),
                    ),
                  ),
                if (usuarioPodePermissaoEstoque(
                  'estoque_baixa_avaria',
                  masterCentralConfirmado: usuarioMasterCentral,
                ))
                  cardOpcao(
                    titulo: 'Baixar por Avaria',
                    subtitulo: 'Baixar itens danificados do estoque',
                    icone: Icons.broken_image_outlined,
                    cor: Colors.deepOrange,
                    onTap: () => abrirTelaConsulta(
                      context: context,
                      titulo: 'Baixar por Avaria',
                      subtitulo:
                          'Escaneie ou busque o item e confirme a baixa.',
                      tipo: 'BAIXA_AVARIA',
                      permissao: 'estoque_baixa_avaria',
                      cor: Colors.deepOrange,
                      icone: Icons.broken_image_outlined,
                    ),
                  ),
                if (usuarioPodePermissaoEstoque(
                  'estoque_baixa_validade',
                  masterCentralConfirmado: usuarioMasterCentral,
                ))
                  cardOpcao(
                    titulo: 'Baixar por Validade',
                    subtitulo: 'Baixar itens vencidos ou impróprios',
                    icone: Icons.event_busy_outlined,
                    cor: Colors.red,
                    onTap: () => abrirTelaConsulta(
                      context: context,
                      titulo: 'Baixar por Validade',
                      subtitulo:
                          'Escaneie ou busque o item e confirme a baixa.',
                      tipo: 'BAIXA_VALIDADE',
                      permissao: 'estoque_baixa_validade',
                      cor: Colors.red,
                      icone: Icons.event_busy_outlined,
                    ),
                  ),
                if (usuarioPodePermissaoEstoque(
                  'estoque_abrir_pacote',
                  masterCentralConfirmado: usuarioMasterCentral,
                ))
                  cardOpcao(
                    titulo: 'Abrir pacote / granel',
                    subtitulo: 'Baixar embalagem e somar no item a granel',
                    icone: Icons.inventory_2_outlined,
                    cor: Colors.brown,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AbrirPacotePage(
                          ignorarPermissao: usuarioMasterCentral,
                        ),
                      ),
                    ),
                  ),
                if (usuarioPodePermissaoEstoque(
                  'estoque_auditoria',
                  masterCentralConfirmado: usuarioMasterCentral,
                ))
                  cardOpcao(
                    titulo: 'Auditoria',
                    subtitulo: 'Consultar alteracoes de estoque',
                    icone: Icons.fact_check_outlined,
                    cor: Colors.indigo,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EstoqueAuditoriaPage(),
                      ),
                    ),
                  ),
                if (usuarioPodeAlgumaPermissaoEstoque([
                  'estoque',
                  'estoque_auditoria',
                ], masterCentralConfirmado: usuarioMasterCentral))
                  cardOpcao(
                    titulo: 'Analisar diferenças',
                    subtitulo: 'Cruzar compra, venda e estoque atual',
                    icone: Icons.compare_arrows,
                    cor: Colors.deepPurple,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EstoqueDiferencasPage(),
                      ),
                    ),
                  ),
                if (!usuarioPodeAlgumaPermissaoEstoque([
                  'estoque',
                  'estoque_entrada',
                  'estoque_correcao',
                  'estoque_baixa_avaria',
                  'estoque_baixa_validade',
                  'estoque_abrir_pacote',
                  'estoque_auditoria',
                ], masterCentralConfirmado: usuarioMasterCentral))
                  avisoSemPermissaoEstoque(),
              ],
            ),
    );
  }
}

class AbrirPacotePage extends StatefulWidget {
  final bool ignorarPermissao;

  const AbrirPacotePage({super.key, this.ignorarPermissao = false});

  @override
  State<AbrirPacotePage> createState() => _AbrirPacotePageState();
}

class _AbrirPacotePageState extends State<AbrirPacotePage> {
  final CentralService centralService = CentralService();
  final pacoteController = TextEditingController();
  final granelController = TextEditingController();
  final quantidadeController = TextEditingController();
  final observacaoController = TextEditingController();

  bool carregandoPacote = false;
  bool carregandoGranel = false;
  bool carregandoToken = false;
  bool gravando = false;
  bool estoqueUpdateTokenAtivo = false;
  bool estoqueDetalhadoAtivo = false;
  String estoqueUpdateToken = '';
  String? erro;

  Map<String, dynamic>? produtoPacote;
  Map<String, dynamic>? produtoGranel;
  List<Map<String, dynamic>> locaisPacote = [];
  List<Map<String, dynamic>> locaisGranel = [];
  Map<String, dynamic>? localPacoteSelecionado;
  Map<String, dynamic>? localGranelSelecionado;
  bool carregandoLocaisPacote = false;
  bool carregandoLocaisGranel = false;
  String? erroLocaisPacote;
  String? erroLocaisGranel;
  int codigoLocaisPacoteAtual = 0;
  int codigoLocaisGranelAtual = 0;

  static Color get corPrimaria => SessaoLoja.corPrimaria;
  static Color get fundo => SessaoLoja.corFundo;

  @override
  void initState() {
    super.initState();
    carregarTokenUpdateEstoque();
  }

  @override
  void dispose() {
    pacoteController.dispose();
    granelController.dispose();
    quantidadeController.dispose();
    observacaoController.dispose();
    super.dispose();
  }

  Future<void> carregarTokenUpdateEstoque() async {
    final mercadoId = SessaoLoja.mercadoId;

    if (mercadoId == null || mercadoId.trim().isEmpty) {
      return;
    }

    setState(() => carregandoToken = true);

    try {
      final conexao = await centralService.buscarConexaoMercado(mercadoId);

      if (!mounted) return;

      setState(() {
        estoqueUpdateToken =
            conexao['estoque_update_token']?.toString().trim() ?? '';
        estoqueUpdateTokenAtivo = lerBooleanoDinamico(
          conexao['estoque_update_token_ativo'],
          padrao: false,
        );
        estoqueDetalhadoAtivo = lerBooleanoDinamico(
          conexao['estoque_detalhado_ativo'],
          padrao: false,
        );
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        estoqueUpdateToken = '';
        estoqueUpdateTokenAtivo = false;
        estoqueDetalhadoAtivo = false;
      });
    } finally {
      if (mounted) setState(() => carregandoToken = false);
    }
  }

  String texto(dynamic valor, {String fallback = '-'}) {
    final t = valor?.toString().trim() ?? '';
    return t.isEmpty ? fallback : t;
  }

  String somenteNumeros(String valor) {
    return valor.replaceAll(RegExp(r'\D'), '');
  }

  String normalizarEan(String valor) {
    final numeros = somenteNumeros(valor);

    if (numeros.isEmpty) return '';
    if (numeros.length < 14) return numeros.padLeft(14, '0');

    return numeros;
  }

  double numero(dynamic valor) {
    if (valor == null) return 0;
    if (valor is num) return valor.toDouble();

    return double.tryParse(valor.toString().replaceAll(',', '.')) ?? 0;
  }

  String quantidade(dynamic valor) {
    final n = numero(valor);

    if (n == n.roundToDouble()) {
      return n.toStringAsFixed(0);
    }

    return n.toStringAsFixed(3).replaceAll('.', ',');
  }

  String unidadeProduto(Map<String, dynamic> produto) {
    final unidade = texto(
      produto['sigla_saida'],
      fallback: 'UN',
    ).trim().toUpperCase();
    return unidade.isEmpty ? 'UN' : unidade;
  }

  double estoqueProduto(Map<String, dynamic> produto) {
    return numero(
      produto['estoque_atual'] ??
          produto['quantidade'] ??
          produto['estoque'] ??
          produto['saldo'],
    );
  }

  bool get usarEstoqueDetalhadoPorLocal => estoqueDetalhadoAtivo;

  int? inteiro(dynamic valor) {
    if (valor == null) return null;
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor.toString().trim());
  }

  int? idLocalEstoque(Map<String, dynamic> local) {
    return inteiro(local['local_estoqueid'] ?? local['local_estoque_id']);
  }

  String nomeLocalEstoque(Map<String, dynamic> local) {
    final id = idLocalEstoque(local);
    final nome = texto(local['nome_local_estoque'] ?? local['nome']);

    if (nome != '-') {
      return nome;
    }

    return id == null ? 'Local de estoque' : 'Local $id';
  }

  double quantidadeLocalEstoque(Map<String, dynamic> local) {
    return numero(local['quantidade']);
  }

  bool localConsideradoNoApp(Map<String, dynamic> local) {
    return lerBooleanoDinamico(local['considerado_no_app'], padrao: true);
  }

  String? chaveLocalEstoque(Map<String, dynamic>? local) {
    final id = local == null ? null : idLocalEstoque(local);
    return id?.toString();
  }

  double estoquePacoteParaValidacao() {
    if (usarEstoqueDetalhadoPorLocal && localPacoteSelecionado != null) {
      return quantidadeLocalEstoque(localPacoteSelecionado!);
    }

    final pacote = produtoPacote;
    return pacote == null ? 0 : estoqueProduto(pacote);
  }

  List<Map<String, dynamic>> extrairLocaisEstoque(dynamic data) {
    if (data is Map && data['locais'] is List) {
      return List<Map<String, dynamic>>.from(data['locais']);
    }

    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    return [];
  }

  Uri uriLocaisEstoqueProduto(Map<String, dynamic> produto) {
    final api = baseUrlApi();
    final produtoId = produto['produto_id']?.toString().trim();

    if (produtoId != null && produtoId.isNotEmpty) {
      return Uri.parse(
        '$api/produto/${Uri.encodeComponent(produtoId)}/estoque-locais',
      );
    }

    final ean = produto['ean_principal']?.toString().trim();

    if (ean == null || ean.isEmpty) {
      throw Exception('Produto sem produto_id ou EAN para consultar locais.');
    }

    return Uri.parse(
      '$api/produto/ean/${Uri.encodeComponent(ean)}/estoque-locais',
    );
  }

  void limparLocaisProduto({required bool pacote}) {
    if (pacote) {
      codigoLocaisPacoteAtual++;
      locaisPacote = [];
      localPacoteSelecionado = null;
      carregandoLocaisPacote = false;
      erroLocaisPacote = null;
    } else {
      codigoLocaisGranelAtual++;
      locaisGranel = [];
      localGranelSelecionado = null;
      carregandoLocaisGranel = false;
      erroLocaisGranel = null;
    }
  }

  Future<void> carregarLocaisEstoqueProduto(
    Map<String, dynamic> produto, {
    required bool pacote,
  }) async {
    if (!usarEstoqueDetalhadoPorLocal) {
      return;
    }

    final codigoExecucao = pacote
        ? ++codigoLocaisPacoteAtual
        : ++codigoLocaisGranelAtual;

    setState(() {
      if (pacote) {
        carregandoLocaisPacote = true;
        erroLocaisPacote = null;
        locaisPacote = [];
        localPacoteSelecionado = null;
      } else {
        carregandoLocaisGranel = true;
        erroLocaisGranel = null;
        locaisGranel = [];
        localGranelSelecionado = null;
      }
    });

    try {
      final resposta = await http
          .get(uriLocaisEstoqueProduto(produto))
          .timeout(const Duration(seconds: 20));

      dynamic data;
      try {
        data = jsonDecode(resposta.body);
      } catch (_) {
        data = null;
      }

      if (resposta.statusCode == 404) {
        throw Exception(
          'Nenhum local de estoque encontrado para este produto.',
        );
      }

      if (resposta.statusCode != 200) {
        final mensagem = data is Map && data['erro'] != null
            ? data['erro'].toString()
            : resposta.body;
        throw Exception(
          'Erro ${resposta.statusCode} ao consultar locais: $mensagem',
        );
      }

      final locais = extrairLocaisEstoque(
        data,
      ).where(localConsideradoNoApp).toList();
      final localPadrao = locais.length == 1 ? locais.first : null;

      if (!mounted) return;
      if (pacote && codigoExecucao != codigoLocaisPacoteAtual) return;
      if (!pacote && codigoExecucao != codigoLocaisGranelAtual) return;

      setState(() {
        if (pacote) {
          locaisPacote = locais;
          localPacoteSelecionado = localPadrao;
          carregandoLocaisPacote = false;
          erroLocaisPacote = null;
        } else {
          locaisGranel = locais;
          localGranelSelecionado = localPadrao;
          carregandoLocaisGranel = false;
          erroLocaisGranel = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      if (pacote && codigoExecucao != codigoLocaisPacoteAtual) return;
      if (!pacote && codigoExecucao != codigoLocaisGranelAtual) return;

      setState(() {
        if (pacote) {
          carregandoLocaisPacote = false;
          erroLocaisPacote = CentralService.mensagemErroUsuario(e);
        } else {
          carregandoLocaisGranel = false;
          erroLocaisGranel = CentralService.mensagemErroUsuario(e);
        }
      });
    }
  }

  bool permiteQuantidadeFracionada(Map<String, dynamic> produto) {
    return unidadeProduto(produto) == 'KG';
  }

  double? lerQuantidadeDigitada() {
    final valor = quantidadeController.text.trim().replaceAll(',', '.');
    if (valor.isEmpty) return null;
    return double.tryParse(valor);
  }

  String baseUrlApi() {
    final apiBaseUrl = SessaoLoja.apiBaseUrl;

    if (apiBaseUrl == null || apiBaseUrl.trim().isEmpty) {
      throw Exception('API da loja nao configurada.');
    }

    return apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  }

  Map<String, String> headersUpdateEstoque() {
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (estoqueUpdateToken.trim().isNotEmpty) {
      headers['x-api-key'] = estoqueUpdateToken.trim();
    }

    return headers;
  }

  List<Map<String, dynamic>> extrairProdutos(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (data is Map) {
      if (data['erro'] != null) {
        throw Exception(data['erro'].toString());
      }

      if (data['produtos'] is List) {
        return List<Map<String, dynamic>>.from(data['produtos']);
      }

      if (data['produto'] is Map) {
        return [Map<String, dynamic>.from(data['produto'])];
      }

      if (data['produto_id'] != null) {
        return [Map<String, dynamic>.from(data)];
      }
    }

    return [];
  }

  Future<List<Map<String, dynamic>>> buscarNaApi(String busca) async {
    final api = baseUrlApi();
    final numeros = somenteNumeros(busca);
    final urls = <Uri>[];

    if (numeros.isNotEmpty) {
      urls.add(Uri.parse('$api/produto/ean/${normalizarEan(busca)}'));
    }

    urls.add(
      Uri.parse('$api/produto').replace(queryParameters: {'busca': busca}),
    );

    for (final uri in urls) {
      final resposta = await http.get(uri).timeout(const Duration(seconds: 20));

      if (resposta.statusCode == 404) continue;

      if (resposta.statusCode != 200) {
        throw Exception('Erro na API ${resposta.statusCode}: ${resposta.body}');
      }

      final lista = extrairProdutos(jsonDecode(resposta.body));
      if (lista.isNotEmpty) return lista;
    }

    return [];
  }

  Future<Map<String, dynamic>?> escolherProdutoDaLista(
    List<Map<String, dynamic>> produtos,
    String titulo,
  ) async {
    if (produtos.isEmpty) return null;
    if (produtos.length == 1) return produtos.first;

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemCount: produtos.length + 1,
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (_, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                );
              }

              final produto = produtos[index - 1];
              return ListTile(
                title: Text(
                  texto(produto['nome_produto']),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  'EAN: ${texto(produto['ean_principal'])} | Est: ${quantidade(estoqueProduto(produto))}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, produto),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> buscarProduto({required bool pacote, String? valorBusca}) async {
    final busca =
        (valorBusca ?? (pacote ? pacoteController : granelController).text)
            .trim();

    if (busca.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Digite ou escaneie o produto.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      erro = null;
      if (pacote) {
        carregandoPacote = true;
        produtoPacote = null;
        limparLocaisProduto(pacote: true);
      } else {
        carregandoGranel = true;
        produtoGranel = null;
        limparLocaisProduto(pacote: false);
      }
    });

    try {
      final produtos = await buscarNaApi(busca);

      if (produtos.isEmpty) {
        throw Exception('Produto nao cadastrado.');
      }

      if (!mounted) return;

      final escolhido = await escolherProdutoDaLista(
        produtos,
        pacote ? 'Selecione o pacote' : 'Selecione o item a granel',
      );

      if (escolhido == null || !mounted) return;

      setState(() {
        if (pacote) {
          produtoPacote = escolhido;
          pacoteController.text = texto(escolhido['nome_produto']);
        } else {
          produtoGranel = escolhido;
          granelController.text = texto(escolhido['nome_produto']);
        }
      });

      unawaited(carregarLocaisEstoqueProduto(escolhido, pacote: pacote));
    } catch (e) {
      if (!mounted) return;

      setState(() {
        erro = CentralService.mensagemErroUsuario(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          if (pacote) {
            carregandoPacote = false;
          } else {
            carregandoGranel = false;
          }
        });
      }
    }
  }

  Future<void> abrirScanner({required bool pacote}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          onDetect: (codigo) {
            if (pacote) {
              pacoteController.text = codigo;
            } else {
              granelController.text = codigo;
            }

            buscarProduto(pacote: pacote, valorBusca: codigo);
          },
        ),
      ),
    );
  }

  String? validarFinalizacao() {
    final pacote = produtoPacote;
    final granel = produtoGranel;
    final qtd = lerQuantidadeDigitada();

    if (pacote == null) return 'Selecione o produto do pacote.';
    if (granel == null) return 'Selecione o item a granel.';

    if (pacote['produto_id']?.toString() == granel['produto_id']?.toString()) {
      return 'O pacote e o item a granel nao podem ser o mesmo produto.';
    }

    if (usarEstoqueDetalhadoPorLocal && localPacoteSelecionado == null) {
      return 'Selecione o local de estoque do produto fechado.';
    }

    if (usarEstoqueDetalhadoPorLocal && localGranelSelecionado == null) {
      return 'Selecione o local de estoque do item a granel.';
    }

    if (estoquePacoteParaValidacao() < 1) {
      return usarEstoqueDetalhadoPorLocal
          ? 'O produto do pacote nao tem estoque no local selecionado.'
          : 'O produto do pacote nao tem estoque para abrir.';
    }

    if (qtd == null || qtd <= 0) {
      return 'Informe a quantidade existente dentro do pacote.';
    }

    if (!permiteQuantidadeFracionada(granel) && qtd != qtd.roundToDouble()) {
      return 'O item a granel esta em ${unidadeProduto(granel)}. Informe numero inteiro.';
    }

    if (estoqueUpdateTokenAtivo && estoqueUpdateToken.trim().isEmpty) {
      return 'Token de update de estoque nao carregado. Verifique a configuracao do mercado.';
    }

    return null;
  }

  Future<bool> confirmarFinalizacao() async {
    final pacote = produtoPacote!;
    final granel = produtoGranel!;
    final qtd = lerQuantidadeDigitada()!;
    final localPacote = usarEstoqueDetalhadoPorLocal
        ? localPacoteSelecionado
        : null;
    final localGranel = usarEstoqueDetalhadoPorLocal
        ? localGranelSelecionado
        : null;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar abertura'),
        content: Text(
          'Baixar 1 unidade do pacote:\n'
          '${texto(pacote['nome_produto'])}\n\n'
          '${localPacote == null ? '' : 'Local de saida: ${nomeLocalEstoque(localPacote)}\n\n'}'
          'Adicionar ${quantidade(qtd)} ${unidadeProduto(granel)} no item:\n'
          '${texto(granel['nome_produto'])}'
          '${localGranel == null ? '' : '\n\nLocal de entrada: ${nomeLocalEstoque(localGranel)}'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: corPrimaria,
              foregroundColor: Colors.white,
            ),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );

    return confirmado == true;
  }

  Future<String?> registrarAuditoria({
    required String tipo,
    required Map<String, dynamic> produto,
    required double estoqueAnterior,
    required double quantidadeInformada,
    required double quantidadeAlterada,
    required double estoqueNovo,
    required String unidade,
    required String observacao,
    Map<String, dynamic>? localEstoque,
  }) async {
    try {
      SessaoLoja.sincronizarSessaoAtual();
      await SessaoLoja.renovarSessaoLojaSePossivel();

      final lojaAccessToken =
          SessaoLoja.supabaseLoja?.auth.currentSession?.accessToken ??
          SessaoLoja.lojaAccessToken;

      final registro = <String, dynamic>{
        'mercado_id': SessaoLoja.mercadoId,
        'mercado_codigo': SessaoLoja.mercadoCodigo,
        'tipo_movimentacao': tipo,
        'produto_id': produto['produto_id']?.toString(),
        'ean_principal': produto['ean_principal']?.toString(),
        'nome_produto': texto(produto['nome_produto']),
        'local_estoqueid': localEstoque == null
            ? produto['local_estoqueid']
            : idLocalEstoque(localEstoque),
        'local_estoque_id': localEstoque == null
            ? produto['local_estoqueid']
            : idLocalEstoque(localEstoque),
        'nome_local_estoque': localEstoque == null
            ? (produto['local_estoqueid'] == null
                  ? null
                  : 'Local ${produto['local_estoqueid']}')
            : nomeLocalEstoque(localEstoque),
        'estoque_anterior': estoqueAnterior,
        'quantidade_informada': quantidadeInformada,
        'quantidade_alterada': quantidadeAlterada,
        'estoque_novo': estoqueNovo,
        'unidade': unidade,
        'observacao': observacao,
        'usuario_id': SessaoLoja.usuarioId,
        'usuario_nome': SessaoLoja.usuarioNome ?? SessaoLoja.usuarioLogin,
        'usuario_email': SessaoLoja.usuarioEmail ?? SessaoLoja.usuarioLogin,
        'usuario_perfil': SessaoLoja.usuarioPerfil,
        'origem': 'app_preco',
      };

      final resposta = await Supabase.instance.client.functions.invoke(
        'registrar-estoque-auditoria',
        body: {
          'mercado_id': SessaoLoja.mercadoId,
          'mercado_codigo': SessaoLoja.mercadoCodigo,
          'loja_access_token': lojaAccessToken,
          'registro': registro,
        },
      );

      final data = resposta.data;

      if (data is Map && data['erro'] != null) {
        throw Exception(data['erro'].toString());
      }

      return null;
    } catch (e) {
      return CentralService.mensagemErroUsuario(e);
    }
  }

  Future<void> finalizarAbertura() async {
    final erroValidacao = validarFinalizacao();

    if (erroValidacao != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erroValidacao), backgroundColor: Colors.red),
      );
      return;
    }

    final confirmado = await confirmarFinalizacao();
    if (!confirmado) return;

    setState(() {
      gravando = true;
      erro = null;
    });

    try {
      final pacote = produtoPacote!;
      final granel = produtoGranel!;
      final qtd = lerQuantidadeDigitada()!;
      final localPacote = usarEstoqueDetalhadoPorLocal
          ? localPacoteSelecionado
          : null;
      final localGranel = usarEstoqueDetalhadoPorLocal
          ? localGranelSelecionado
          : null;
      final body = <String, dynamic>{
        'pacote_produto_id': pacote['produto_id'],
        'granel_produto_id': granel['produto_id'],
        'quantidade_granel': qtd,
        'usuario_login': SessaoLoja.usuarioLogin ?? SessaoLoja.usuarioNome,
        'observacao': observacaoController.text.trim(),
      };

      final localPacoteId = localPacote == null
          ? null
          : idLocalEstoque(localPacote);
      final localGranelId = localGranel == null
          ? null
          : idLocalEstoque(localGranel);

      if (localPacoteId != null) {
        body['pacote_local_estoqueid'] = localPacoteId;
      }

      if (localGranelId != null) {
        body['granel_local_estoqueid'] = localGranelId;
      }

      final resposta = await http
          .post(
            Uri.parse('${baseUrlApi()}/estoque/abrir-pacote'),
            headers: headersUpdateEstoque(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));

      dynamic data;
      try {
        data = jsonDecode(resposta.body);
      } catch (_) {
        data = null;
      }

      if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
        final mensagemApi = data is Map && data['erro'] != null
            ? data['erro'].toString().trim()
            : resposta.body.trim();
        final rotaAusente = resposta.statusCode == 404 &&
            (mensagemApi.isEmpty ||
                mensagemApi.toLowerCase().contains('cannot post') ||
                mensagemApi.toLowerCase().contains('<!doctype html'));

        if (rotaAusente) {
          throw const ErroUsuarioException(
            'A funcao Abrir pacote ainda nao esta instalada na API desta loja.',
          );
        }

        if (resposta.statusCode == 401 || resposta.statusCode == 403) {
          throw const ErroUsuarioException(
            'A API recusou a atualizacao do estoque. Confira o token de estoque da loja.',
          );
        }

        throw ErroUsuarioException(
          mensagemApi.isEmpty
              ? 'A API da loja recusou a abertura do pacote (erro ${resposta.statusCode}).'
              : mensagemApi,
        );
      }

      if (data is! Map || data['pacote'] is! Map || data['granel'] is! Map) {
        throw Exception('Resposta invalida da API.');
      }

      final pacoteAtualizado = Map<String, dynamic>.from(data['pacote']);
      final granelAtualizado = Map<String, dynamic>.from(data['granel']);
      final obsDigitada = observacaoController.text.trim();
      final obsBase =
          'Abertura de pacote: ${texto(pacoteAtualizado['nome_produto'])} -> ${texto(granelAtualizado['nome_produto'])}';
      final obs = obsDigitada.isEmpty ? obsBase : '$obsBase | $obsDigitada';

      final erroAuditoriaPacote = await registrarAuditoria(
        tipo: 'ABERTURA_PACOTE_SAIDA',
        produto: pacoteAtualizado,
        estoqueAnterior: numero(pacoteAtualizado['estoque_anterior']),
        quantidadeInformada: 1,
        quantidadeAlterada: -1,
        estoqueNovo: numero(pacoteAtualizado['estoque_novo']),
        unidade: unidadeProduto(pacoteAtualizado),
        observacao: obs,
        localEstoque: localPacote,
      );

      final erroAuditoriaGranel = await registrarAuditoria(
        tipo: 'ABERTURA_PACOTE_ENTRADA',
        produto: granelAtualizado,
        estoqueAnterior: numero(granelAtualizado['estoque_anterior']),
        quantidadeInformada: qtd,
        quantidadeAlterada: qtd,
        estoqueNovo: numero(granelAtualizado['estoque_novo']),
        unidade: unidadeProduto(granelAtualizado),
        observacao: obs,
        localEstoque: localGranel,
      );

      if (!mounted) return;

      final auditoriaOk =
          erroAuditoriaPacote == null && erroAuditoriaGranel == null;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            auditoriaOk
                ? 'Pacote aberto e estoque atualizado.'
                : 'Estoque atualizado, mas a auditoria nao foi gravada completamente.',
          ),
          backgroundColor: auditoriaOk ? Colors.green : Colors.orange,
        ),
      );

      setState(() {
        produtoPacote = null;
        produtoGranel = null;
        pacoteController.clear();
        granelController.clear();
        quantidadeController.clear();
        observacaoController.clear();
        limparLocaisProduto(pacote: true);
        limparLocaisProduto(pacote: false);
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => erro = CentralService.mensagemErroUsuario(e));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erro!), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => gravando = false);
    }
  }

  Widget topo() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: corPrimaria.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: corPrimaria.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: corPrimaria.withValues(alpha: 0.14),
            child: Icon(Icons.inventory_2_outlined, color: corPrimaria),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Abrir pacote / granel',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1F2937),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Baixe uma embalagem e some a quantidade no item vendido a granel.',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget produtoResumo(Map<String, dynamic> produto, Color cor) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            texto(produto['nome_produto']),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            'EAN: ${texto(produto['ean_principal'])} | EST: ${quantidade(estoqueProduto(produto))} ${unidadeProduto(produto)}',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget seletorLocalEstoque({
    required bool pacote,
    required Map<String, dynamic> produto,
    required Color cor,
  }) {
    final locais = pacote ? locaisPacote : locaisGranel;
    final selecionado = pacote
        ? localPacoteSelecionado
        : localGranelSelecionado;
    final carregando = pacote ? carregandoLocaisPacote : carregandoLocaisGranel;
    final erroLocal = pacote ? erroLocaisPacote : erroLocaisGranel;
    final unidade = unidadeProduto(produto);

    if (carregando) {
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cor.withValues(alpha: 0.20)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: cor),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text('Carregando locais de estoque...')),
          ],
        ),
      );
    }

    if (erroLocal != null && erroLocal.trim().isNotEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.30)),
        ),
        child: Text(
          erroLocal,
          style: const TextStyle(
            color: Colors.orange,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    if (locais.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.28)),
        ),
        child: const Text(
          'Nenhum local de estoque considerado no app foi retornado para este produto.',
        ),
      );
    }

    final chaveSelecionada = chaveLocalEstoque(selecionado);
    final itens = locais.map((local) {
      final chave = chaveLocalEstoque(local) ?? '';
      final nome = nomeLocalEstoque(local);
      final saldo = quantidade(quantidadeLocalEstoque(local));

      return DropdownMenuItem<String>(
        value: chave,
        child: Text(
          '$nome - $saldo $unidade',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }).toList();

    final value = itens.any((item) => item.value == chaveSelecionada)
        ? chaveSelecionada
        : null;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        menuMaxHeight: 320,
        decoration: InputDecoration(
          labelText: pacote
              ? 'Local para baixar o pacote'
              : 'Local para somar o granel',
          helperText: pacote
              ? 'Escolha de onde sairá 1 unidade.'
              : 'Escolha onde entrará a quantidade do pacote.',
          prefixIcon: const Icon(Icons.inventory_2_outlined),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
        items: itens,
        onChanged: gravando
            ? null
            : (chave) {
                if (chave == null) return;

                final local = locais.firstWhere(
                  (item) => chaveLocalEstoque(item) == chave,
                );

                setState(() {
                  if (pacote) {
                    localPacoteSelecionado = local;
                  } else {
                    localGranelSelecionado = local;
                  }
                });
              },
      ),
    );
  }

  Widget campoProduto({
    required String titulo,
    required String hint,
    required TextEditingController controller,
    required bool pacote,
    required bool carregando,
    required Map<String, dynamic>? produto,
    required Color cor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            enabled: !gravando && !carregando,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: controller.text.trim().isEmpty
                  ? null
                  : IconButton(
                      onPressed: gravando
                          ? null
                          : () {
                              setState(() {
                                controller.clear();
                                if (pacote) {
                                  produtoPacote = null;
                                  limparLocaisProduto(pacote: true);
                                } else {
                                  produtoGranel = null;
                                  limparLocaisProduto(pacote: false);
                                }
                              });
                            },
                      icon: const Icon(Icons.close),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onSubmitted: (_) => buscarProduto(pacote: pacote),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: gravando || carregando
                      ? null
                      : () => buscarProduto(pacote: pacote),
                  icon: carregando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search),
                  label: const Text('Buscar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: gravando || carregando
                      ? null
                      : () => abrirScanner(pacote: pacote),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scanner'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cor,
                    side: BorderSide(color: cor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (produto != null) produtoResumo(produto, cor),
          if (produto != null && usarEstoqueDetalhadoPorLocal)
            seletorLocalEstoque(pacote: pacote, produto: produto, cor: cor),
        ],
      ),
    );
  }

  Widget painelQuantidade() {
    final granel = produtoGranel;
    final fracionado = granel == null
        ? false
        : permiteQuantidadeFracionada(granel);
    final unidade = granel == null ? 'UN' : unidadeProduto(granel);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: quantidadeController,
            enabled: !gravando,
            keyboardType: fracionado
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.number,
            inputFormatters: fracionado
                ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))]
                : [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Quantidade dentro do pacote',
              helperText: fracionado
                  ? 'Unidade $unidade aceita quantidade fracionada.'
                  : 'Unidade $unidade aceita apenas numero inteiro.',
              prefixIcon: const Icon(Icons.exposure_plus_1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: observacaoController,
            enabled: !gravando,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Observacao',
              hintText: 'Opcional',
              prefixIcon: const Icon(Icons.notes),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final temAcesso =
        widget.ignorarPermissao ||
        usuarioPodePermissaoEstoque('estoque_abrir_pacote');

    return Scaffold(
      backgroundColor: fundo,
      appBar: AppBar(
        title: const Text('Abrir pacote'),
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: temAcesso
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  topo(),
                  const SizedBox(height: 14),
                  campoProduto(
                    titulo: '1. Produto fechado / pacote',
                    hint: 'EAN ou descricao do pacote',
                    controller: pacoteController,
                    pacote: true,
                    carregando: carregandoPacote,
                    produto: produtoPacote,
                    cor: Colors.brown,
                  ),
                  const SizedBox(height: 14),
                  campoProduto(
                    titulo: '2. Item a granel',
                    hint: 'EAN ou descricao do item a granel',
                    controller: granelController,
                    pacote: false,
                    carregando: carregandoGranel,
                    produto: produtoGranel,
                    cor: corPrimaria,
                  ),
                  const SizedBox(height: 14),
                  painelQuantidade(),
                  if (erro != null && erro!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Text(
                        erro!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed:
                          gravando ||
                              carregandoToken ||
                              carregandoLocaisPacote ||
                              carregandoLocaisGranel ||
                              (usarEstoqueDetalhadoPorLocal &&
                                  produtoPacote != null &&
                                  produtoGranel != null &&
                                  (localPacoteSelecionado == null ||
                                      localGranelSelecionado == null))
                          ? null
                          : finalizarAbertura,
                      icon: gravando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle),
                      label: Text(
                        carregandoToken
                            ? 'Carregando autorizacao...'
                            : 'Finalizar abertura',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: corPrimaria,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Seu usuario nao tem permissao para abrir pacote.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
      ),
    );
  }
}

class EstoqueProdutosAppPage extends StatefulWidget {
  final bool ignorarPermissao;

  const EstoqueProdutosAppPage({super.key, this.ignorarPermissao = false});

  @override
  State<EstoqueProdutosAppPage> createState() => _EstoqueProdutosAppPageState();
}

class _EstoqueProdutosAppPageState extends State<EstoqueProdutosAppPage> {
  final CentralService centralService = CentralService();
  final buscaController = TextEditingController();
  final quantidadeController = TextEditingController();
  final observacaoController = TextEditingController();

  Timer? debounceBusca;
  int codigoBuscaAtual = 0;

  bool carregando = false;
  bool buscandoSugestoes = false;
  bool gravando = false;
  bool listandoTodos = false;
  String? erro;
  String tipoSelecionado = 'ENTRADA';

  List<Map<String, dynamic>> produtos = [];
  Map<String, dynamic>? produtoSelecionado;

  static Color get vermelho => SessaoLoja.corPrimaria;
  static Color get fundo => SessaoLoja.corFundo;

  bool get podeEntrada {
    return usuarioPodePermissaoEstoque(
      'estoque_entrada',
      masterCentralConfirmado: widget.ignorarPermissao,
    );
  }

  bool get podeCorrecao {
    return usuarioPodePermissaoEstoque(
      'estoque_correcao',
      masterCentralConfirmado: widget.ignorarPermissao,
    );
  }

  bool get temAcesso => podeEntrada || podeCorrecao;

  bool get modoEntrada => tipoSelecionado == 'ENTRADA';

  Color get corMovimentacao => modoEntrada ? Colors.green : Colors.blue;

  @override
  void initState() {
    super.initState();
    SessaoLoja.sincronizarSessaoAtual();
    tipoSelecionado = podeEntrada ? 'ENTRADA' : 'CORRECAO';
  }

  @override
  void dispose() {
    debounceBusca?.cancel();
    buscaController.dispose();
    quantidadeController.dispose();
    observacaoController.dispose();
    super.dispose();
  }

  String texto(dynamic valor, {String fallback = '-'}) {
    final t = valor?.toString().trim() ?? '';
    return t.isEmpty ? fallback : t;
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

    if (t.contains(',')) {
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

  double custoProduto(Map<String, dynamic> produto) {
    for (final campo in [
      'preco_custo',
      'custo_unitario',
      'preco_compra',
      'custo_liquido',
      'custo',
      'valor_custo',
    ]) {
      final valor = numero(produto[campo]);
      if (valor > 0) return valor;
    }
    return 0;
  }

  Map<String, dynamic> custoAuditoriaProduto(Map<String, dynamic> produto) {
    final custo = custoProduto(produto);
    if (custo <= 0) return {};
    return {'preco_custo': custo, 'custo_unitario': custo};
  }

  String eanProduto(Map<String, dynamic> produto) {
    final ean = texto(produto['ean'], fallback: '');

    if (ean.isNotEmpty) {
      return ean;
    }

    return texto(produto['codigo_barras'], fallback: '');
  }

  String unidadeProduto(Map<String, dynamic> produto) {
    final unidade = texto(produto['unidade'], fallback: 'UN').toUpperCase();
    return unidade.isEmpty ? 'UN' : unidade;
  }

  bool permiteQuantidadeFracionada(Map<String, dynamic> produto) {
    return unidadeProduto(produto) == 'KG';
  }

  TextInputType tipoTecladoQuantidade(Map<String, dynamic> produto) {
    if (permiteQuantidadeFracionada(produto)) {
      return const TextInputType.numberWithOptions(decimal: true);
    }

    return TextInputType.number;
  }

  List<TextInputFormatter> formatadoresQuantidade(
    Map<String, dynamic> produto,
  ) {
    if (permiteQuantidadeFracionada(produto)) {
      return [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))];
    }

    return [FilteringTextInputFormatter.digitsOnly];
  }

  double? lerQuantidadeDigitada(String valor) {
    final textoValor = valor.trim().replaceAll(',', '.');

    if (textoValor.isEmpty) {
      return null;
    }

    return double.tryParse(textoValor);
  }

  String? validarQuantidade({
    required Map<String, dynamic> produto,
    required double quantidadeInformada,
  }) {
    if (quantidadeInformada < 0) {
      return 'A quantidade nao pode ser negativa.';
    }

    if (modoEntrada && quantidadeInformada <= 0) {
      return 'Informe uma quantidade de entrada maior que zero.';
    }

    if (!permiteQuantidadeFracionada(produto) &&
        quantidadeInformada != quantidadeInformada.roundToDouble()) {
      return 'Este produto esta em ${unidadeProduto(produto)}. Informe apenas numero inteiro.';
    }

    return null;
  }

  String? mercadoIdAtual() {
    final mercadoId = SessaoLoja.mercadoId?.trim();
    return mercadoId == null || mercadoId.isEmpty ? null : mercadoId;
  }

  Future<List<Map<String, dynamic>>> buscarProdutosApp(String busca) async {
    final mercadoId = mercadoIdAtual();

    if (mercadoId == null) {
      throw Exception('Loja nao identificada.');
    }

    return centralService.listarProdutosAppEstoque(
      mercadoId: mercadoId,
      mercadoCodigo: SessaoLoja.mercadoCodigo,
      busca: busca,
    );
  }

  void agendarBuscaAutomatica(String valor) {
    debounceBusca?.cancel();

    final busca = valor.trim();

    if (busca.length < 2) {
      codigoBuscaAtual++;

      setState(() {
        produtos = [];
        produtoSelecionado = null;
        erro = null;
        buscandoSugestoes = false;
        listandoTodos = false;
      });

      return;
    }

    debounceBusca = Timer(const Duration(milliseconds: 420), () {
      buscarSugestoesAutomaticas(busca);
    });
  }

  Future<void> buscarSugestoesAutomaticas(String busca) async {
    if (gravando || busca.trim().length < 2) {
      return;
    }

    final codigoExecucao = ++codigoBuscaAtual;

    setState(() {
      buscandoSugestoes = true;
      erro = null;
      produtos = [];
      produtoSelecionado = null;
      listandoTodos = false;
    });

    try {
      final resultado = await buscarProdutosApp(busca.trim());

      if (!mounted || codigoExecucao != codigoBuscaAtual) {
        return;
      }

      if (buscaController.text.trim() != busca.trim()) {
        return;
      }

      setState(() {
        produtos = resultado;
        buscandoSugestoes = false;
      });
    } catch (e) {
      if (!mounted || codigoExecucao != codigoBuscaAtual) {
        return;
      }

      setState(() {
        erro = CentralService.mensagemErroUsuario(e);
        buscandoSugestoes = false;
      });
    }
  }

  Future<void> consultar({
    String? valorBusca,
    bool selecionarAutomaticamente = false,
  }) async {
    final busca = (valorBusca ?? buscaController.text).trim();

    debounceBusca?.cancel();
    codigoBuscaAtual++;
    buscaController.text = busca;

    FocusScope.of(context).unfocus();

    setState(() {
      carregando = true;
      buscandoSugestoes = false;
      erro = null;
      produtos = [];
      produtoSelecionado = null;
      listandoTodos = false;
    });

    try {
      final resultado = await buscarProdutosApp(busca);

      if (!mounted) return;

      if (busca.isNotEmpty && resultado.isEmpty) {
        setState(() {
          produtos = [];
          produtoSelecionado = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto não cadastrado.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final produtoAutomatico =
          selecionarAutomaticamente && resultado.length == 1
          ? resultado.first
          : null;

      setState(() {
        produtos = produtoAutomatico == null ? resultado : [];
        produtoSelecionado = produtoAutomatico;
        if (produtoAutomatico != null) {
          buscaController.text = texto(produtoAutomatico['nome_produto']);
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        erro = CentralService.mensagemErroUsuario(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          carregando = false;
        });
      }
    }
  }

  Future<void> abrirScanner() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          onDetect: (codigo) {
            consultar(valorBusca: codigo, selecionarAutomaticamente: true);
          },
        ),
      ),
    );
  }

  Future<void> listarTodosProdutos() async {
    debounceBusca?.cancel();
    codigoBuscaAtual++;

    FocusScope.of(context).unfocus();

    setState(() {
      carregando = true;
      buscandoSugestoes = false;
      erro = null;
      produtos = [];
      produtoSelecionado = null;
      listandoTodos = true;
      buscaController.clear();
      quantidadeController.clear();
      observacaoController.clear();
    });

    try {
      final resultado = await buscarProdutosApp('');

      if (!mounted) return;

      setState(() {
        produtos = resultado;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        erro = CentralService.mensagemErroUsuario(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          carregando = false;
        });
      }
    }
  }

  void limparBuscaProdutos() {
    debounceBusca?.cancel();
    codigoBuscaAtual++;

    setState(() {
      buscaController.clear();
      produtos = [];
      produtoSelecionado = null;
      erro = null;
      buscandoSugestoes = false;
      listandoTodos = false;
      quantidadeController.clear();
      observacaoController.clear();
    });
  }

  void selecionarProduto(Map<String, dynamic> produto) {
    FocusScope.of(context).unfocus();

    setState(() {
      produtoSelecionado = produto;
      if (!listandoTodos) {
        produtos = [];
      }
      erro = null;
      buscandoSugestoes = false;
      buscaController.text = texto(produto['nome_produto']);
      quantidadeController.clear();
      observacaoController.clear();
    });
  }

  Future<bool> confirmarAlteracaoEstoque({
    required Map<String, dynamic> produto,
    required double estoqueAnterior,
    required double quantidadeInformada,
    required double estoqueNovo,
  }) async {
    final unidade = unidadeProduto(produto);
    final acao = modoEntrada ? 'entrada' : 'correcao';
    final descricaoQuantidade = modoEntrada
        ? 'Entrada: ${quantidade(quantidadeInformada)} $unidade'
        : 'Novo estoque: ${quantidade(estoqueNovo)} $unidade';

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Confirmar $acao'),
        content: Text(
          'Produto: ${texto(produto['nome_produto'])}\n\n'
          'Estoque atual: ${quantidade(estoqueAnterior)} $unidade\n'
          '$descricaoQuantidade\n'
          'Estoque final: ${quantidade(estoqueNovo)} $unidade',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: corMovimentacao,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    return confirmado == true;
  }

  Future<String?> registrarAuditoriaProdutosApp({
    required String tipoMovimentacao,
    required Map<String, dynamic> produto,
    required double estoqueAnterior,
    required double quantidadeInformada,
    required double quantidadeAlterada,
    required double estoqueNovo,
  }) async {
    final mercadoId = mercadoIdAtual();

    if (mercadoId == null) {
      return 'Loja nao identificada para registrar auditoria.';
    }

    final observacao = observacaoController.text.trim();
    final registro = <String, dynamic>{
      'mercado_id': mercadoId,
      'mercado_codigo': SessaoLoja.mercadoCodigo,
      'tipo_movimentacao': tipoMovimentacao,
      'produto_id': texto(produto['produto_id'] ?? produto['id']),
      'ean_principal': eanProduto(produto),
      'nome_produto': texto(produto['nome_produto']),
      'estoque_anterior': estoqueAnterior,
      'quantidade_informada': quantidadeInformada,
      'quantidade_alterada': quantidadeAlterada,
      'estoque_novo': estoqueNovo,
      'unidade': unidadeProduto(produto),
      'observacao': observacao.isEmpty ? null : observacao,
      'usuario_id': SessaoLoja.usuarioId,
      'usuario_nome': SessaoLoja.usuarioNome ?? SessaoLoja.usuarioLogin,
      'usuario_email': SessaoLoja.usuarioEmail ?? SessaoLoja.usuarioLogin,
      'usuario_perfil': SessaoLoja.usuarioPerfil,
      'origem': 'app_preco_produtos_app',
      ...custoAuditoriaProduto(produto),
    };

    final erroFunction = await registrarAuditoriaProdutosAppFunction(registro);

    if (erroFunction == null) {
      return null;
    }

    final supabase = SessaoLoja.supabaseLoja;

    if (supabase == null) {
      return erroFunction;
    }

    try {
      await supabase.from('estoque_auditoria').insert(registro);
      return null;
    } catch (e) {
      return mensagemAmigavelErroAuditoria(e, erroFunction: erroFunction);
    }
  }

  Future<String?> registrarAuditoriaProdutosAppFunction(
    Map<String, dynamic> registro,
  ) async {
    try {
      SessaoLoja.sincronizarSessaoAtual();
      await SessaoLoja.renovarSessaoLojaSePossivel();
      final lojaAccessToken =
          SessaoLoja.supabaseLoja?.auth.currentSession?.accessToken ??
          SessaoLoja.lojaAccessToken;

      final resposta = await Supabase.instance.client.functions.invoke(
        'registrar-estoque-auditoria',
        body: {
          'mercado_id': SessaoLoja.mercadoId,
          'mercado_codigo': SessaoLoja.mercadoCodigo,
          'loja_access_token': lojaAccessToken,
          'registro': registro,
        },
      );

      final data = resposta.data;

      if (data is Map && data['erro'] != null) {
        throw Exception(data['erro'].toString());
      }

      return null;
    } catch (e) {
      return CentralService.mensagemErroUsuario(e);
    }
  }

  String mensagemAmigavelErroAuditoria(Object erro, {String? erroFunction}) {
    final mensagem = erro.toString().replaceFirst('Exception: ', '');
    final textoErro = mensagem.toLowerCase();

    if (textoErro.contains('row-level security') ||
        textoErro.contains('42501') ||
        textoErro.contains('estoque_auditoria')) {
      return 'Auditoria nao gravada por permissao do banco. Faca deploy da function registrar-estoque-auditoria.';
    }

    if (erroFunction != null && erroFunction.trim().isNotEmpty) {
      return erroFunction;
    }

    return CentralService.mensagemErroUsuario(erro);
  }

  Future<void> registrarAlteracaoEstoque() async {
    final produto = produtoSelecionado;

    if (produto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione um produto primeiro'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (modoEntrada && !podeEntrada) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuario sem permissao para entrada de estoque'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!modoEntrada && !podeCorrecao) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuario sem permissao para correcao de estoque'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final quantidadeInformada = lerQuantidadeDigitada(
      quantidadeController.text,
    );

    if (quantidadeInformada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            modoEntrada
                ? 'Informe a quantidade de entrada'
                : 'Informe o novo estoque',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final erroValidacao = validarQuantidade(
      produto: produto,
      quantidadeInformada: quantidadeInformada,
    );

    if (erroValidacao != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erroValidacao), backgroundColor: Colors.red),
      );
      return;
    }

    final estoqueAnterior = numero(produto['estoque']);
    final estoqueNovo = modoEntrada
        ? estoqueAnterior + quantidadeInformada
        : quantidadeInformada;

    final confirmado = await confirmarAlteracaoEstoque(
      produto: produto,
      estoqueAnterior: estoqueAnterior,
      quantidadeInformada: quantidadeInformada,
      estoqueNovo: estoqueNovo,
    );

    if (!confirmado) {
      return;
    }

    if (!mounted) return;

    final mercadoId = mercadoIdAtual();
    final produtoId = texto(produto['id'], fallback: '');

    if (mercadoId == null || produtoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Produto ou loja sem identificador para atualizar'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      gravando = true;
    });

    try {
      final resposta = await centralService.atualizarEstoqueProdutoApp(
        mercadoId: mercadoId,
        mercadoCodigo: SessaoLoja.mercadoCodigo,
        id: produtoId,
        tipoMovimentacao: tipoSelecionado,
        quantidade: quantidadeInformada,
      );

      final produtoAtualizado = resposta['produto'] is Map
          ? Map<String, dynamic>.from(resposta['produto'])
          : {...produto, 'estoque': estoqueNovo};

      final erroAuditoria = await registrarAuditoriaProdutosApp(
        tipoMovimentacao: tipoSelecionado,
        produto: produto,
        estoqueAnterior: estoqueAnterior,
        quantidadeInformada: quantidadeInformada,
        quantidadeAlterada: estoqueNovo - estoqueAnterior,
        estoqueNovo: estoqueNovo,
      );

      if (!mounted) return;

      setState(() {
        produtoSelecionado = produtoAtualizado;
        produtos = produtos
            .map(
              (item) =>
                  texto(item['id']) == produtoId ? produtoAtualizado : item,
            )
            .toList();
        buscaController.text = texto(produtoAtualizado['nome_produto']);
        quantidadeController.clear();
        observacaoController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            erroAuditoria == null
                ? 'Estoque de produtos_app atualizado'
                : 'Estoque atualizado, mas a auditoria nao foi gravada: $erroAuditoria',
          ),
          backgroundColor: erroAuditoria == null ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao atualizar estoque: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          gravando = false;
        });
      }
    }
  }

  Widget topo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.teal.withValues(alpha: 0.14),
            child: const Icon(Icons.storefront, color: Colors.teal, size: 32),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estoque produtos app',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Ajuste o saldo gravado na tabela produtos_app.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget campoBusca() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: buscaController,
            enabled: !carregando && !gravando,
            textInputAction: TextInputAction.search,
            onChanged: agendarBuscaAutomatica,
            onSubmitted: (_) => consultar(),
            decoration: InputDecoration(
              labelText: 'EAN ou descricao do produto',
              hintText: 'Digite nome, codigo ou EAN',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: buscaController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      onPressed: carregando || gravando
                          ? null
                          : limparBuscaProdutos,
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.teal.withValues(alpha: 0.55),
                  width: 1.4,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.teal, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: carregando || gravando ? null : consultar,
                    icon: carregando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search),
                    label: const Text('Consultar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: vermelho,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: carregando || gravando ? null : abrirScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scanner'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: carregando || gravando ? null : listarTodosProdutos,
              icon: const Icon(Icons.table_rows_outlined),
              label: const Text('Listar todos'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.teal,
                side: BorderSide(color: Colors.teal.withValues(alpha: 0.55)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget cardProduto(Map<String, dynamic> produto) {
    final selecionado =
        texto(produtoSelecionado?['id'], fallback: '') ==
        texto(produto['id'], fallback: '');
    final unidade = unidadeProduto(produto);
    final estoque = quantidade(produto['estoque']);
    final ativo = lerBooleanoDinamico(produto['ativo'], padrao: true);
    final controlaEstoque = lerBooleanoDinamico(
      produto['controla_estoque'],
      padrao: true,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selecionado ? Colors.teal.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selecionado
              ? Colors.teal.withValues(alpha: 0.55)
              : Colors.black.withValues(alpha: 0.08),
          width: selecionado ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: selecionado ? 0.06 : 0.025),
            blurRadius: selecionado ? 10 : 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: gravando ? null : () => selecionarProduto(produto),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selecionado
                        ? Colors.teal.withValues(alpha: 0.14)
                        : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    selecionado
                        ? Icons.check_circle
                        : Icons.inventory_2_outlined,
                    color: selecionado ? Colors.teal : Colors.black45,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        texto(produto['nome_produto']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.8,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'EAN: ${eanProduto(produto)} | ${moeda(produto['preco'])}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!ativo || !controlaEstoque) ...[
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (!ativo) 'Inativo',
                            if (!controlaEstoque) 'Nao controla estoque',
                          ].join(' - '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$estoque $unidade',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.teal,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Icon(
                      selecionado
                          ? Icons.keyboard_arrow_down
                          : Icons.chevron_right,
                      color: selecionado ? Colors.teal : Colors.black38,
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget indicadorBuscaAutomatica() {
    if (!buscandoSugestoes) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.18)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Buscando produtos app...',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget listaProdutos() {
    if (produtos.isEmpty) {
      return const SizedBox.shrink();
    }

    if (listandoTodos) {
      return listaProdutosPlanilha();
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              color: const Color(0xFFF9FAFB),
              child: Text(
                produtos.length == 1
                    ? 'Selecione o produto encontrado'
                    : 'Selecione um dos ${produtos.length} produtos encontrados',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                  fontSize: 13,
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.separated(
                padding: const EdgeInsets.all(8),
                shrinkWrap: true,
                itemCount: produtos.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) => cardProduto(produtos[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget celulaPlanilha({
    required String valor,
    required double largura,
    TextAlign alinhamento = TextAlign.left,
    bool destaque = false,
  }) {
    return SizedBox(
      width: largura,
      child: Text(
        valor,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: alinhamento,
        style: TextStyle(
          color: destaque ? const Color(0xFF0F766E) : const Color(0xFF1F2937),
          fontSize: 12,
          fontWeight: destaque ? FontWeight.w900 : FontWeight.w600,
        ),
      ),
    );
  }

  Widget espacoColunaPlanilha() {
    return const SizedBox(width: 6);
  }

  Widget linhaPlanilhaProduto(Map<String, dynamic> produto, int index) {
    final selecionado =
        texto(produtoSelecionado?['id'], fallback: '') ==
        texto(produto['id'], fallback: '');
    final ativo = lerBooleanoDinamico(produto['ativo'], padrao: true);
    final controlaEstoque = lerBooleanoDinamico(
      produto['controla_estoque'],
      padrao: true,
    );
    final status = !ativo
        ? 'Inativo'
        : !controlaEstoque
        ? 'Sem controle'
        : 'Ativo';

    return Material(
      color: selecionado ? Colors.teal.withValues(alpha: 0.08) : Colors.white,
      child: InkWell(
        onTap: gravando ? null : () => selecionarProduto(produto),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
              left: BorderSide(
                color: selecionado ? Colors.teal : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              celulaPlanilha(
                valor: (index + 1).toString(),
                largura: 30,
                alinhamento: TextAlign.center,
                destaque: selecionado,
              ),
              espacoColunaPlanilha(),
              celulaPlanilha(
                valor: texto(produto['nome_produto']),
                largura: 118,
                destaque: selecionado,
              ),
              espacoColunaPlanilha(),
              celulaPlanilha(
                valor: quantidade(produto['estoque']),
                largura: 54,
                alinhamento: TextAlign.right,
                destaque: selecionado,
              ),
              espacoColunaPlanilha(),
              celulaPlanilha(
                valor: unidadeProduto(produto),
                largura: 34,
                alinhamento: TextAlign.center,
                destaque: selecionado,
              ),
              espacoColunaPlanilha(),
              celulaPlanilha(
                valor: moeda(produto['preco']),
                largura: 76,
                alinhamento: TextAlign.right,
                destaque: selecionado,
              ),
              espacoColunaPlanilha(),
              celulaPlanilha(
                valor: eanProduto(produto),
                largura: 104,
                destaque: selecionado,
              ),
              espacoColunaPlanilha(),
              celulaPlanilha(valor: status, largura: 76, destaque: selecionado),
            ],
          ),
        ),
      ),
    );
  }

  Widget cabecalhoPlanilha() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.10),
        border: Border(
          bottom: BorderSide(color: Colors.teal.withValues(alpha: 0.25)),
        ),
      ),
      child: Row(
        children: [
          celulaPlanilha(
            valor: '#',
            largura: 30,
            alinhamento: TextAlign.center,
            destaque: true,
          ),
          espacoColunaPlanilha(),
          celulaPlanilha(valor: 'Produto', largura: 118, destaque: true),
          espacoColunaPlanilha(),
          celulaPlanilha(
            valor: 'Estoque',
            largura: 54,
            alinhamento: TextAlign.right,
            destaque: true,
          ),
          espacoColunaPlanilha(),
          celulaPlanilha(
            valor: 'UN',
            largura: 34,
            alinhamento: TextAlign.center,
            destaque: true,
          ),
          espacoColunaPlanilha(),
          celulaPlanilha(
            valor: 'Preco',
            largura: 76,
            alinhamento: TextAlign.right,
            destaque: true,
          ),
          espacoColunaPlanilha(),
          celulaPlanilha(valor: 'EAN', largura: 104, destaque: true),
          espacoColunaPlanilha(),
          celulaPlanilha(valor: 'Status', largura: 76, destaque: true),
        ],
      ),
    );
  }

  Widget listaProdutosPlanilha() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              color: const Color(0xFFF9FAFB),
              child: Text(
                'Produtos app (${produtos.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                  fontSize: 13,
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final larguraTabela = constraints.maxWidth;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: larguraTabela),
                    child: Column(
                      children: [
                        cabecalhoPlanilha(),
                        ...produtos.asMap().entries.map(
                          (entry) =>
                              linhaPlanilhaProduto(entry.value, entry.key),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget botaoModo({
    required String tipo,
    required String titulo,
    required IconData icone,
    required bool habilitado,
  }) {
    final selecionado = tipoSelecionado == tipo;
    final cor = tipo == 'ENTRADA' ? Colors.green : Colors.blue;

    return Expanded(
      child: SizedBox(
        height: 46,
        child: OutlinedButton.icon(
          onPressed: !habilitado || gravando
              ? null
              : () {
                  setState(() {
                    tipoSelecionado = tipo;
                    quantidadeController.clear();
                  });
                },
          icon: Icon(icone, size: 18),
          label: Text(titulo, overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(
            backgroundColor: selecionado
                ? cor.withValues(alpha: 0.10)
                : Colors.white,
            foregroundColor: selecionado ? cor : Colors.black54,
            side: BorderSide(
              color: selecionado
                  ? cor.withValues(alpha: 0.70)
                  : Colors.black.withValues(alpha: 0.12),
              width: selecionado ? 1.4 : 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  Widget seletorTipoMovimentacao() {
    return Row(
      children: [
        botaoModo(
          tipo: 'ENTRADA',
          titulo: 'Entrada',
          icone: Icons.add_box,
          habilitado: podeEntrada,
        ),
        const SizedBox(width: 10),
        botaoModo(
          tipo: 'CORRECAO',
          titulo: 'Correcao',
          icone: Icons.edit_note,
          habilitado: podeCorrecao,
        ),
      ],
    );
  }

  Widget painelProdutoSelecionado() {
    final produto = produtoSelecionado;

    if (produto == null) {
      return Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.teal.withValues(alpha: 0.22)),
        ),
        child: const Row(
          children: [
            Icon(Icons.touch_app, color: Colors.teal),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Consulte ou escaneie um produto da tabela produtos_app.',
                style: TextStyle(color: Colors.black87),
              ),
            ),
          ],
        ),
      );
    }

    final unidade = unidadeProduto(produto);
    final estoqueAtual = quantidade(produto['estoque']);
    final fracionado = permiteQuantidadeFracionada(produto);

    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: corMovimentacao.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storefront, color: corMovimentacao),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Produto selecionado',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          cardProduto(produto),
          const SizedBox(height: 10),
          seletorTipoMovimentacao(),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Estoque atual',
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              '$estoqueAtual $unidade',
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: quantidadeController,
            enabled: !gravando,
            keyboardType: tipoTecladoQuantidade(produto),
            inputFormatters: formatadoresQuantidade(produto),
            decoration: InputDecoration(
              labelText: modoEntrada
                  ? 'Quantidade de entrada'
                  : 'Novo estoque correto',
              hintText: fracionado ? 'Ex: 1,500' : 'Ex: 10',
              helperText: fracionado
                  ? 'Unidade $unidade aceita quantidade fracionada.'
                  : 'Unidade $unidade aceita apenas numero inteiro.',
              prefixIcon: Icon(modoEntrada ? Icons.add : Icons.edit),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: observacaoController,
            enabled: !gravando,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Observacao',
              hintText: 'Opcional',
              prefixIcon: const Icon(Icons.notes),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: gravando ? null : registrarAlteracaoEstoque,
              icon: gravando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle),
              label: Text(
                modoEntrada ? 'Registrar entrada' : 'Registrar correcao',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: corMovimentacao,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget corpoResultado() {
    if (carregando) {
      return const Padding(
        padding: EdgeInsets.only(top: 30),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (erro != null) {
      return Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withValues(alpha: 0.22)),
        ),
        child: Text(
          erro!,
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    if (listandoTodos && produtos.isEmpty && produtoSelecionado == null) {
      return Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: const Text(
          'Nenhum produto_app cadastrado para esta loja.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    if (produtos.isEmpty &&
        produtoSelecionado == null &&
        buscaController.text.trim().isNotEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: const Text(
          'Nenhum produto_app encontrado para a busca.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget acessoNegado() {
    return Scaffold(
      backgroundColor: fundo,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Estoque produtos app'),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 46, color: Colors.black38),
                SizedBox(height: 12),
                Text(
                  'Acesso nao permitido',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Seu usuario nao tem permissao de entrada ou correcao de estoque.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!temAcesso) {
      return acessoNegado();
    }

    return Scaffold(
      backgroundColor: fundo,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Estoque produtos app'),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          topo(),
          const SizedBox(height: 16),
          campoBusca(),
          indicadorBuscaAutomatica(),
          listaProdutos(),
          corpoResultado(),
          painelProdutoSelecionado(),
        ],
      ),
    );
  }
}

class ConsultaEstoquePage extends StatefulWidget {
  final String titulo;
  final String subtitulo;
  final String tipo;
  final String permissao;
  final bool ignorarPermissao;
  final Color cor;
  final IconData icone;

  const ConsultaEstoquePage({
    super.key,
    required this.titulo,
    required this.subtitulo,
    required this.tipo,
    required this.permissao,
    this.ignorarPermissao = false,
    required this.cor,
    required this.icone,
  });

  @override
  State<ConsultaEstoquePage> createState() => _ConsultaEstoquePageState();
}

class _ConsultaEstoquePageState extends State<ConsultaEstoquePage> {
  final CentralService centralService = CentralService();

  final buscaController = TextEditingController();
  final quantidadeEntradaController = TextEditingController();
  final novaQuantidadeController = TextEditingController();
  final quantidadeConsumoController = TextEditingController();
  final quantidadeBaixaController = TextEditingController();
  final observacaoController = TextEditingController();

  Timer? debounceBusca;
  int codigoBuscaAtual = 0;

  bool carregando = false;
  bool buscandoSugestoes = false;
  bool gravando = false;
  bool carregandoTokenEstoque = false;
  bool estoqueUpdateTokenAtivo = false;
  bool estoqueDetalhadoAtivo = false;
  bool carregandoMotivosConsumo = false;
  bool salvandoMotivoConsumo = false;

  String estoqueUpdateToken = '';
  String? erro;
  String motivoSelecionado = 'Padaria';

  List<Map<String, dynamic>> produtos = [];
  Map<String, dynamic>? produtoSelecionado;
  List<Map<String, dynamic>> locaisEstoque = [];
  Map<String, dynamic>? localEstoqueSelecionado;
  bool carregandoLocaisEstoque = false;
  String? erroLocaisEstoque;
  int codigoLocaisEstoqueAtual = 0;

  static Color get vermelho => SessaoLoja.corPrimaria;
  static Color get fundo => SessaoLoja.corFundo;

  static const List<String> motivosConsumoPadrao = [
    'Padaria',
    'Limpeza',
    'Açougue',
    'Despesa',
  ];
  List<String> motivosConsumo = List<String>.from(motivosConsumoPadrao);

  @override
  void initState() {
    super.initState();
    carregarTokenUpdateEstoque();
    if (widget.tipo == 'CONSUMO_INTERNO') {
      unawaited(carregarMotivosConsumoInterno());
    }
  }

  String chaveMotivoConsumo(String valor) {
    return valor
        .trim()
        .toLowerCase()
        .replaceAll(RegExp('[áàâãä]'), 'a')
        .replaceAll(RegExp('[éèêë]'), 'e')
        .replaceAll(RegExp('[íìîï]'), 'i')
        .replaceAll(RegExp('[óòôõö]'), 'o')
        .replaceAll(RegExp('[úùûü]'), 'u')
        .replaceAll('ç', 'c');
  }

  List<String> combinarMotivosConsumo(Iterable<String> personalizados) {
    final motivos = <String>[];
    final chaves = <String>{};

    for (final motivo in [...motivosConsumoPadrao, ...personalizados]) {
      final nome = motivo.trim();
      final chave = chaveMotivoConsumo(nome);

      if (nome.isEmpty || chave.isEmpty || chaves.contains(chave)) {
        continue;
      }

      motivos.add(nome);
      chaves.add(chave);
    }

    return motivos;
  }

  Future<void> carregarMotivosConsumoInterno() async {
    final mercadoId = SessaoLoja.mercadoId?.trim();

    if (mercadoId == null || mercadoId.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        carregandoMotivosConsumo = true;
      });
    }

    try {
      final personalizados = await centralService.listarMotivosConsumoInterno(
        mercadoId: mercadoId,
      );
      final motivosAtualizados = combinarMotivosConsumo(personalizados);

      if (!mounted) return;

      setState(() {
        motivosConsumo = motivosAtualizados;
        if (!motivosConsumo.contains(motivoSelecionado)) {
          motivoSelecionado = motivosConsumo.first;
        }
        carregandoMotivosConsumo = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        motivosConsumo = combinarMotivosConsumo(const []);
        carregandoMotivosConsumo = false;
      });
    }
  }

  Future<void> cadastrarNovoMotivoConsumo() async {
    if (!SessaoLoja.usuarioAdminLoja || salvandoMotivoConsumo) {
      return;
    }

    final nome = await showDialog<String>(
      context: context,
      builder: (_) => const _CadastrarMotivoConsumoDialog(),
    );

    if (!mounted || nome == null || nome.trim().isEmpty) {
      return;
    }

    final mercadoId = SessaoLoja.mercadoId?.trim();

    if (mercadoId == null || mercadoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível identificar a loja.')),
      );
      return;
    }

    setState(() {
      salvandoMotivoConsumo = true;
    });

    try {
      final motivoCadastrado = await centralService
          .cadastrarMotivoConsumoInterno(mercadoId: mercadoId, nome: nome);

      if (!mounted) return;

      setState(() {
        motivosConsumo = combinarMotivosConsumo([
          ...motivosConsumo,
          motivoCadastrado,
        ]);
        motivoSelecionado = motivosConsumo.firstWhere(
          (motivo) =>
              chaveMotivoConsumo(motivo) ==
              chaveMotivoConsumo(motivoCadastrado),
          orElse: () => motivoSelecionado,
        );
        salvandoMotivoConsumo = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Motivo "$motivoCadastrado" cadastrado.')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        salvandoMotivoConsumo = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CentralService.mensagemErroUsuario(e))),
      );
    }
  }

  Future<void> carregarTokenUpdateEstoque() async {
    final mercadoId = SessaoLoja.mercadoId;

    if (mercadoId == null || mercadoId.trim().isEmpty) {
      return;
    }

    setState(() {
      carregandoTokenEstoque = true;
    });

    try {
      final conexao = await centralService.buscarConexaoMercado(mercadoId);

      if (!mounted) return;

      setState(() {
        estoqueUpdateToken =
            conexao['estoque_update_token']?.toString().trim() ?? '';

        estoqueUpdateTokenAtivo = lerBooleanoDinamico(
          conexao['estoque_update_token_ativo'],
          padrao: false,
        );

        estoqueDetalhadoAtivo = lerBooleanoDinamico(
          conexao['estoque_detalhado_ativo'],
          padrao: false,
        );

        carregandoTokenEstoque = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        estoqueUpdateToken = '';
        estoqueUpdateTokenAtivo = false;
        estoqueDetalhadoAtivo = false;
        carregandoTokenEstoque = false;
      });
    }
  }

  @override
  void dispose() {
    debounceBusca?.cancel();
    buscaController.dispose();
    quantidadeEntradaController.dispose();
    novaQuantidadeController.dispose();
    quantidadeConsumoController.dispose();
    quantidadeBaixaController.dispose();
    observacaoController.dispose();
    super.dispose();
  }

  String somenteNumeros(String valor) {
    return valor.replaceAll(RegExp(r'\D'), '');
  }

  String normalizarEan(String valor) {
    final numeros = somenteNumeros(valor);

    if (numeros.isEmpty) {
      return '';
    }

    if (numeros.length < 14) {
      return numeros.padLeft(14, '0');
    }

    return numeros;
  }

  String baseUrlApi() {
    final apiBaseUrl = SessaoLoja.apiBaseUrl;

    if (apiBaseUrl == null || apiBaseUrl.trim().isEmpty) {
      throw Exception('API da loja não configurada.');
    }

    return apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  }

  bool get usarEstoqueDetalhadoPorLocal {
    return estoqueDetalhadoAtivo &&
        (widget.tipo == 'ENTRADA' ||
            widget.tipo == 'CORRECAO' ||
            widget.tipo == 'CONSUMO_INTERNO' ||
            widget.tipo == 'BAIXA_AVARIA' ||
            widget.tipo == 'BAIXA_VALIDADE');
  }

  bool get tipoBaixaEstoque {
    return widget.tipo == 'BAIXA_AVARIA' || widget.tipo == 'BAIXA_VALIDADE';
  }

  String get nomeBaixaEstoque {
    if (widget.tipo == 'BAIXA_AVARIA') {
      return 'Baixa por avaria';
    }

    if (widget.tipo == 'BAIXA_VALIDADE') {
      return 'Baixa por validade';
    }

    return 'Baixa de estoque';
  }

  int? inteiro(dynamic valor) {
    if (valor == null) {
      return null;
    }

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    return int.tryParse(valor.toString().trim());
  }

  double numeroDinamico(dynamic valor) {
    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  int? idLocalEstoque(Map<String, dynamic> local) {
    return inteiro(local['local_estoqueid'] ?? local['local_estoque_id']);
  }

  String nomeLocalEstoque(Map<String, dynamic> local) {
    final id = idLocalEstoque(local);
    final nome = local['nome_local_estoque'] ?? local['nome'];
    final textoNome = texto(nome);

    if (textoNome != '-') {
      return textoNome;
    }

    return id == null ? 'Local de estoque' : 'Local $id';
  }

  double quantidadeLocalEstoque(Map<String, dynamic> local) {
    return numeroDinamico(local['quantidade']);
  }

  bool localConsideradoNoApp(Map<String, dynamic> local) {
    return lerBooleanoDinamico(local['considerado_no_app'], padrao: true);
  }

  double estoqueAtualMovimentacao(Map<String, dynamic> produto) {
    final local = localEstoqueSelecionado;

    if (usarEstoqueDetalhadoPorLocal && local != null) {
      return quantidadeLocalEstoque(local);
    }

    return numeroEstoqueProduto(produto);
  }

  String? chaveLocalEstoque(Map<String, dynamic>? local) {
    final id = local == null ? null : idLocalEstoque(local);
    return id?.toString();
  }

  List<Map<String, dynamic>> extrairLocaisEstoque(dynamic data) {
    if (data is Map && data['locais'] is List) {
      return List<Map<String, dynamic>>.from(data['locais']);
    }

    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    return [];
  }

  void limparEstadoLocaisEstoque() {
    codigoLocaisEstoqueAtual++;
    locaisEstoque = [];
    localEstoqueSelecionado = null;
    carregandoLocaisEstoque = false;
    erroLocaisEstoque = null;
  }

  Uri uriLocaisEstoqueProduto(Map<String, dynamic> produto) {
    final api = baseUrlApi();
    final produtoId = produto['produto_id']?.toString().trim();

    if (produtoId != null && produtoId.isNotEmpty) {
      return Uri.parse(
        '$api/produto/${Uri.encodeComponent(produtoId)}/estoque-locais',
      );
    }

    final ean = produto['ean_principal']?.toString().trim();

    if (ean == null || ean.isEmpty) {
      throw Exception('Produto sem produto_id ou EAN para consultar locais.');
    }

    return Uri.parse(
      '$api/produto/ean/${Uri.encodeComponent(ean)}/estoque-locais',
    );
  }

  Future<void> carregarLocaisEstoqueProduto(
    Map<String, dynamic> produto,
  ) async {
    if (!usarEstoqueDetalhadoPorLocal) {
      return;
    }

    final codigoExecucao = ++codigoLocaisEstoqueAtual;

    setState(() {
      carregandoLocaisEstoque = true;
      erroLocaisEstoque = null;
      locaisEstoque = [];
      localEstoqueSelecionado = null;
    });

    try {
      final resposta = await http
          .get(uriLocaisEstoqueProduto(produto))
          .timeout(const Duration(seconds: 20));

      dynamic data;

      try {
        data = jsonDecode(resposta.body);
      } catch (_) {
        data = null;
      }

      if (resposta.statusCode == 404) {
        throw Exception(
          'Nenhum local de estoque encontrado para este produto.',
        );
      }

      if (resposta.statusCode != 200) {
        final mensagemErro = data is Map && data['erro'] != null
            ? data['erro'].toString()
            : resposta.body;

        throw Exception(
          'Erro ${resposta.statusCode} ao consultar locais: $mensagemErro',
        );
      }

      final locais = extrairLocaisEstoque(
        data,
      ).where(localConsideradoNoApp).toList();
      final localPadrao = locais.length == 1 ? locais.first : null;

      if (!mounted || codigoExecucao != codigoLocaisEstoqueAtual) {
        return;
      }

      setState(() {
        locaisEstoque = locais;
        localEstoqueSelecionado = localPadrao;
        carregandoLocaisEstoque = false;
        erroLocaisEstoque = null;
      });
    } catch (e) {
      if (!mounted || codigoExecucao != codigoLocaisEstoqueAtual) {
        return;
      }

      setState(() {
        carregandoLocaisEstoque = false;
        erroLocaisEstoque = CentralService.mensagemErroUsuario(e);
      });
    }
  }

  void selecionarProdutoParaEstoque(Map<String, dynamic> produto) {
    FocusScope.of(context).unfocus();

    setState(() {
      produtoSelecionado = produto;
      erro = null;
      buscandoSugestoes = false;
      buscaController.text = texto(produto['nome_produto']);
      quantidadeEntradaController.clear();
      novaQuantidadeController.clear();
      quantidadeConsumoController.clear();
      observacaoController.clear();
      limparEstadoLocaisEstoque();
    });

    unawaited(carregarLocaisEstoqueProduto(produto));
  }

  List<Map<String, dynamic>> extrairProdutos(dynamic data) {
    if (data == null) {
      return [];
    }

    if (data is List) {
      return data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (data is Map) {
      if (data['erro'] != null) {
        throw Exception(data['erro'].toString());
      }

      if (data['produtos'] is List) {
        return List<Map<String, dynamic>>.from(data['produtos']);
      }

      if (data['produto'] is Map) {
        return [Map<String, dynamic>.from(data['produto'])];
      }

      if (data['data'] is List) {
        return List<Map<String, dynamic>>.from(data['data']);
      }

      if (data['resultado'] is List) {
        return List<Map<String, dynamic>>.from(data['resultado']);
      }

      if (data['produto_id'] != null) {
        return [Map<String, dynamic>.from(data)];
      }
    }

    return [];
  }

  Future<List<Map<String, dynamic>>> buscarNaApi(String busca) async {
    final api = baseUrlApi();
    final numeros = somenteNumeros(busca);

    final urls = <Uri>[];

    if (numeros.isNotEmpty) {
      final eanNormalizado = normalizarEan(busca);

      urls.add(Uri.parse('$api/produto/ean/$eanNormalizado'));
    }

    urls.add(
      Uri.parse('$api/produto').replace(queryParameters: {'busca': busca}),
    );

    for (final uri in urls) {
      final resposta = await http.get(uri).timeout(const Duration(seconds: 20));

      if (resposta.statusCode == 404) {
        continue;
      }

      if (resposta.statusCode != 200) {
        throw Exception('Erro na API ${resposta.statusCode}: ${resposta.body}');
      }

      final data = jsonDecode(resposta.body);
      final lista = extrairProdutos(data);

      if (lista.isNotEmpty) {
        return lista;
      }
    }

    return [];
  }

  void agendarBuscaAutomatica(String valor) {
    debounceBusca?.cancel();

    final busca = valor.trim();

    if (busca.length < 3) {
      codigoBuscaAtual++;

      setState(() {
        produtos = [];
        produtoSelecionado = null;
        erro = null;
        buscandoSugestoes = false;
        limparEstadoLocaisEstoque();
      });

      return;
    }

    debounceBusca = Timer(const Duration(milliseconds: 450), () {
      buscarSugestoesAutomaticas(busca);
    });
  }

  Future<void> buscarSugestoesAutomaticas(String busca) async {
    final buscaAtual = busca.trim();

    if (buscaAtual.length < 3 || gravando) {
      return;
    }

    final codigoExecucao = ++codigoBuscaAtual;

    setState(() {
      buscandoSugestoes = true;
      erro = null;
      produtos = [];
      produtoSelecionado = null;
      limparEstadoLocaisEstoque();
    });

    try {
      final resultado = await buscarNaApi(buscaAtual);

      if (!mounted || codigoExecucao != codigoBuscaAtual) {
        return;
      }

      if (buscaController.text.trim() != buscaAtual) {
        return;
      }

      setState(() {
        produtos = resultado;
        produtoSelecionado = null;
        buscandoSugestoes = false;
      });
    } catch (e) {
      if (!mounted || codigoExecucao != codigoBuscaAtual) {
        return;
      }

      setState(() {
        erro = CentralService.mensagemErroUsuario(e);
        buscandoSugestoes = false;
      });
    }
  }

  void limparBuscaProdutos() {
    debounceBusca?.cancel();
    codigoBuscaAtual++;

    setState(() {
      buscaController.clear();
      produtos = [];
      produtoSelecionado = null;
      erro = null;
      buscandoSugestoes = false;
      limparEstadoLocaisEstoque();
    });
  }

  void fecharPainelProdutoSelecionado() {
    if (produtoSelecionado == null || gravando) {
      return;
    }

    FocusScope.of(context).unfocus();
    debounceBusca?.cancel();
    codigoBuscaAtual++;

    setState(() {
      buscaController.clear();
      produtos = [];
      produtoSelecionado = null;
      erro = null;
      buscandoSugestoes = false;
      quantidadeEntradaController.clear();
      novaQuantidadeController.clear();
      quantidadeConsumoController.clear();
      quantidadeBaixaController.clear();
      observacaoController.clear();
      limparEstadoLocaisEstoque();
    });
  }

  Future<void> consultar({
    String? valorBusca,
    bool selecionarAutomaticamente = false,
  }) async {
    final busca = (valorBusca ?? buscaController.text).trim();

    if (busca.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Digite ou escaneie o EAN do produto'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    debounceBusca?.cancel();
    codigoBuscaAtual++;
    buscaController.text = busca;

    FocusScope.of(context).unfocus();

    setState(() {
      carregando = true;
      buscandoSugestoes = false;
      erro = null;
      produtos = [];
      produtoSelecionado = null;
      limparEstadoLocaisEstoque();
    });

    try {
      final resultado = await buscarNaApi(busca);

      if (!mounted) return;

      if (resultado.isEmpty) {
        setState(() {
          produtos = [];
          produtoSelecionado = null;
          limparEstadoLocaisEstoque();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produto não cadastrado.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final produtoAutomatico =
          selecionarAutomaticamente && resultado.length == 1
          ? resultado.first
          : null;

      setState(() {
        produtos = resultado;
        produtoSelecionado = produtoAutomatico;
        limparEstadoLocaisEstoque();
      });

      if (produtoAutomatico != null) {
        unawaited(carregarLocaisEstoqueProduto(produtoAutomatico));
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        erro = CentralService.mensagemErroUsuario(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          carregando = false;
        });
      }
    }
  }

  Future<void> abrirScanner() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          onDetect: (codigo) {
            consultar(valorBusca: codigo, selecionarAutomaticamente: true);
          },
        ),
      ),
    );
  }

  Future<void> registrarConsumoInterno() async {
    final produto = produtoSelecionado;

    if (produto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione um produto primeiro'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final quantidadeConsumo = lerQuantidadeDigitada(
      quantidadeConsumoController.text,
    );

    if (quantidadeConsumo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe a quantidade do consumo interno'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final erroValidacao = validarQuantidadeProduto(
      produto: produto,
      quantidadeInformada: quantidadeConsumo,
      permitirZero: false,
    );

    if (erroValidacao != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erroValidacao), backgroundColor: Colors.red),
      );
      return;
    }

    final localEstoque = usarEstoqueDetalhadoPorLocal
        ? localEstoqueSelecionado
        : null;

    if (usarEstoqueDetalhadoPorLocal && localEstoque == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione o local de estoque'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final estoqueAtual = localEstoque == null
        ? numeroEstoqueProduto(produto)
        : quantidadeLocalEstoque(localEstoque);
    final unidade = unidadeProduto(produto);

    if (quantidadeConsumo > estoqueAtual) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Quantidade maior que o estoque atual (${quantidade(estoqueAtual)} $unidade).',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final mercadoId = SessaoLoja.mercadoId;

    if (mercadoId == null || mercadoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mercado não selecionado'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final produtoId = produto['produto_id'];

    if (produtoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Produto sem produto_id'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar consumo interno'),
        content: Text(
          'Confirmar uso interno do produto?\n\n'
          '${texto(produto['nome_produto'])}\n\n'
          '${localEstoque == null ? '' : 'Local: ${nomeLocalEstoque(localEstoque)}\n'}'
          'Quantidade: ${quantidade(quantidadeConsumo)} $unidade\n'
          'Estoque atual: ${quantidade(estoqueAtual)} $unidade\n'
          'Motivo: $motivoSelecionado',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.cor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmar != true) {
      return;
    }

    setState(() {
      gravando = true;
    });

    try {
      final novoEstoque = estoqueAtual - quantidadeConsumo;
      await atualizarEstoqueNaApi(
        produto: produto,
        novaQuantidade: novoEstoque,
        localEstoque: localEstoque,
      );

      final observacaoDigitada = observacaoController.text.trim();
      final observacaoAuditoria = observacaoDigitada.isEmpty
          ? 'Motivo: $motivoSelecionado'
          : 'Motivo: $motivoSelecionado | $observacaoDigitada';
      final erroAuditoria = await registrarAuditoriaEstoque(
        tipoMovimentacao: 'CONSUMO_INTERNO',
        produto: produto,
        estoqueAnterior: estoqueAtual,
        quantidadeInformada: quantidadeConsumo,
        quantidadeAlterada: -quantidadeConsumo,
        estoqueNovo: novoEstoque,
        unidade: unidade,
        localEstoque: localEstoque,
        observacaoOverride: observacaoAuditoria,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            erroAuditoria == null
                ? 'Consumo interno registrado e estoque atualizado'
                : 'Estoque atualizado, mas a auditoria nao foi gravada: $erroAuditoria',
          ),
          backgroundColor: erroAuditoria == null ? Colors.green : Colors.orange,
        ),
      );

      setState(() {
        quantidadeConsumoController.clear();
        observacaoController.clear();
        produtoSelecionado = null;
        produtos = [];
        buscandoSugestoes = false;
        buscaController.clear();
        debounceBusca?.cancel();
        codigoBuscaAtual++;
        limparEstadoLocaisEstoque();
      });
    } catch (e) {
      if (!mounted) return;

      final mensagemErro = CentralService.mensagemErroUsuario(e);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao registrar consumo interno: $mensagemErro'),
          backgroundColor: Colors.red,
        ),
      );
    }

    if (!mounted) return;

    setState(() {
      gravando = false;
    });
  }

  String texto(dynamic valor) {
    if (valor == null) {
      return '-';
    }

    final texto = valor.toString();

    if (texto.trim().isEmpty) {
      return '-';
    }

    return texto;
  }

  String moeda(dynamic valor) {
    final numero = double.tryParse(valor?.toString() ?? '');

    if (numero == null) {
      return '-';
    }

    return 'R\$ ${numero.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  double numeroValor(dynamic valor) {
    if (valor == null) return 0;
    if (valor is num) return valor.toDouble();

    var textoValor = valor.toString().trim();
    if (textoValor.isEmpty) return 0;

    textoValor = textoValor.replaceAll('R\$', '').trim();
    if (textoValor.contains(',')) {
      textoValor = textoValor.replaceAll('.', '').replaceAll(',', '.');
    }

    return double.tryParse(textoValor) ?? 0;
  }

  double custoProduto(Map<String, dynamic> produto) {
    for (final campo in [
      'preco_custo',
      'custo_unitario',
      'preco_compra',
      'custo_liquido',
      'custo',
      'valor_custo',
    ]) {
      final valor = numeroValor(produto[campo]);
      if (valor > 0) return valor;
    }
    return 0;
  }

  Map<String, dynamic> custoAuditoriaProduto(Map<String, dynamic> produto) {
    final custo = custoProduto(produto);
    if (custo <= 0) return {};
    return {'preco_custo': custo, 'custo_unitario': custo};
  }

  String quantidade(dynamic valor) {
    final numero = double.tryParse(valor?.toString() ?? '');

    if (numero == null) {
      return '0';
    }

    if (numero == numero.roundToDouble()) {
      return numero.toStringAsFixed(0);
    }

    return numero.toStringAsFixed(3).replaceAll('.', ',');
  }

  dynamic estoqueProduto(Map<String, dynamic> produto) {
    return produto['estoque_atual'] ??
        produto['quantidade'] ??
        produto['estoque'] ??
        produto['saldo'] ??
        0;
  }

  double numeroEstoqueProduto(Map<String, dynamic> produto) {
    final valor = estoqueProduto(produto);

    return double.tryParse(valor?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  String unidadeProduto(Map<String, dynamic> produto) {
    return texto(produto['sigla_saida']).trim().toUpperCase();
  }

  bool permiteQuantidadeFracionada(Map<String, dynamic> produto) {
    final unidade = unidadeProduto(produto);

    return unidade == 'KG';
  }

  TextInputType tipoTecladoQuantidade(Map<String, dynamic> produto) {
    if (permiteQuantidadeFracionada(produto)) {
      return const TextInputType.numberWithOptions(decimal: true);
    }

    return TextInputType.number;
  }

  List<TextInputFormatter> formatadoresQuantidade(
    Map<String, dynamic> produto,
  ) {
    if (permiteQuantidadeFracionada(produto)) {
      return [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))];
    }

    return [FilteringTextInputFormatter.digitsOnly];
  }

  double? lerQuantidadeDigitada(String valor) {
    final textoValor = valor.trim().replaceAll(',', '.');

    if (textoValor.isEmpty) {
      return null;
    }

    return double.tryParse(textoValor);
  }

  String? validarQuantidadeProduto({
    required Map<String, dynamic> produto,
    required double quantidadeInformada,
    required bool permitirZero,
  }) {
    if (quantidadeInformada < 0) {
      return 'A quantidade não pode ser negativa.';
    }

    if (!permitirZero && quantidadeInformada <= 0) {
      return 'Informe uma quantidade maior que zero.';
    }

    if (!permiteQuantidadeFracionada(produto) &&
        quantidadeInformada != quantidadeInformada.roundToDouble()) {
      return 'Este produto está em ${unidadeProduto(produto)}. Informe apenas número inteiro.';
    }

    return null;
  }

  Map<String, String> headersUpdateEstoque() {
    final headers = <String, String>{'Content-Type': 'application/json'};

    if (estoqueUpdateToken.trim().isNotEmpty) {
      headers['x-api-key'] = estoqueUpdateToken.trim();
    }

    return headers;
  }

  Future<Map<String, dynamic>> atualizarEstoqueNaApi({
    required Map<String, dynamic> produto,
    required double novaQuantidade,
    Map<String, dynamic>? localEstoque,
  }) async {
    final produtoId = produto['produto_id'];

    if (produtoId == null) {
      throw Exception('Produto sem produto_id.');
    }

    if (estoqueUpdateTokenAtivo && estoqueUpdateToken.trim().isEmpty) {
      throw Exception(
        'Token de update de estoque não carregado. Verifique a configuração do mercado na Central.',
      );
    }

    final api = baseUrlApi();
    final body = <String, dynamic>{'quantidade': novaQuantidade};
    final localEstoqueId = localEstoque == null
        ? null
        : idLocalEstoque(localEstoque);

    if (localEstoque != null && localEstoqueId == null) {
      throw Exception('Local de estoque sem identificador.');
    }

    if (localEstoqueId != null) {
      body['local_estoqueid'] = localEstoqueId;
    }

    final resposta = await http
        .patch(
          Uri.parse('$api/produto/$produtoId/estoque'),
          headers: headersUpdateEstoque(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    dynamic data;

    try {
      data = jsonDecode(resposta.body);
    } catch (_) {
      data = null;
    }

    if (resposta.statusCode < 200 || resposta.statusCode >= 300) {
      if (data is Map && data['erro'] != null) {
        throw Exception(data['erro'].toString());
      }

      throw Exception(
        'Erro ${resposta.statusCode} ao atualizar estoque: ${resposta.body}',
      );
    }

    if (data is Map && data['erro'] != null) {
      throw Exception(data['erro'].toString());
    }

    if (data is Map && data['produto'] is Map) {
      return Map<String, dynamic>.from(data['produto']);
    }

    return {...produto, 'estoque_atual': novaQuantidade};
  }

  Future<String?> registrarAuditoriaEstoque({
    required String tipoMovimentacao,
    required Map<String, dynamic> produto,
    required double estoqueAnterior,
    required double quantidadeInformada,
    required double quantidadeAlterada,
    required double estoqueNovo,
    required String unidade,
    Map<String, dynamic>? localEstoque,
    String? observacaoOverride,
  }) async {
    final supabase = SessaoLoja.supabaseLoja;

    if (supabase == null) {
      return 'Supabase da loja nao configurado para registrar auditoria.';
    }

    final observacao = observacaoOverride?.trim().isNotEmpty == true
        ? observacaoOverride!.trim()
        : observacaoController.text.trim();

    final registro = <String, dynamic>{
      'mercado_id': SessaoLoja.mercadoId,
      'mercado_codigo': SessaoLoja.mercadoCodigo,
      'tipo_movimentacao': tipoMovimentacao,
      'produto_id': produto['produto_id']?.toString(),
      'ean_principal': produto['ean_principal']?.toString(),
      'nome_produto': texto(produto['nome_produto']),
      'local_estoqueid': localEstoque == null
          ? null
          : idLocalEstoque(localEstoque),
      'local_estoque_id': localEstoque == null
          ? null
          : idLocalEstoque(localEstoque),
      'nome_local_estoque': localEstoque == null
          ? null
          : nomeLocalEstoque(localEstoque),
      'estoque_anterior': estoqueAnterior,
      'quantidade_informada': quantidadeInformada,
      'quantidade_alterada': quantidadeAlterada,
      'estoque_novo': estoqueNovo,
      'unidade': unidade,
      'observacao': observacao.isEmpty ? null : observacao,
      'usuario_id': SessaoLoja.usuarioId,
      'usuario_nome': SessaoLoja.usuarioNome ?? SessaoLoja.usuarioLogin,
      'usuario_email': SessaoLoja.usuarioEmail ?? SessaoLoja.usuarioLogin,
      'usuario_perfil': SessaoLoja.usuarioPerfil,
      'origem': 'app_preco',
      ...custoAuditoriaProduto(produto),
    };

    final erroFunction = await registrarAuditoriaEstoqueFunction(registro);

    if (erroFunction == null) {
      return null;
    }

    try {
      await supabase.from('estoque_auditoria').insert(registro);
      return null;
    } catch (e) {
      return mensagemAmigavelErroAuditoria(e, erroFunction: erroFunction);
    }
  }

  Future<String?> registrarAuditoriaEstoqueFunction(
    Map<String, dynamic> registro,
  ) async {
    try {
      SessaoLoja.sincronizarSessaoAtual();
      await SessaoLoja.renovarSessaoLojaSePossivel();
      final lojaAccessToken =
          SessaoLoja.supabaseLoja?.auth.currentSession?.accessToken ??
          SessaoLoja.lojaAccessToken;

      final resposta = await Supabase.instance.client.functions.invoke(
        'registrar-estoque-auditoria',
        body: {
          'mercado_id': SessaoLoja.mercadoId,
          'mercado_codigo': SessaoLoja.mercadoCodigo,
          'loja_access_token': lojaAccessToken,
          'registro': registro,
        },
      );

      final data = resposta.data;

      if (data is Map && data['erro'] != null) {
        throw Exception(data['erro'].toString());
      }

      return null;
    } catch (e) {
      return CentralService.mensagemErroUsuario(e);
    }
  }

  String mensagemAmigavelErroAuditoria(Object erro, {String? erroFunction}) {
    final mensagem = erro.toString().replaceFirst('Exception: ', '');
    final textoErro = mensagem.toLowerCase();

    if (textoErro.contains('row-level security') ||
        textoErro.contains('42501') ||
        textoErro.contains('estoque_auditoria')) {
      return 'Auditoria nao gravada por permissao do banco. Faca deploy da function registrar-estoque-auditoria.';
    }

    if (erroFunction != null && erroFunction.trim().isNotEmpty) {
      return erroFunction;
    }

    return CentralService.mensagemErroUsuario(erro);
  }

  void atualizarProdutoSelecionado(Map<String, dynamic> produtoAtualizado) {
    final produtoAtual = produtoSelecionado;

    if (produtoAtual == null) {
      return;
    }

    final atualizado = Map<String, dynamic>.from(produtoAtual);
    final dadosAtualizados = Map<String, dynamic>.from(produtoAtualizado);
    final localIdAtualizado = inteiro(
      dadosAtualizados['local_estoqueid'] ??
          dadosAtualizados['local_estoque_id'],
    );
    final estoqueLocalAtualizado = dadosAtualizados['estoque_atual'];
    var locaisAtualizados = locaisEstoque;
    var localSelecionadoAtualizado = localEstoqueSelecionado;

    if (localIdAtualizado != null && estoqueLocalAtualizado != null) {
      locaisAtualizados = locaisEstoque.map((local) {
        if (idLocalEstoque(local) != localIdAtualizado) {
          return local;
        }

        final novoLocal = Map<String, dynamic>.from(local);
        novoLocal['quantidade'] = estoqueLocalAtualizado;

        if (dadosAtualizados['nome_local_estoque'] != null) {
          novoLocal['nome_local_estoque'] =
              dadosAtualizados['nome_local_estoque'];
        }

        return novoLocal;
      }).toList();

      for (final local in locaisAtualizados) {
        if (idLocalEstoque(local) == localIdAtualizado) {
          localSelecionadoAtualizado = local;
          break;
        }
      }
    }

    if (dadosAtualizados['estoque_total_app'] != null) {
      dadosAtualizados['estoque_atual'] = dadosAtualizados['estoque_total_app'];
    } else if (localIdAtualizado != null && estoqueLocalAtualizado != null) {
      dadosAtualizados['estoque_atual'] = locaisAtualizados
          .where(
            (local) =>
                lerBooleanoDinamico(local['considerado_no_app'], padrao: true),
          )
          .fold<double>(
            0,
            (total, local) => total + quantidadeLocalEstoque(local),
          );
    }

    atualizado.addAll(dadosAtualizados);

    if (dadosAtualizados['estoque_atual'] == null &&
        dadosAtualizados['quantidade'] != null) {
      atualizado['estoque_atual'] = dadosAtualizados['quantidade'];
    }

    setState(() {
      produtoSelecionado = atualizado;
      locaisEstoque = locaisAtualizados;
      localEstoqueSelecionado = localSelecionadoAtualizado;
      produtos = [];
      buscandoSugestoes = false;
      buscaController.text = texto(atualizado['nome_produto']);
    });
  }

  Future<bool> confirmarAlteracaoEstoque({
    required String titulo,
    required String mensagem,
    required String textoBotao,
  }) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titulo),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.cor,
              foregroundColor: Colors.white,
            ),
            child: Text(textoBotao),
          ),
        ],
      ),
    );

    return confirmado == true;
  }

  Future<void> registrarEntradaEstoque() async {
    final produto = produtoSelecionado;

    if (produto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione um produto primeiro'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final quantidadeEntrada = lerQuantidadeDigitada(
      quantidadeEntradaController.text,
    );

    if (quantidadeEntrada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe a quantidade de entrada'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final erroValidacao = validarQuantidadeProduto(
      produto: produto,
      quantidadeInformada: quantidadeEntrada,
      permitirZero: false,
    );

    if (erroValidacao != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erroValidacao), backgroundColor: Colors.red),
      );
      return;
    }

    final localEstoque = usarEstoqueDetalhadoPorLocal
        ? localEstoqueSelecionado
        : null;

    if (usarEstoqueDetalhadoPorLocal && localEstoque == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione o local de estoque'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final estoqueAtual = localEstoque == null
        ? numeroEstoqueProduto(produto)
        : quantidadeLocalEstoque(localEstoque);
    final novoEstoque = estoqueAtual + quantidadeEntrada;
    final unidade = unidadeProduto(produto);

    final confirmado = await confirmarAlteracaoEstoque(
      titulo: 'Confirmar entrada de estoque',
      mensagem:
          'Produto: ${texto(produto['nome_produto'])}\n\n'
          '${localEstoque == null ? '' : 'Local: ${nomeLocalEstoque(localEstoque)}\n'}'
          'Estoque atual: ${quantidade(estoqueAtual)} $unidade\n'
          'Entrada: ${quantidade(quantidadeEntrada)} $unidade\n'
          'Novo estoque: ${quantidade(novoEstoque)} $unidade',
      textoBotao: 'Confirmar entrada',
    );

    if (!confirmado) {
      return;
    }

    setState(() {
      gravando = true;
    });

    try {
      final atualizado = await atualizarEstoqueNaApi(
        produto: produto,
        novaQuantidade: novoEstoque,
        localEstoque: localEstoque,
      );
      final erroAuditoria = await registrarAuditoriaEstoque(
        tipoMovimentacao: 'ENTRADA',
        produto: produto,
        estoqueAnterior: estoqueAtual,
        quantidadeInformada: quantidadeEntrada,
        quantidadeAlterada: quantidadeEntrada,
        estoqueNovo: novoEstoque,
        unidade: unidade,
        localEstoque: localEstoque,
      );

      if (!mounted) return;

      atualizarProdutoSelecionado(atualizado);

      quantidadeEntradaController.clear();
      observacaoController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            erroAuditoria == null
                ? 'Entrada registrada e estoque atualizado'
                : 'Estoque atualizado, mas a auditoria nao foi gravada: $erroAuditoria',
          ),
          backgroundColor: erroAuditoria == null ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao atualizar estoque: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          gravando = false;
        });
      }
    }
  }

  Future<void> registrarCorrecaoEstoque() async {
    final produto = produtoSelecionado;

    if (produto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione um produto primeiro'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final novaQuantidade = lerQuantidadeDigitada(novaQuantidadeController.text);

    if (novaQuantidade == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe a nova quantidade correta'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final erroValidacao = validarQuantidadeProduto(
      produto: produto,
      quantidadeInformada: novaQuantidade,
      permitirZero: true,
    );

    if (erroValidacao != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erroValidacao), backgroundColor: Colors.red),
      );
      return;
    }

    final localEstoque = usarEstoqueDetalhadoPorLocal
        ? localEstoqueSelecionado
        : null;

    if (usarEstoqueDetalhadoPorLocal && localEstoque == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione o local de estoque'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final estoqueAtual = localEstoque == null
        ? numeroEstoqueProduto(produto)
        : quantidadeLocalEstoque(localEstoque);
    final unidade = unidadeProduto(produto);

    final confirmado = await confirmarAlteracaoEstoque(
      titulo: 'Confirmar correção de estoque',
      mensagem:
          'Produto: ${texto(produto['nome_produto'])}\n\n'
          '${localEstoque == null ? '' : 'Local: ${nomeLocalEstoque(localEstoque)}\n'}'
          'Estoque atual: ${quantidade(estoqueAtual)} $unidade\n'
          'Nova quantidade: ${quantidade(novaQuantidade)} $unidade',
      textoBotao: 'Confirmar correção',
    );

    if (!confirmado) {
      return;
    }

    setState(() {
      gravando = true;
    });

    try {
      final atualizado = await atualizarEstoqueNaApi(
        produto: produto,
        novaQuantidade: novaQuantidade,
        localEstoque: localEstoque,
      );
      final erroAuditoria = await registrarAuditoriaEstoque(
        tipoMovimentacao: 'CORRECAO',
        produto: produto,
        estoqueAnterior: estoqueAtual,
        quantidadeInformada: novaQuantidade,
        quantidadeAlterada: novaQuantidade - estoqueAtual,
        estoqueNovo: novaQuantidade,
        unidade: unidade,
        localEstoque: localEstoque,
      );

      if (!mounted) return;

      atualizarProdutoSelecionado(atualizado);

      novaQuantidadeController.clear();
      observacaoController.clear();

      if (erroAuditoria != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Estoque atualizado, mas a auditoria nao foi gravada: $erroAuditoria',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Correção registrada e estoque atualizado'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao corrigir estoque: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          gravando = false;
        });
      }
    }
  }

  Future<void> registrarBaixaEstoque() async {
    final produto = produtoSelecionado;

    if (produto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione um produto primeiro'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final quantidadeBaixa = lerQuantidadeDigitada(
      quantidadeBaixaController.text,
    );

    if (quantidadeBaixa == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Informe a quantidade da $nomeBaixaEstoque'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final erroValidacao = validarQuantidadeProduto(
      produto: produto,
      quantidadeInformada: quantidadeBaixa,
      permitirZero: false,
    );

    if (erroValidacao != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(erroValidacao), backgroundColor: Colors.red),
      );
      return;
    }

    final localEstoque = usarEstoqueDetalhadoPorLocal
        ? localEstoqueSelecionado
        : null;

    if (usarEstoqueDetalhadoPorLocal && localEstoque == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione o local de estoque'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final estoqueAtual = localEstoque == null
        ? numeroEstoqueProduto(produto)
        : quantidadeLocalEstoque(localEstoque);
    final unidade = unidadeProduto(produto);

    if (quantidadeBaixa > estoqueAtual) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Quantidade maior que o estoque atual (${quantidade(estoqueAtual)} $unidade).',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final novoEstoque = estoqueAtual - quantidadeBaixa;

    final confirmado = await confirmarAlteracaoEstoque(
      titulo: 'Confirmar $nomeBaixaEstoque',
      mensagem:
          'Produto: ${texto(produto['nome_produto'])}\n\n'
          '${localEstoque == null ? '' : 'Local: ${nomeLocalEstoque(localEstoque)}\n'}'
          'Estoque atual: ${quantidade(estoqueAtual)} $unidade\n'
          'Baixa: ${quantidade(quantidadeBaixa)} $unidade\n'
          'Novo estoque: ${quantidade(novoEstoque)} $unidade',
      textoBotao: 'Confirmar baixa',
    );

    if (!confirmado) {
      return;
    }

    setState(() {
      gravando = true;
    });

    try {
      final atualizado = await atualizarEstoqueNaApi(
        produto: produto,
        novaQuantidade: novoEstoque,
        localEstoque: localEstoque,
      );
      final erroAuditoria = await registrarAuditoriaEstoque(
        tipoMovimentacao: widget.tipo,
        produto: produto,
        estoqueAnterior: estoqueAtual,
        quantidadeInformada: quantidadeBaixa,
        quantidadeAlterada: -quantidadeBaixa,
        estoqueNovo: novoEstoque,
        unidade: unidade,
        localEstoque: localEstoque,
      );

      if (!mounted) return;

      atualizarProdutoSelecionado(atualizado);

      quantidadeBaixaController.clear();
      observacaoController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            erroAuditoria == null
                ? '$nomeBaixaEstoque registrada e estoque atualizado'
                : 'Estoque atualizado, mas a auditoria nao foi gravada: $erroAuditoria',
          ),
          backgroundColor: erroAuditoria == null ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao registrar $nomeBaixaEstoque: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          gravando = false;
        });
      }
    }
  }

  String textoBotaoSelecionar() {
    if (widget.tipo == 'ENTRADA') {
      return 'Selecionar para entrada';
    }

    if (widget.tipo == 'CORRECAO') {
      return 'Selecionar para correção';
    }

    if (tipoBaixaEstoque) {
      return 'Selecionar para baixa';
    }

    return 'Selecionar para consumo interno';
  }

  Widget topo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: widget.cor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.cor.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: widget.cor.withValues(alpha: 0.14),
            child: Icon(widget.icone, color: widget.cor, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.titulo,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.subtitulo,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget campoBusca() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: buscaController,
            enabled: !carregando && !gravando,
            textInputAction: TextInputAction.search,
            onChanged: (valor) {
              setState(() {});
              agendarBuscaAutomatica(valor);
            },
            onSubmitted: (_) => consultar(),
            decoration: InputDecoration(
              labelText: 'EAN ou descrição do produto',
              hintText: 'Digite o nome, código ou EAN',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: buscaController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      onPressed: carregando || gravando
                          ? null
                          : limparBuscaProdutos,
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(
                  color: widget.cor.withValues(alpha: 0.65),
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: widget.cor, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: carregando || gravando ? null : consultar,
                    icon: carregando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search),
                    label: const Text('Consultar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: vermelho,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: carregando || gravando ? null : abrirScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scanner'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget cardProduto(Map<String, dynamic> produto) {
    final estoqueAtual = estoqueProduto(produto);
    final selecionado =
        produtoSelecionado?['produto_id']?.toString() ==
        produto['produto_id']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: selecionado ? widget.cor.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selecionado
              ? widget.cor.withValues(alpha: 0.55)
              : Colors.black.withValues(alpha: 0.07),
          width: selecionado ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: selecionado ? 0.06 : 0.025),
            blurRadius: selecionado ? 10 : 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: gravando ? null : () => selecionarProdutoParaEstoque(produto),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selecionado
                        ? widget.cor.withValues(alpha: 0.13)
                        : Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    selecionado
                        ? Icons.check_circle
                        : Icons.inventory_2_outlined,
                    color: selecionado ? widget.cor : Colors.black45,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        texto(produto['nome_produto']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.4,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'EAN: ${texto(produto['ean_principal'])} | ${moeda(produto['preco_venda'])}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 11.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: widget.cor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${quantidade(estoqueAtual)} ${texto(produto['sigla_saida'])}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.cor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Icon(
                      selecionado
                          ? Icons.keyboard_arrow_down
                          : Icons.chevron_right,
                      color: selecionado ? widget.cor : Colors.black38,
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget resumoProdutoSelecionado() {
    final produto = produtoSelecionado;

    if (produto == null || produtos.isNotEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Produto selecionado',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          cardProduto(produto),
        ],
      ),
    );
  }

  Widget painelAcaoInferior() {
    void fecharPorGesto(DragEndDetails details) {
      final velocidade = details.primaryVelocity ?? 0;
      if (velocidade > 220) {
        fecharPainelProdutoSelecionado();
      }
    }

    final handle = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: fecharPainelProdutoSelecionado,
      onVerticalDragEnd: fecharPorGesto,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
        child: Center(
          child: Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );

    return GestureDetector(
      onVerticalDragEnd: fecharPorGesto,
      child: Material(
        color: Colors.transparent,
        elevation: 18,
        child: Container(
          decoration: BoxDecoration(
            color: fundo,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.58,
              ),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Column(children: [handle, painelAcao()]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget chipInfo({required IconData icone, required String textoChip}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 15, color: Colors.black54),
          const SizedBox(width: 5),
          Text(
            textoChip,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget seletorLocalEstoque(Map<String, dynamic> produto) {
    final unidade = unidadeProduto(produto);

    if (carregandoLocaisEstoque) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: widget.cor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: widget.cor.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: widget.cor,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Carregando locais de estoque...')),
          ],
        ),
      );
    }

    if (erroLocaisEstoque != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              erroLocaisEstoque!,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: gravando
                  ? null
                  : () => carregarLocaisEstoqueProduto(produto),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    final itens = locaisEstoque
        .where(
          (local) =>
              idLocalEstoque(local) != null && localConsideradoNoApp(local),
        )
        .map((local) {
          final chave = chaveLocalEstoque(local)!;
          final nome = nomeLocalEstoque(local);
          final saldo = quantidade(quantidadeLocalEstoque(local));

          return DropdownMenuItem<String>(
            value: chave,
            child: Text(
              '$nome - $saldo $unidade',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        })
        .toList();

    if (itens.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.28)),
        ),
        child: const Text(
          'Nenhum local de estoque considerado no app foi retornado para este produto.',
        ),
      );
    }

    final chaveSelecionada = chaveLocalEstoque(localEstoqueSelecionado);
    final value = itens.any((item) => item.value == chaveSelecionada)
        ? chaveSelecionada
        : null;

    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      menuMaxHeight: 320,
      decoration: InputDecoration(
        labelText: 'Local de estoque',
        helperText: 'Escolha onde a alteração será aplicada.',
        prefixIcon: const Icon(Icons.inventory_2_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      items: itens,
      onChanged: gravando
          ? null
          : (chave) {
              if (chave == null) return;

              final selecionado = locaisEstoque.firstWhere(
                (local) => chaveLocalEstoque(local) == chave,
              );

              setState(() {
                localEstoqueSelecionado = selecionado;
              });
            },
    );
  }

  Widget painelEntrada() {
    final produto = produtoSelecionado;

    if (produto == null) {
      return avisoSelecioneProduto();
    }

    final unidade = unidadeProduto(produto);
    final fracionado = permiteQuantidadeFracionada(produto);

    return painelBase(
      titulo: 'Entrada de Estoque',
      subtitulo:
          'Informe a quantidade que entrou. O sistema somará ao estoque atual.',
      children: [
        campoSomenteLeitura(
          label: 'Produto',
          valor: texto(produto['nome_produto']),
        ),
        const SizedBox(height: 12),
        if (usarEstoqueDetalhadoPorLocal) ...[
          seletorLocalEstoque(produto),
          const SizedBox(height: 12),
        ],
        campoSomenteLeitura(
          label:
              !usarEstoqueDetalhadoPorLocal || localEstoqueSelecionado == null
              ? 'Estoque atual'
              : 'Estoque atual no local',
          valor:
              '${quantidade(estoqueAtualMovimentacao(produto))} ${texto(produto['sigla_saida'])}',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: quantidadeEntradaController,
          enabled: !gravando,
          keyboardType: tipoTecladoQuantidade(produto),
          inputFormatters: formatadoresQuantidade(produto),
          decoration: InputDecoration(
            labelText: 'Quantidade de entrada',
            hintText: fracionado ? 'Ex: 1,500' : 'Ex: 10',
            helperText: fracionado
                ? 'Unidade $unidade aceita quantidade fracionada.'
                : 'Unidade $unidade aceita apenas número inteiro.',
            prefixIcon: const Icon(Icons.add),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: observacaoController,
          enabled: !gravando,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Observação',
            hintText: 'Ex: entrada manual, conferência, ajuste inicial',
            prefixIcon: const Icon(Icons.notes),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed:
                gravando ||
                    carregandoTokenEstoque ||
                    carregandoLocaisEstoque ||
                    (usarEstoqueDetalhadoPorLocal &&
                        localEstoqueSelecionado == null)
                ? null
                : registrarEntradaEstoque,
            icon: gravando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle),
            label: Text(
              carregandoTokenEstoque
                  ? 'Carregando autorização...'
                  : 'Registrar entrada',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.cor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget painelCorrecao() {
    final produto = produtoSelecionado;

    if (produto == null) {
      return avisoSelecioneProduto();
    }

    final unidade = unidadeProduto(produto);
    final fracionado = permiteQuantidadeFracionada(produto);

    return painelBase(
      titulo: 'Correção de Estoque',
      subtitulo:
          'Informe o saldo correto. O sistema substituirá o estoque atual.',
      children: [
        campoSomenteLeitura(
          label: 'Produto',
          valor: texto(produto['nome_produto']),
        ),
        const SizedBox(height: 12),
        if (usarEstoqueDetalhadoPorLocal) ...[
          seletorLocalEstoque(produto),
          const SizedBox(height: 12),
        ],
        campoSomenteLeitura(
          label:
              !usarEstoqueDetalhadoPorLocal || localEstoqueSelecionado == null
              ? 'Estoque atual'
              : 'Estoque atual no local',
          valor:
              '${quantidade(estoqueAtualMovimentacao(produto))} ${texto(produto['sigla_saida'])}',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: novaQuantidadeController,
          enabled: !gravando,
          keyboardType: tipoTecladoQuantidade(produto),
          inputFormatters: formatadoresQuantidade(produto),
          decoration: InputDecoration(
            labelText: 'Nova quantidade correta',
            hintText: fracionado ? 'Ex: 2,750' : 'Ex: 25',
            helperText: fracionado
                ? 'Unidade $unidade aceita quantidade fracionada.'
                : 'Unidade $unidade aceita apenas número inteiro.',
            prefixIcon: const Icon(Icons.edit),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: observacaoController,
          enabled: !gravando,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Motivo / observação',
            hintText: 'Ex: divergência de contagem',
            prefixIcon: const Icon(Icons.notes),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed:
                gravando ||
                    carregandoTokenEstoque ||
                    carregandoLocaisEstoque ||
                    (usarEstoqueDetalhadoPorLocal &&
                        localEstoqueSelecionado == null)
                ? null
                : registrarCorrecaoEstoque,
            icon: gravando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle),
            label: Text(
              carregandoTokenEstoque
                  ? 'Carregando autorização...'
                  : 'Registrar correção',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.cor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget painelConsumoInterno() {
    final produto = produtoSelecionado;

    if (produto == null) {
      return avisoSelecioneProduto();
    }

    final unidade = unidadeProduto(produto);
    final fracionado = permiteQuantidadeFracionada(produto);

    return painelBase(
      titulo: 'Confirmar Consumo Interno',
      subtitulo: 'Informe a quantidade usada e registre o consumo interno.',
      children: [
        campoSomenteLeitura(
          label: 'Produto',
          valor: texto(produto['nome_produto']),
        ),
        const SizedBox(height: 12),
        if (usarEstoqueDetalhadoPorLocal) ...[
          seletorLocalEstoque(produto),
          const SizedBox(height: 12),
        ],
        campoSomenteLeitura(
          label:
              !usarEstoqueDetalhadoPorLocal || localEstoqueSelecionado == null
              ? 'Estoque atual'
              : 'Estoque atual no local',
          valor:
              '${quantidade(estoqueAtualMovimentacao(produto))} ${texto(produto['sigla_saida'])}',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: quantidadeConsumoController,
          enabled: !gravando,
          keyboardType: tipoTecladoQuantidade(produto),
          inputFormatters: formatadoresQuantidade(produto),
          decoration: InputDecoration(
            labelText: 'Quantidade consumida',
            hintText: fracionado ? 'Ex: 1,500' : 'Ex: 1',
            helperText: fracionado
                ? 'Unidade $unidade aceita quantidade fracionada.'
                : 'Unidade $unidade aceita apenas número inteiro.',
            prefixIcon: const Icon(Icons.remove_circle_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey(motivoSelecionado),
          initialValue: motivoSelecionado,
          decoration: InputDecoration(
            labelText: 'Motivo',
            prefixIcon: const Icon(Icons.assignment),
            suffixIcon: carregandoMotivosConsumo
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          items: motivosConsumo.map((motivo) {
            return DropdownMenuItem<String>(value: motivo, child: Text(motivo));
          }).toList(),
          onChanged: gravando || carregandoMotivosConsumo
              ? null
              : (valor) {
                  if (valor == null) return;

                  setState(() {
                    motivoSelecionado = valor;
                  });
                },
        ),
        if (SessaoLoja.usuarioAdminLoja) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: gravando || salvandoMotivoConsumo
                  ? null
                  : cadastrarNovoMotivoConsumo,
              icon: salvandoMotivoConsumo
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: const Text('Cadastrar novo motivo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: widget.cor,
                side: BorderSide(color: widget.cor),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: observacaoController,
          enabled: !gravando,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Observação',
            hintText: 'Opcional',
            prefixIcon: const Icon(Icons.notes),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed:
                gravando ||
                    carregandoTokenEstoque ||
                    carregandoLocaisEstoque ||
                    (usarEstoqueDetalhadoPorLocal &&
                        localEstoqueSelecionado == null)
                ? null
                : registrarConsumoInterno,
            icon: gravando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle),
            label: Text(
              carregandoTokenEstoque
                  ? 'Carregando autorização...'
                  : 'Confirmar consumo interno',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.cor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget painelBaixaEstoque() {
    final produto = produtoSelecionado;

    if (produto == null) {
      return avisoSelecioneProduto();
    }

    final unidade = unidadeProduto(produto);
    final fracionado = permiteQuantidadeFracionada(produto);

    return painelBase(
      titulo: nomeBaixaEstoque,
      subtitulo: 'Informe a quantidade que deve sair do estoque.',
      children: [
        campoSomenteLeitura(
          label: 'Produto',
          valor: texto(produto['nome_produto']),
        ),
        const SizedBox(height: 12),
        if (usarEstoqueDetalhadoPorLocal) ...[
          seletorLocalEstoque(produto),
          const SizedBox(height: 12),
        ],
        campoSomenteLeitura(
          label:
              !usarEstoqueDetalhadoPorLocal || localEstoqueSelecionado == null
              ? 'Estoque atual'
              : 'Estoque atual no local',
          valor:
              '${quantidade(estoqueAtualMovimentacao(produto))} ${texto(produto['sigla_saida'])}',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: quantidadeBaixaController,
          enabled: !gravando,
          keyboardType: tipoTecladoQuantidade(produto),
          inputFormatters: formatadoresQuantidade(produto),
          decoration: InputDecoration(
            labelText: 'Quantidade da baixa',
            hintText: fracionado ? 'Ex: 1,500' : 'Ex: 1',
            helperText: fracionado
                ? 'Unidade $unidade aceita quantidade fracionada.'
                : 'Unidade $unidade aceita apenas numero inteiro.',
            prefixIcon: const Icon(Icons.remove_circle_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: observacaoController,
          enabled: !gravando,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Motivo / observacao',
            hintText: widget.tipo == 'BAIXA_VALIDADE'
                ? 'Ex: vencido na prateleira'
                : 'Ex: embalagem danificada',
            prefixIcon: const Icon(Icons.notes),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed:
                gravando ||
                    carregandoTokenEstoque ||
                    carregandoLocaisEstoque ||
                    (usarEstoqueDetalhadoPorLocal &&
                        localEstoqueSelecionado == null)
                ? null
                : registrarBaixaEstoque,
            icon: gravando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle),
            label: Text(
              carregandoTokenEstoque
                  ? 'Carregando autorizacao...'
                  : 'Registrar baixa',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.cor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget painelAcao() {
    if (produtos.isEmpty && produtoSelecionado == null) {
      return const SizedBox.shrink();
    }

    if (widget.tipo == 'ENTRADA') {
      return painelEntrada();
    }

    if (widget.tipo == 'CORRECAO') {
      return painelCorrecao();
    }

    if (tipoBaixaEstoque) {
      return painelBaixaEstoque();
    }

    return painelConsumoInterno();
  }

  Widget painelBase({
    required String titulo,
    required String subtitulo,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.cor.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(widget.icone, color: widget.cor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitulo,
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget campoSomenteLeitura({required String label, required String valor}) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(
        valor,
        style: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget avisoSelecioneProduto() {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.cor.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(Icons.touch_app, color: widget.cor),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Consulte ou escaneie um produto e selecione para continuar.',
              style: TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget acessoNegado() {
    return Scaffold(
      backgroundColor: fundo,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(widget.titulo),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 46, color: Colors.black38),
                SizedBox(height: 12),
                Text(
                  'Acesso não permitido',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Seu usuário não tem permissão para acessar esta movimentação de estoque.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget indicadorBuscaAutomatica() {
    if (!buscandoSugestoes) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.cor.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: widget.cor),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Buscando produtos...',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget listaSuspensaProdutos() {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.cor.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              color: const Color(0xFFF9FAFB),
              child: Text(
                produtos.length == 1
                    ? 'Selecione o produto encontrado'
                    : 'Selecione um dos ${produtos.length} produtos encontrados',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                  fontSize: 13,
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                padding: const EdgeInsets.all(8),
                shrinkWrap: true,
                itemCount: produtos.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  return cardProduto(produtos[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget corpoResultado() {
    if (carregando) {
      return const Padding(
        padding: EdgeInsets.only(top: 30),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (buscandoSugestoes) {
      return indicadorBuscaAutomatica();
    }

    if (erro != null) {
      return Container(
        margin: const EdgeInsets.only(top: 18),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(erro!, style: const TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    }

    if (produtos.isNotEmpty) {
      return listaSuspensaProdutos();
    }

    if (produtoSelecionado != null) {
      return resumoProdutoSelecionado();
    }

    return const Padding(
      padding: EdgeInsets.only(top: 28),
      child: Center(
        child: Text(
          'Digite pelo menos 3 caracteres para listar os produtos.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.ignorarPermissao &&
        !usuarioPodePermissaoEstoque(widget.permissao)) {
      return acessoNegado();
    }

    final paddingInferior = produtoSelecionado == null
        ? 16.0
        : MediaQuery.sizeOf(context).height * 0.58 + 24;

    return PopScope(
      canPop: produtoSelecionado == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }

        fecharPainelProdutoSelecionado();
      },
      child: Scaffold(
        backgroundColor: fundo,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(widget.titulo),
          backgroundColor: vermelho,
          foregroundColor: Colors.white,
        ),
        body: Stack(
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, paddingInferior),
              children: [
                topo(),
                const SizedBox(height: 16),
                campoBusca(),
                corpoResultado(),
              ],
            ),
            if (produtoSelecionado != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: painelAcaoInferior(),
              ),
          ],
        ),
      ),
    );
  }
}

class _CadastrarMotivoConsumoDialog extends StatefulWidget {
  const _CadastrarMotivoConsumoDialog();

  @override
  State<_CadastrarMotivoConsumoDialog> createState() =>
      _CadastrarMotivoConsumoDialogState();
}

class _CadastrarMotivoConsumoDialogState
    extends State<_CadastrarMotivoConsumoDialog> {
  final TextEditingController controller = TextEditingController();
  String? erro;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void salvar() {
    final nome = controller.text.trim();

    if (nome.length < 2) {
      setState(() {
        erro = 'Informe um nome com pelo menos 2 caracteres.';
      });
      return;
    }

    if (nome.length > 60) {
      setState(() {
        erro = 'O nome pode ter no máximo 60 caracteres.';
      });
      return;
    }

    Navigator.of(context).pop(nome);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo motivo de consumo'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => salvar(),
        decoration: InputDecoration(
          labelText: 'Nome do motivo',
          hintText: 'Ex: Escritório',
          errorText: erro,
          prefixIcon: const Icon(Icons.assignment_add),
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: salvar,
          icon: const Icon(Icons.save),
          label: const Text('Cadastrar'),
        ),
      ],
    );
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_mercado_config.dart';
import '../models/produto.dart';
import 'sessao_mercado_cliente.dart';

class RegraClassificacaoNcm {
  final String ncmPrefixo;
  final String categoria;
  final String subcategoria;
  final int ordemCategoria;
  final int ordemSubcategoria;
  final int prioridade;
  final List<String> palavrasIncluir;
  final List<String> palavrasExcluir;
  final bool escopoLoja;

  const RegraClassificacaoNcm({
    required this.ncmPrefixo,
    required this.categoria,
    required this.subcategoria,
    required this.ordemCategoria,
    required this.ordemSubcategoria,
    required this.prioridade,
    required this.palavrasIncluir,
    required this.palavrasExcluir,
    required this.escopoLoja,
  });

  factory RegraClassificacaoNcm.fromJson(Map<String, dynamic> json) {
    return RegraClassificacaoNcm(
      ncmPrefixo: _digitos(json['ncm_prefixo']),
      categoria: _texto(json['categoria']),
      subcategoria: _texto(json['subcategoria']),
      ordemCategoria: _inteiro(json['ordem_categoria']),
      ordemSubcategoria: _inteiro(json['ordem_subcategoria']),
      prioridade: _inteiro(json['prioridade']),
      palavrasIncluir: _lista(json['palavras_incluir']),
      palavrasExcluir: _lista(json['palavras_excluir']),
      escopoLoja: json['escopo_loja'] == true,
    );
  }

  bool corresponde(Produto produto) {
    final ncmProduto = _digitos(produto.ncm);
    if (ncmPrefixo.isEmpty || !ncmProduto.startsWith(ncmPrefixo)) return false;
    final nome = _normalizar(produto.nome);
    if (palavrasExcluir.any((palavra) => nome.contains(_normalizar(palavra)))) {
      return false;
    }
    if (palavrasIncluir.isEmpty) return true;
    return palavrasIncluir.any(
      (palavra) => nome.contains(_normalizar(palavra)),
    );
  }

  static String _texto(dynamic valor) => valor?.toString().trim() ?? '';
  static String _digitos(dynamic valor) =>
      _texto(valor).replaceAll(RegExp(r'[^0-9]'), '');
  static int _inteiro(dynamic valor) =>
      valor is num ? valor.toInt() : int.tryParse(_texto(valor)) ?? 0;
  static List<String> _lista(dynamic valor) => valor is List
      ? valor.map(_texto).where((item) => item.isNotEmpty).toList()
      : const [];
}

class ClassificacaoNcmService {
  ClassificacaoNcmService._();

  static SupabaseClient? _central;
  static Future<void>? _carregamento;
  static List<RegraClassificacaoNcm> _regras = const [];
  static Map<String, List<RegraClassificacaoNcm>> _regrasLocaisPorPrefixo =
      const {};
  static Map<String, List<RegraClassificacaoNcm>> _regrasGlobaisPorPrefixo =
      const {};
  static List<Map<String, dynamic>> _categoriasHibridas = const [];
  static String _modo = 'HIBRIDO';

  static bool get usaCatalogoClassificado {
    final modo = SessaoMercadoCliente.categoriaOrigem.trim().toUpperCase();
    return modo == 'NCM' || modo == 'HIBRIDO';
  }

  static bool get usaSomenteNcm =>
      SessaoMercadoCliente.categoriaOrigem.trim().toUpperCase() == 'NCM';

  static bool get usaHibrido =>
      SessaoMercadoCliente.categoriaOrigem.trim().toUpperCase() == 'HIBRIDO';

  static Future<List<RegraClassificacaoNcm>> regrasAtivas() async {
    await _carregar();
    return List<RegraClassificacaoNcm>.unmodifiable(_regras);
  }

  static Future<List<Map<String, dynamic>>> categoriasHibridas() async {
    await _carregar();
    return _categoriasHibridas
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static Future<List<Produto>> aplicar(List<Produto> produtos) async {
    if (produtos.isEmpty) return produtos;
    await _carregar();
    return produtos
        .map(
          (produto) => resolverProduto(produto, modo: _modo, regras: _regras),
        )
        .toList();
  }

  static Produto resolverProduto(
    Produto produto, {
    required String modo,
    required List<RegraClassificacaoNcm> regras,
  }) {
    final modoNormalizado = modo.trim().toUpperCase();
    final categoriaApi = produto.categoriaApi.trim().isNotEmpty
        ? produto.categoriaApi.trim()
        : produto.categoria.trim();
    final subcategoriaApi = produto.subcategoriaApi.trim().isNotEmpty
        ? produto.subcategoriaApi.trim()
        : produto.subcategoria.trim();
    if (modoNormalizado == 'API') {
      return produto.copyWith(
        categoria: categoriaApi,
        subcategoria: subcategoriaApi,
      );
    }

    final regra = identical(regras, _regras)
        ? _encontrarRegraIndexada(produto)
        : _encontrarRegraLinear(produto, regras);

    if (modoNormalizado == 'HIBRIDO' && categoriaApi.isNotEmpty) {
      final mesmaCategoria =
          regra != null &&
          _normalizar(regra.categoria) == _normalizar(categoriaApi);
      return produto.copyWith(
        categoria: categoriaApi,
        subcategoria: subcategoriaApi.isNotEmpty
            ? subcategoriaApi
            : mesmaCategoria
            ? regra.subcategoria
            : '',
        ordemCategoria: mesmaCategoria ? regra.ordemCategoria : 0,
        ordemSubcategoria: mesmaCategoria ? regra.ordemSubcategoria : 0,
      );
    }

    if (regra == null) {
      return produto.copyWith(
        categoria: 'Outros',
        subcategoria: '',
        ordemCategoria: 9999,
        ordemSubcategoria: 9999,
      );
    }

    return produto.copyWith(
      categoria: regra.categoria,
      subcategoria: regra.subcategoria,
      ordemCategoria: regra.ordemCategoria,
      ordemSubcategoria: regra.ordemSubcategoria,
    );
  }

  static Future<void> _carregar() {
    return _carregamento ??= _buscarRegras();
  }

  static Future<void> _buscarRegras() async {
    _modo = SessaoMercadoCliente.categoriaOrigem.trim().toUpperCase();
    if (!const {'API', 'NCM', 'HIBRIDO'}.contains(_modo)) _modo = 'HIBRIDO';
    if (_modo == 'API') return;
    try {
      _central ??= SupabaseClient(
        AppMercadoConfig.centralSupabaseUrl,
        AppMercadoConfig.centralSupabaseAnonKey,
      );
      final resposta = await _central!.functions.invoke(
        'buscar-regras-categorizacao',
        body: {
          'mercado_id': SessaoMercadoCliente.mercadoIdObrigatorio,
          'mercado_codigo': SessaoMercadoCliente.mercadoCodigoObrigatorio,
        },
      );
      final dados = resposta.data;
      if (dados is! Map || dados['erro'] != null) {
        _modo = 'API';
        return;
      }
      _modo =
          dados['categoria_origem']?.toString().trim().toUpperCase() ?? _modo;
      final resumo = dados['categorias_hibridas'];
      _categoriasHibridas = resumo is List
          ? resumo
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false)
          : const [];
      final lista = dados['regras'];
      if (lista is! List) {
        _modo = 'API';
        return;
      }
      _regras =
          lista
              .whereType<Map>()
              .map(
                (item) => RegraClassificacaoNcm.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
            ..sort((a, b) {
              final escopo = (b.escopoLoja ? 1 : 0).compareTo(
                a.escopoLoja ? 1 : 0,
              );
              if (escopo != 0) return escopo;
              final tamanho = b.ncmPrefixo.length.compareTo(
                a.ncmPrefixo.length,
              );
              if (tamanho != 0) return tamanho;
              return b.prioridade.compareTo(a.prioridade);
            });
      _indexarRegras();
    } catch (_) {
      // Sem conexao com a Central, preserva a classificacao original da API.
      _modo = 'API';
    }
  }

  static RegraClassificacaoNcm? _encontrarRegraLinear(
    Produto produto,
    List<RegraClassificacaoNcm> regras,
  ) {
    for (final candidata in regras) {
      if (candidata.corresponde(produto)) return candidata;
    }
    return null;
  }

  static void _indexarRegras() {
    final locais = <String, List<RegraClassificacaoNcm>>{};
    final globais = <String, List<RegraClassificacaoNcm>>{};
    for (final regra in _regras) {
      final destino = regra.escopoLoja ? locais : globais;
      (destino[regra.ncmPrefixo] ??= []).add(regra);
    }
    _regrasLocaisPorPrefixo = locais;
    _regrasGlobaisPorPrefixo = globais;
  }

  static RegraClassificacaoNcm? _encontrarRegraIndexada(Produto produto) {
    final ncm = RegraClassificacaoNcm._digitos(produto.ncm);
    if (ncm.isEmpty) return null;
    for (final indice in [_regrasLocaisPorPrefixo, _regrasGlobaisPorPrefixo]) {
      for (final tamanho in const [8, 6, 4, 2]) {
        if (ncm.length < tamanho) continue;
        for (final regra in indice[ncm.substring(0, tamanho)] ?? const []) {
          if (regra.corresponde(produto)) return regra;
        }
      }
    }
    return null;
  }

  static void limparCache() {
    _carregamento = null;
    _regras = const [];
    _regrasLocaisPorPrefixo = const {};
    _regrasGlobaisPorPrefixo = const {};
    _categoriasHibridas = const [];
    _modo = SessaoMercadoCliente.categoriaOrigem;
  }
}

String _normalizar(String valor) {
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
      .replaceAll('Ç', 'C')
      .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
      .trim();
}

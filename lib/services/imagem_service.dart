import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_mercado_config.dart' as app_config;
import 'sessao_mercado_cliente.dart' as sessao;

class ImagemService {
  static const Duration _timeout = Duration(seconds: 25);

  /// Imagem encontrada fica cacheada no app por 3 dias.
  /// Depois de 3 dias, consulta novamente a Central.
  static const Duration _validadeCacheImagem = Duration(days: 3);

  /// Nome da Edge Function na Supabase Central.
  static const String _functionBuscarImagem = 'buscar-imagem-produto';

  /// Cache em memória da sessão atual.
  ///
  /// Se encontrou imagem, guarda a URL.
  /// Se não encontrou imagem, guarda null.
  ///
  /// Isso faz produto sem imagem tentar buscar apenas 1 vez por abertura do app.
  static final Map<String, String?> _cacheMemoria = {};

  /// Controla buscas que já estão em andamento.
  static final Map<String, Future<String?>> _buscasEmAndamento = {};

  static SupabaseClient get _central {
    return SupabaseClient(
      app_config.AppMercadoConfig.centralSupabaseUrl,
      app_config.AppMercadoConfig.centralSupabaseAnonKey,
    );
  }

  static Future<String?> buscarImagemProduto({
    required String ean,
    required String nomeProduto,
  }) async {
    final eanLimpo = ean.trim();
    final nomeLimpo = nomeProduto.trim();

    if (eanLimpo.isEmpty && nomeLimpo.isEmpty) {
      return null;
    }

    final chaveCache = _montarChaveCache(ean: eanLimpo, nomeProduto: nomeLimpo);

    // 1) Se já buscou nessa abertura do app, retorna direto.
    // Isso inclui null para produto sem imagem.
    if (_cacheMemoria.containsKey(chaveCache)) {
      return _cacheMemoria[chaveCache];
    }

    // 2) Se já tem imagem local válida, usa por até 7 dias sem chamar function.
    final imagemLocal = await _buscarImagemNoCacheLocal(chaveCache);

    if (imagemLocal != null) {
      _cacheMemoria[chaveCache] = imagemLocal;
      return imagemLocal;
    }

    // 3) Se já existe uma busca em andamento para esse produto, aguarda a mesma.
    final buscaExistente = _buscasEmAndamento[chaveCache];

    if (buscaExistente != null) {
      return buscaExistente;
    }

    // 4) Busca apenas conforme o produto aparece na tela, igual hoje.
    final busca = _buscarImagemProdutoPorRegra(
      ean: eanLimpo,
      nomeProduto: nomeLimpo,
    );

    _buscasEmAndamento[chaveCache] = busca;

    try {
      final resultado = await busca;

      // Guarda em memória até null.
      // Assim produto sem imagem só tenta uma vez por abertura do app.
      _cacheMemoria[chaveCache] = resultado;

      if (resultado != null && resultado.trim().isNotEmpty) {
        await _salvarImagemNoCacheLocal(chaveCache, resultado);
      } else {
        // Se não encontrou, não salva cache negativo em disco.
        // Na próxima abertura do app, ele tenta novamente uma vez.
        await _removerImagemDoCacheLocal(chaveCache);
      }

      return resultado;
    } finally {
      _buscasEmAndamento.remove(chaveCache);
    }
  }

  static Future<String?> _buscarImagemProdutoPorRegra({
    required String ean,
    required String nomeProduto,
  }) async {
    if (_eanInternoLoja(ean)) {
      final imagemLoja = await _buscarImagemProdutoBaseLoja(ean: ean);

      if (imagemLoja != null && imagemLoja.trim().isNotEmpty) {
        return imagemLoja;
      }

      return _buscarImagemProdutoCentral(
        ean: ean,
        nomeProduto: nomeProduto,
        ignorarCacheCentral: true,
        salvarNoCentral: false,
      );
    }

    return _buscarImagemProdutoCentral(ean: ean, nomeProduto: nomeProduto);
  }

  static Future<String?> _buscarImagemProdutoBaseLoja({
    required String ean,
  }) async {
    final mercadoId = sessao.SessaoMercadoCliente.mercadoId.trim();
    final mercadoCodigo = sessao.SessaoMercadoCliente.mercadoCodigo.trim();

    for (final candidato in _candidatosEan(ean)) {
      if (mercadoId.isNotEmpty) {
        final imagem = await _buscarImagemProdutoBaseLojaComFiltro(
          ean: candidato,
          coluna: 'mercado_id',
          valor: mercadoId,
        );

        if (imagem != null) {
          return imagem;
        }
      }

      if (mercadoCodigo.isNotEmpty) {
        final imagem = await _buscarImagemProdutoBaseLojaComFiltro(
          ean: candidato,
          coluna: 'mercado_codigo',
          valor: mercadoCodigo,
        );

        if (imagem != null) {
          return imagem;
        }
      }
    }

    return null;
  }

  static Future<String?> _buscarImagemProdutoBaseLojaComFiltro({
    required String ean,
    required String coluna,
    required String valor,
  }) async {
    try {
      final data = await Supabase.instance.client
          .from('produtos_imagens')
          .select('imagem_url')
          .eq(coluna, valor)
          .eq('ean', ean)
          .limit(1)
          .maybeSingle()
          .timeout(_timeout);

      return _extrairImagemUrl(data);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _buscarImagemProdutoCentral({
    required String ean,
    required String nomeProduto,
    bool ignorarCacheCentral = false,
    bool salvarNoCentral = true,
  }) async {
    if (app_config.AppMercadoConfig.centralSupabaseAnonKey.contains(
      'COLOQUE_A_ANON',
    )) {
      return null;
    }

    try {
      final resposta = await _central.functions
          .invoke(
            _functionBuscarImagem,
            body: {
              'ean': ean,
              'nome_produto': nomeProduto,

              // Aliases para compatibilidade.
              'nome': nomeProduto,
              'descricao': nomeProduto,
              'produto_nome': nomeProduto,

              // Identificação da loja.
              'mercado_id': app_config.AppMercadoConfig.mercadoId,
              'mercado_codigo': app_config.AppMercadoConfig.mercadoCodigo,
              'ignorar_cache_central': ignorarCacheCentral,
              'salvar_no_central': salvarNoCentral,
            },
          )
          .timeout(_timeout);

      return _extrairImagemUrl(resposta.data);
    } catch (_) {
      return null;
    }
  }

  static String _montarChaveCache({
    required String ean,
    required String nomeProduto,
  }) {
    if (ean.trim().isNotEmpty) {
      return 'ean:${ean.trim()}';
    }

    return 'nome:${nomeProduto.trim().toUpperCase()}';
  }

  static bool _eanInternoLoja(String ean) {
    return _apenasNumeros(ean).startsWith('0000000');
  }

  static List<String> _candidatosEan(String ean) {
    final candidatos = <String>[];
    final original = ean.trim();
    final numeros = _apenasNumeros(ean);

    if (original.isNotEmpty) {
      candidatos.add(original);
    }

    if (numeros.isNotEmpty && numeros != original) {
      candidatos.add(numeros);
    }

    return candidatos.toSet().toList();
  }

  static String _apenasNumeros(String valor) {
    return valor.replaceAll(RegExp(r'[^0-9]'), '');
  }

  static String _chaveUrl(String chaveCache) {
    return 'produto_img_${_normalizarChavePreferencias(chaveCache)}_url';
  }

  static String _chaveData(String chaveCache) {
    return 'produto_img_${_normalizarChavePreferencias(chaveCache)}_data';
  }

  static String _normalizarChavePreferencias(String chave) {
    return chave.replaceAll(RegExp(r'[^a-zA-Z0-9_:-]'), '_');
  }

  static Future<String?> _buscarImagemNoCacheLocal(String chaveCache) async {
    final prefs = await SharedPreferences.getInstance();

    final url = prefs.getString(_chaveUrl(chaveCache));
    final dataMs = prefs.getInt(_chaveData(chaveCache));

    if (url == null || url.trim().isEmpty || dataMs == null) {
      return null;
    }

    final criadoEm = DateTime.fromMillisecondsSinceEpoch(dataMs);
    final expirado = DateTime.now().difference(criadoEm) > _validadeCacheImagem;

    if (expirado) {
      await _removerImagemDoCacheLocal(chaveCache);
      return null;
    }

    return url;
  }

  static Future<void> _salvarImagemNoCacheLocal(
    String chaveCache,
    String imagemUrl,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_chaveUrl(chaveCache), imagemUrl);
    await prefs.setInt(
      _chaveData(chaveCache),
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<void> _removerImagemDoCacheLocal(String chaveCache) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_chaveUrl(chaveCache));
    await prefs.remove(_chaveData(chaveCache));
  }

  static String? _extrairImagemUrl(dynamic data) {
    if (data == null) {
      return null;
    }

    if (data is String) {
      return data.startsWith('http') ? data : null;
    }

    if (data is Map<String, dynamic>) {
      return _extrairImagemUrlDeMap(data);
    }

    if (data is Map) {
      return _extrairImagemUrlDeMap(Map<String, dynamic>.from(data));
    }

    return null;
  }

  static String? _extrairImagemUrlDeMap(Map<String, dynamic> data) {
    final dataInterna = data['data'];

    if (dataInterna is Map) {
      final url = _extrairImagemUrlDeMap(
        Map<String, dynamic>.from(dataInterna),
      );

      if (url != null) {
        return url;
      }
    }

    for (final chave in ['produto', 'imagem', 'resultado', 'item']) {
      final interno = data[chave];

      if (interno is Map) {
        final url = _extrairImagemUrlDeMap(Map<String, dynamic>.from(interno));

        if (url != null) {
          return url;
        }
      }
    }

    final possiveisCampos = [
      'imagem_url',
      'imagemUrl',
      'image_url',
      'imageUrl',
      'url',
      'imagem',
      'image',
      'original',
      'thumbnail',
      'serpapi_thumbnail',
    ];

    for (final campo in possiveisCampos) {
      final valor = data[campo];

      if (valor == null) {
        continue;
      }

      final texto = valor.toString().trim();

      if (texto.startsWith('http://') || texto.startsWith('https://')) {
        return texto;
      }
    }

    return null;
  }

  /// Use apenas se quiser forçar recarregamento de imagens durante testes.
  static Future<void> limparCacheMemoria() async {
    _cacheMemoria.clear();
    _buscasEmAndamento.clear();
  }

  /// Use apenas em testes/manutenção para limpar também o cache de 7 dias.
  static Future<void> limparCacheLocal() async {
    _cacheMemoria.clear();
    _buscasEmAndamento.clear();

    final prefs = await SharedPreferences.getInstance();

    final chaves = prefs.getKeys().where(
      (chave) => chave.startsWith('produto_img_'),
    );

    for (final chave in chaves) {
      await prefs.remove(chave);
    }
  }
}

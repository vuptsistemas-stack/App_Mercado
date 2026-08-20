import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/produto.dart';
import 'loja_funcionamento_service.dart';
import 'produto_configuracao_app_service.dart';
import 'sessao_mercado_cliente.dart' as sessao;

class ApiService {
  static const Duration _timeout = Duration(seconds: 20);

  /// URL da API da loja carregada pela Central.
  ///
  /// Antes estava fixo:
  /// http://192.141.122.71:34000
  ///
  /// Agora vem da function buscar-conexao-mercado-cliente,
  /// através de SessaoMercadoCliente.apiBaseUrl.
  static String get baseUrl {
    final url = sessao.SessaoMercadoCliente.apiBaseUrl.trim();

    if (url.isEmpty) {
      throw Exception(
        'API da loja não carregada. Verifique o campo api_base_url na Central.',
      );
    }

    return _removerBarraFinal(url);
  }

  static String _removerBarraFinal(String valor) {
    var texto = valor.trim();

    while (texto.endsWith('/')) {
      texto = texto.substring(0, texto.length - 1);
    }

    return texto;
  }

  static Uri _uri(String path, {Map<String, String>? queryParameters}) {
    final base = baseUrl;
    final pathCorrigido = path.startsWith('/') ? path : '/$path';

    return Uri.parse(
      '$base$pathCorrigido',
    ).replace(queryParameters: queryParameters);
  }

  static Future<http.Response> _get(Uri url) {
    return http.get(url).timeout(_timeout);
  }

  static bool get _usarBancoLoja {
    return sessao.SessaoMercadoCliente.fonteProdutos == 'BANCO_LOJA';
  }

  static bool get usandoBancoLoja => _usarBancoLoja;

  static SupabaseClient get _supabaseLoja => Supabase.instance.client;

  static Map<String, dynamic> _normalizarProdutoBancoLoja(
    Map<String, dynamic> item,
  ) {
    final precoPromocional = item['preco_promocional'];
    final precoNormal = item['preco'];

    return {
      ...item,
      'produto_app_id': item['id'],
      'produto_id': item['produto_id'] ?? item['id'],
      'nome_produto': item['nome_produto'] ?? item['descricao'] ?? item['nome'],
      'descricao': item['descricao'] ?? item['nome_produto'],
      'ean_principal': item['ean'] ?? item['codigo_barras'],
      'preco_venda': precoPromocional ?? precoNormal,
      'preco': precoPromocional ?? precoNormal,
      'estoque_atual': item['estoque'],
      'unidade_medida': item['unidade'],
      'imagem_url': item['imagem_url'],
      'peso_variavel': item['peso_variavel'],
      'peso_medio_kg': item['peso_medio_kg'],
    };
  }

  static List<Produto> _produtosBancoParaModelos(List<dynamic> resposta) {
    final produtos = resposta
        .whereType<Map>()
        .map((item) {
          final dados = Map<String, dynamic>.from(item);
          return Produto.fromJson(_normalizarProdutoBancoLoja(dados));
        })
        .where((produto) => produto.nome.trim().isNotEmpty)
        .toList();

    return removerProdutosDuplicados(produtos);
  }

  static List<Produto> removerProdutosDuplicados(List<Produto> produtos) {
    final resultado = <Produto>[];
    final chaves = <String>{};

    for (final produto in produtos) {
      final chave = _chaveProdutoUnico(produto);

      if (chave.isEmpty || chaves.contains(chave)) {
        continue;
      }

      chaves.add(chave);
      resultado.add(produto);
    }

    return resultado;
  }

  static Future<List<Produto>> aplicarFiltroEstoqueApp(
    List<Produto> produtos,
  ) async {
    try {
      final configuracoes =
          await LojaFuncionamentoService.buscarConfiguracoes();
      var visiveis = _filtrarCategoriasBloqueadas(produtos, configuracoes);

      if (configuracoes.exibirProdutosSemEstoque) {
        return visiveis;
      }

      return _filtrarProdutosComEstoque(visiveis);
    } catch (_) {
      return produtos;
    }
  }

  static Future<bool> deveExibirProdutoNoApp(Produto produto) async {
    final produtos = await aplicarFiltroEstoqueApp([produto]);
    return produtos.isNotEmpty;
  }

  static List<Produto> _filtrarProdutosComEstoque(List<Produto> produtos) {
    return produtos.where((produto) => produto.estoque > 0).toList();
  }

  static List<Produto> _filtrarCategoriasBloqueadas(
    List<Produto> produtos,
    LojaConfiguracoesCliente configuracoes,
  ) {
    final categoriasCliente =
        LojaFuncionamentoService.categoriasBloqueadasCliente;

    if (categoriasCliente.isEmpty) {
      return produtos;
    }

    final bloqueadas = categoriasCliente
        .map(LojaFuncionamentoService.normalizarCategoria)
        .where((categoria) => categoria.isNotEmpty)
        .toSet();

    return produtos.where((produto) {
      final categoria = LojaFuncionamentoService.normalizarCategoria(
        produto.categoria,
      );

      return categoria.isEmpty || !bloqueadas.contains(categoria);
    }).toList();
  }

  static bool _categoriaBloqueada(
    String categoria,
    LojaConfiguracoesCliente configuracoes,
  ) {
    final categoriaNormalizada = LojaFuncionamentoService.normalizarCategoria(
      categoria,
    );

    if (categoriaNormalizada.isEmpty) return false;

    return LojaFuncionamentoService.categoriaBloqueadaParaCliente(categoria);
  }

  static Future<List<Produto>> _buscarProdutosApiPagina({
    required String path,
    required int pagina,
    required int limite,
    String busca = '',
  }) async {
    final queryParameters = <String, String>{
      'pagina': pagina.toString(),
      'limite': limite.toString(),
    };

    final termoBusca = busca.trim();

    if (termoBusca.isNotEmpty) {
      queryParameters['busca'] = termoBusca;
    }

    final response = await _get(_uri(path, queryParameters: queryParameters));

    if (response.statusCode != 200) {
      return [];
    }

    final produtos = await ProdutoConfiguracaoAppService.aplicarConfiguracoes(
      _converterResposta(response.body),
    );

    final configuracoes = await LojaFuncionamentoService.buscarConfiguracoes();

    return _filtrarCategoriasBloqueadas(
      removerProdutosDuplicados(produtos),
      configuracoes,
    );
  }

  static Future<List<Produto>> _listarProdutosApiPaginados({
    required String path,
    int pagina = 1,
    int limite = 20,
    String busca = '',
  }) async {
    final paginaCorrigida = pagina < 1 ? 1 : pagina;
    final limiteCorrigido = limite < 1 ? 20 : limite;
    final configuracoes = await LojaFuncionamentoService.buscarConfiguracoes();

    if (configuracoes.exibirProdutosSemEstoque &&
        LojaFuncionamentoService.categoriasBloqueadasCliente.isEmpty) {
      final produtos = await _buscarProdutosApiPagina(
        path: path,
        pagina: paginaCorrigida,
        limite: limiteCorrigido,
        busca: busca,
      );

      if (produtos.length < limiteCorrigido) {
        return produtos;
      }

      final proximaPagina = await _buscarProdutosApiPagina(
        path: path,
        pagina: paginaCorrigida + 1,
        limite: limiteCorrigido,
        busca: busca,
      );

      final chavesAtuais = produtos
          .map(_chaveProdutoUnico)
          .where((chave) => chave.isNotEmpty)
          .toSet();

      for (final produto in proximaPagina) {
        final chave = _chaveProdutoUnico(produto);

        if (chave.isEmpty || chavesAtuais.contains(chave)) {
          continue;
        }

        return [...produtos, produto];
      }

      return produtos;
    }

    final inicioVisivel = (paginaCorrigida - 1) * limiteCorrigido;
    final quantidadeDesejada = limiteCorrigido + 1;
    final limiteApi = limiteCorrigido;
    final produtos = <Produto>[];
    final chaves = <String>{};

    var paginaApi = 1;
    var visiveisIgnorados = 0;

    while (produtos.length < quantidadeDesejada && paginaApi <= 40) {
      final lote = await _buscarProdutosApiPagina(
        path: path,
        pagina: paginaApi,
        limite: limiteApi,
        busca: busca,
      );

      if (lote.isEmpty) {
        break;
      }

      final visiveis = configuracoes.exibirProdutosSemEstoque
          ? lote
          : _filtrarProdutosComEstoque(lote);

      for (final produto in visiveis) {
        final chave = _chaveProdutoUnico(produto);

        if (chave.isEmpty || chaves.contains(chave)) {
          continue;
        }

        chaves.add(chave);

        if (visiveisIgnorados < inicioVisivel) {
          visiveisIgnorados++;
          continue;
        }

        produtos.add(produto);

        if (produtos.length >= quantidadeDesejada) {
          break;
        }
      }

      if (lote.length < limiteApi) {
        break;
      }

      paginaApi++;
    }

    return produtos;
  }

  static String _chaveProdutoUnico(Produto produto) {
    final ean = _normalizarEan(produto.ean);

    if (ean.isNotEmpty) {
      return 'ean:$ean';
    }

    final produtoAppId = produto.produtoAppId.trim();

    if (produtoAppId.isNotEmpty) {
      return 'produto_app_id:$produtoAppId';
    }

    final nome = _normalizarNomeProduto(produto.nome);

    if (nome.isNotEmpty) {
      return 'nome:$nome';
    }

    if (produto.produtoId > 0) {
      return 'id:${produto.produtoId}';
    }

    return '';
  }

  static Future<List<Produto>> _listarProdutosBancoLoja({
    int pagina = 1,
    int limite = 20,
    String busca = '',
    String categoria = '',
    String subcategoria = '',
  }) async {
    try {
      final paginaCorrigida = pagina < 1 ? 1 : pagina;
      final limiteCorrigido = limite < 1 ? 20 : limite;
      final inicio = (paginaCorrigida - 1) * limiteCorrigido;
      final limiteConsulta = limiteCorrigido + 1;
      final fim = inicio + limiteConsulta - 1;
      final configuracoes =
          await LojaFuncionamentoService.buscarConfiguracoes();

      dynamic consulta = _supabaseLoja
          .from('produtos_app')
          .select()
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('ativo', true)
          .eq('vende_no_app', true);

      if (!configuracoes.exibirProdutosSemEstoque) {
        consulta = consulta.gt('estoque', 0);
      }

      final categoriaFiltro = categoria.trim();
      if (_categoriaBloqueada(categoriaFiltro, configuracoes)) {
        return [];
      }

      if (categoriaFiltro.isNotEmpty) {
        consulta = consulta.eq('categoria', categoriaFiltro);
      }

      final subcategoriaFiltro = subcategoria.trim();
      if (subcategoriaFiltro.isNotEmpty) {
        consulta = consulta.eq('subcategoria', subcategoriaFiltro);
      }

      final termoBusca = busca.trim();
      if (termoBusca.isNotEmpty) {
        final termoSeguro = termoBusca.replaceAll("'", "''");
        consulta = consulta.or(
          'nome_produto.ilike.%$termoSeguro%,descricao.ilike.%$termoSeguro%,ean.ilike.%$termoSeguro%,codigo_barras.ilike.%$termoSeguro%,categoria.ilike.%$termoSeguro%,subcategoria.ilike.%$termoSeguro%',
        );
      }

      final resposta = await consulta
          .order('destaque', ascending: false)
          .order('nome_produto', ascending: true)
          .range(inicio, fim);

      final listaResposta = List<dynamic>.from(resposta);
      final produtos = _produtosBancoParaModelos(listaResposta);

      // ignore: avoid_print
      print(
        'APP_MERCADO BANCO_LOJA: produtos_app retornou ${produtos.length} produto(s). '
        'mercado_id=${sessao.SessaoMercadoCliente.mercadoIdObrigatorio} '
        'pagina=$paginaCorrigida limite=$limiteCorrigido consulta=$limiteConsulta busca="$termoBusca" '
        'categoria="$categoriaFiltro" subcategoria="$subcategoriaFiltro"',
      );

      if (produtos.isNotEmpty) {
        // ignore: avoid_print
        print(
          'APP_MERCADO BANCO_LOJA: primeiro produto="${produtos.first.nome}" '
          'ean="${produtos.first.ean}" preco=${produtos.first.preco}',
        );
      }

      return _filtrarCategoriasBloqueadas(produtos, configuracoes);
    } catch (e) {
      // ignore: avoid_print
      print('APP_MERCADO BANCO_LOJA ERRO produtos_app: $e');
      return [];
    }
  }

  static Future<List<String>> _listarCategoriasBancoLoja() async {
    try {
      final configuracoes =
          await LojaFuncionamentoService.buscarConfiguracoes();
      final resposta = await _supabaseLoja
          .from('produtos_app')
          .select('categoria')
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('ativo', true)
          .eq('vende_no_app', true)
          .not('categoria', 'is', null)
          .order('categoria', ascending: true);

      final categorias = <String>{};

      for (final item in resposta) {
        final categoria = item['categoria']?.toString().trim() ?? '';

        if (categoria.isNotEmpty) {
          categorias.add(categoria);
        }
      }

      final lista = categorias.toList()..sort();

      // ignore: avoid_print
      print(
        'APP_MERCADO BANCO_LOJA: categorias retornou ${lista.length} categoria(s).',
      );

      return lista
          .where((categoria) => !_categoriaBloqueada(categoria, configuracoes))
          .toList();
    } catch (e) {
      // ignore: avoid_print
      print('APP_MERCADO BANCO_LOJA ERRO categorias: $e');
      return [];
    }
  }

  static Future<List<String>> _listarSubcategoriasBancoLoja(
    String categoria,
  ) async {
    try {
      final configuracoes =
          await LojaFuncionamentoService.buscarConfiguracoes();
      if (_categoriaBloqueada(categoria, configuracoes)) {
        return [];
      }

      dynamic consulta = _supabaseLoja
          .from('produtos_app')
          .select('subcategoria')
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('ativo', true)
          .eq('vende_no_app', true)
          .not('subcategoria', 'is', null);

      final categoriaFiltro = categoria.trim();

      if (categoriaFiltro.isNotEmpty) {
        consulta = consulta.eq('categoria', categoriaFiltro);
      }

      final resposta = await consulta.order('subcategoria', ascending: true);

      final subcategorias = <String>{};

      for (final item in resposta) {
        if (item is! Map) continue;

        final subcategoria = item['subcategoria']?.toString().trim() ?? '';

        if (subcategoria.isNotEmpty) {
          subcategorias.add(subcategoria);
        }
      }

      final lista = subcategorias.toList()..sort();

      // ignore: avoid_print
      print(
        'APP_MERCADO BANCO_LOJA: subcategorias retornou ${lista.length} subcategoria(s).',
      );

      return lista;
    } catch (e) {
      // ignore: avoid_print
      print('APP_MERCADO BANCO_LOJA ERRO subcategorias: $e');
      return [];
    }
  }

  static Future<List<Produto>> listarProdutosIniciais({
    int pagina = 1,
    int limite = 20,
    String busca = '',
  }) async {
    if (_usarBancoLoja) {
      // ignore: avoid_print
      print('APP_MERCADO PRODUTOS: usando BANCO_LOJA em produtos_app');
      return _listarProdutosBancoLoja(
        pagina: pagina,
        limite: limite,
        busca: busca,
      );
    }

    try {
      return _listarProdutosApiPaginados(
        path: '/produtos',
        pagina: pagina,
        limite: limite,
        busca: busca,
      );
    } catch (_) {}

    return [];
  }

  static Future<List<Produto>> listarProdutosMaisVendidosNoApp({
    int limite = 50,
  }) async {
    final limiteCorrigido = limite < 1 ? 50 : limite;

    try {
      final resposta = await _supabaseLoja
          .from('pedido_itens')
          .select(
            'id, pedido_id, produto_id, nome_produto, ean, quantidade, preco_unitario, unidade_medida, peso_variavel, peso_medio_kg, criado_em',
          )
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .order('criado_em', ascending: false)
          .limit(1500);

      final agrupados = <String, _ProdutoVendidoApp>{};

      for (final item in resposta) {
        final dados = Map<String, dynamic>.from(item);
        final chave = _chaveProdutoVendido(dados);

        if (chave.isEmpty) continue;

        final quantidade = _numero(dados['quantidade']);
        final ultimaVenda = _dataHora(dados['criado_em']);
        final pedidoId = _chavePedidoVenda(dados);

        if (agrupados.containsKey(chave)) {
          agrupados[chave]!.registrarVenda(
            pedidoId: pedidoId,
            quantidade: quantidade,
            dataVenda: ultimaVenda,
          );
        } else {
          agrupados[chave] = _ProdutoVendidoApp(
            dados: dados,
            pedidoId: pedidoId,
            quantidadeVendida: quantidade,
            ultimaVenda: ultimaVenda,
          );
        }
      }

      final maisVendidos = agrupados.values.toList()
        ..sort((a, b) {
          final comparacaoPedidos = b.totalPedidos.compareTo(a.totalPedidos);

          if (comparacaoPedidos != 0) {
            return comparacaoPedidos;
          }

          final comparacaoQuantidade = b.quantidadeVendida.compareTo(
            a.quantidadeVendida,
          );

          if (comparacaoQuantidade != 0) {
            return comparacaoQuantidade;
          }

          return b.ultimaVenda.compareTo(a.ultimaVenda);
        });

      final produtos = <Produto>[];
      final chavesAdicionadas = <String>{};

      for (final venda in maisVendidos) {
        if (produtos.length >= limiteCorrigido) {
          break;
        }

        final produtoAtual = await _buscarProdutoAtualPorVenda(venda);

        if (produtoAtual == null) {
          continue;
        }

        final chaveProduto = _chaveProdutoModelo(produtoAtual);

        if (chaveProduto.isEmpty || chavesAdicionadas.contains(chaveProduto)) {
          continue;
        }

        chavesAdicionadas.add(chaveProduto);
        produtos.add(produtoAtual);
      }

      // ignore: avoid_print
      print(
        'APP_MERCADO MAIS_VENDIDOS_APP: retornou ${produtos.length} produto(s) '
        'de ${maisVendidos.length} produto(s) mais presentes em pedidos no app.',
      );

      return produtos;
    } catch (e) {
      // ignore: avoid_print
      print('APP_MERCADO MAIS_VENDIDOS_APP ERRO: $e');
      return [];
    }
  }

  static Future<Produto?> _buscarProdutoAtualPorVenda(
    _ProdutoVendidoApp venda,
  ) async {
    final ean = venda.ean.trim();

    if (ean.isNotEmpty) {
      final produtos = await buscarProdutos(ean);
      final produtoExato = _produtoComMesmoEan(produtos, ean);

      if (produtoExato != null) {
        return produtoExato;
      }

      if (produtos.isNotEmpty) {
        return produtos.first;
      }
    }

    final nome = venda.nome.trim();

    if (nome.isNotEmpty) {
      final produtos = await buscarProdutos(nome);
      final produtoExato = _produtoComMesmoNome(produtos, nome);

      if (produtoExato != null) {
        return produtoExato;
      }

      if (produtos.isNotEmpty) {
        return produtos.first;
      }
    }

    return null;
  }

  static Produto? _produtoComMesmoEan(List<Produto> produtos, String ean) {
    final eanNormalizado = _normalizarEan(ean);

    for (final produto in produtos) {
      if (_normalizarEan(produto.ean) == eanNormalizado) {
        return produto;
      }
    }

    return null;
  }

  static Produto? _produtoComMesmoNome(List<Produto> produtos, String nome) {
    final nomeNormalizado = _normalizarTextoBusca(nome);

    for (final produto in produtos) {
      if (_normalizarTextoBusca(produto.nome) == nomeNormalizado) {
        return produto;
      }
    }

    return null;
  }

  static String _chaveProdutoVendido(Map<String, dynamic> item) {
    final ean = _normalizarEan(_texto(item['ean']));

    if (ean.isNotEmpty) {
      return 'ean:$ean';
    }

    final nome = _normalizarNomeProduto(_texto(item['nome_produto']));

    if (nome.isNotEmpty) {
      return 'nome:$nome';
    }

    final produtoId = _inteiro(item['produto_id']);

    if (produtoId > 0) {
      return 'id:$produtoId';
    }

    return '';
  }

  static String _chavePedidoVenda(Map<String, dynamic> item) {
    final pedidoId = _texto(item['pedido_id']);

    if (pedidoId.isNotEmpty) {
      return 'pedido:$pedidoId';
    }

    final itemId = _texto(item['id']);

    if (itemId.isNotEmpty) {
      return 'item:$itemId';
    }

    final criadoEm = _texto(item['criado_em']);

    if (criadoEm.isNotEmpty) {
      return 'data:$criadoEm';
    }

    return 'sem_pedido:${DateTime.now().microsecondsSinceEpoch}';
  }

  static String _chaveProdutoModelo(Produto produto) {
    return _chaveProdutoUnico(produto);
  }

  static String _normalizarEan(String valor) {
    final apenasNumeros = valor.replaceAll(RegExp(r'[^0-9]'), '');
    return apenasNumeros.replaceFirst(RegExp(r'^0+'), '');
  }

  static String _normalizarTextoBusca(String valor) {
    return _normalizarNomeProduto(valor);
  }

  static String _normalizarNomeProduto(String valor) {
    return valor
        .trim()
        .toUpperCase()
        .replaceAll('Á', 'A')
        .replaceAll('À', 'A')
        .replaceAll('Â', 'A')
        .replaceAll('Ã', 'A')
        .replaceAll('Ä', 'A')
        .replaceAll('É', 'E')
        .replaceAll('È', 'E')
        .replaceAll('Ê', 'E')
        .replaceAll('Ë', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ì', 'I')
        .replaceAll('Î', 'I')
        .replaceAll('Ï', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ò', 'O')
        .replaceAll('Ô', 'O')
        .replaceAll('Õ', 'O')
        .replaceAll('Ö', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ù', 'U')
        .replaceAll('Û', 'U')
        .replaceAll('Ü', 'U')
        .replaceAll('Ç', 'C')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static List<Produto> _filtrarProdutosPorBuscaPrecisa(
    List<Produto> produtos,
    String termo,
  ) {
    final termoNormalizado = _normalizarNomeProduto(termo);
    final termoNumerico = _normalizarEan(termo);

    if (termoNormalizado.isEmpty && termoNumerico.isEmpty) {
      return produtos;
    }

    final palavras = termoNormalizado
        .split(' ')
        .map((item) => item.trim())
        .where((item) => item.length > 1)
        .toList();

    return produtos.where((produto) {
      final nomeNormalizado = _normalizarNomeProduto(produto.nome);
      final eanNormalizado = _normalizarEan(produto.ean);

      if (termoNumerico.isNotEmpty &&
          eanNormalizado.isNotEmpty &&
          eanNormalizado.contains(termoNumerico)) {
        return true;
      }

      if (palavras.isEmpty) {
        return termoNormalizado.isEmpty ||
            nomeNormalizado.contains(termoNormalizado);
      }

      return palavras.every(nomeNormalizado.contains);
    }).toList();
  }

  static List<Produto> _filtrarProdutosPorBuscaNumerica(
    List<Produto> produtos,
    String termoOriginal,
    String termoBusca,
  ) {
    final termoOriginalNormalizado = _normalizarEan(termoOriginal);
    final termoBuscaNormalizado = _normalizarEan(termoBusca);

    if (termoOriginalNormalizado.isEmpty && termoBuscaNormalizado.isEmpty) {
      return produtos;
    }

    return produtos.where((produto) {
      final eanProduto = _normalizarEan(produto.ean);

      if (eanProduto.isEmpty) {
        return false;
      }

      return eanProduto == termoOriginalNormalizado ||
          eanProduto == termoBuscaNormalizado ||
          eanProduto.endsWith(termoOriginalNormalizado) ||
          eanProduto.contains(termoOriginalNormalizado);
    }).toList();
  }

  static String _texto(dynamic valor) {
    return valor?.toString().trim() ?? '';
  }

  static int _inteiro(dynamic valor) {
    return _numero(valor).round();
  }

  static double _numero(dynamic valor) {
    if (valor == null) {
      return 0;
    }

    if (valor is num) {
      return valor.toDouble();
    }

    var texto = valor.toString().trim();

    if (texto.isEmpty) {
      return 0;
    }

    texto = texto.replaceAll('R\$', '').replaceAll(' ', '').trim();

    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else {
      texto = texto.replaceAll(',', '.');
    }

    return double.tryParse(texto) ?? 0;
  }

  static DateTime _dataHora(dynamic valor) {
    if (valor == null) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return DateTime.tryParse(valor.toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static Future<List<Produto>> buscarProdutos(String busca) async {
    if (_usarBancoLoja) {
      // ignore: avoid_print
      print('APP_MERCADO PRODUTOS: usando BANCO_LOJA busca=$busca');
      return _listarProdutosBancoLoja(busca: busca, limite: 60);
    }

    final termoOriginal = busca.trim();

    if (termoOriginal.isEmpty) {
      return listarProdutosIniciais();
    }

    final ehNumerico = RegExp(r'^[0-9]+$').hasMatch(termoOriginal);

    String termoBusca = termoOriginal;

    if (ehNumerico && termoOriginal.length < 14) {
      termoBusca = termoOriginal.padLeft(14, '0');
    }

    // IMPORTANTE:
    // Antes havia uma segunda tentativa em /produto?busca=...
    // Em algumas APIs essa rota retorna a listagem normal quando não encontra
    // o termo, causando produtos aleatórios para buscas como "fralda".
    //
    // Agora a busca textual usa apenas /produto/descricao e ainda filtra
    // localmente pelo termo digitado. Assim, "fralda" só mostra produtos
    // cujo nome realmente contenha "fralda".
    final urls = ehNumerico
        ? [_uri('/produto/ean/${Uri.encodeComponent(termoBusca)}')]
        : [_uri('/produto/descricao/${Uri.encodeComponent(termoBusca)}')];

    for (final url in urls) {
      try {
        final response = await _get(url);

        if (response.statusCode == 200) {
          var produtos =
              await ProdutoConfiguracaoAppService.aplicarConfiguracoes(
                _converterResposta(response.body),
              );

          produtos = removerProdutosDuplicados(produtos);

          produtos = ehNumerico
              ? _filtrarProdutosPorBuscaNumerica(
                  produtos,
                  termoOriginal,
                  termoBusca,
                )
              : _filtrarProdutosPorBuscaPrecisa(produtos, termoOriginal);

          if (produtos.isNotEmpty) {
            return aplicarFiltroEstoqueApp(produtos);
          }
        }
      } catch (_) {}
    }

    return [];
  }

  static Future<Produto?> buscarProdutoExatoParaOferta({
    required String ean,
    required String produtoId,
    required String nome,
  }) async {
    if (_usarBancoLoja) {
      return _buscarProdutoExatoBancoLoja(
        ean: ean,
        produtoId: produtoId,
        nome: nome,
      );
    }

    final eanLimpo = ean.trim();

    if (eanLimpo.isNotEmpty) {
      final tentativas = <String>[eanLimpo];
      final apenasNumeros = RegExp(r'^[0-9]+$').hasMatch(eanLimpo);

      if (apenasNumeros && eanLimpo.length < 14) {
        tentativas.add(eanLimpo.padLeft(14, '0'));
      }

      for (final tentativa in tentativas.toSet()) {
        try {
          final response = await _get(
            _uri('/produto/ean/${Uri.encodeComponent(tentativa)}'),
          );

          if (response.statusCode != 200) {
            continue;
          }

          final produtos =
              await ProdutoConfiguracaoAppService.aplicarConfiguracoes(
                _converterResposta(response.body),
              );
          final produtoExato = _produtoComMesmoEan(produtos, eanLimpo);

          if (produtoExato != null) {
            return produtoExato;
          }
        } catch (_) {}
      }

      return null;
    }

    final produtoIdLimpo = produtoId.trim();

    if (produtoIdLimpo.isNotEmpty) {
      try {
        final produtos = await _buscarProdutosApiPagina(
          path: '/produtos',
          pagina: 1,
          limite: 20,
          busca: produtoIdLimpo,
        );
        final produtoIdNormalizado = _normalizarEan(produtoIdLimpo);

        for (final produto in produtos) {
          if (_normalizarEan(produto.produtoId.toString()) ==
              produtoIdNormalizado) {
            return produto;
          }
        }
      } catch (_) {}

      return null;
    }

    final nomeLimpo = nome.trim();

    if (nomeLimpo.isNotEmpty) {
      try {
        final response = await _get(
          _uri('/produto/descricao/${Uri.encodeComponent(nomeLimpo)}'),
        );

        if (response.statusCode == 200) {
          final produtos =
              await ProdutoConfiguracaoAppService.aplicarConfiguracoes(
                _converterResposta(response.body),
              );
          return _produtoComMesmoNome(produtos, nomeLimpo);
        }
      } catch (_) {}
    }

    return null;
  }

  static Future<Produto?> _buscarProdutoExatoBancoLoja({
    required String ean,
    required String produtoId,
    required String nome,
  }) async {
    try {
      final eanLimpo = ean.trim();

      if (eanLimpo.isNotEmpty) {
        final porEan = await _supabaseLoja
            .from('produtos_app')
            .select()
            .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
            .eq('ativo', true)
            .eq('vende_no_app', true)
            .eq('ean', eanLimpo)
            .limit(1);

        final produtosPorEan = _produtosBancoParaModelos(
          List<dynamic>.from(porEan),
        );

        if (produtosPorEan.isNotEmpty) {
          return produtosPorEan.first;
        }

        final porCodigoBarras = await _supabaseLoja
            .from('produtos_app')
            .select()
            .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
            .eq('ativo', true)
            .eq('vende_no_app', true)
            .eq('codigo_barras', eanLimpo)
            .limit(1);

        final produtosPorCodigoBarras = _produtosBancoParaModelos(
          List<dynamic>.from(porCodigoBarras),
        );

        if (produtosPorCodigoBarras.isNotEmpty) {
          return produtosPorCodigoBarras.first;
        }

        return null;
      }

      final produtoIdLimpo = produtoId.trim();

      if (produtoIdLimpo.isNotEmpty) {
        final porProdutoId = await _supabaseLoja
            .from('produtos_app')
            .select()
            .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
            .eq('ativo', true)
            .eq('vende_no_app', true)
            .eq('produto_id', produtoIdLimpo)
            .limit(1);

        final produtosPorProdutoId = _produtosBancoParaModelos(
          List<dynamic>.from(porProdutoId),
        );

        if (produtosPorProdutoId.isNotEmpty) {
          return produtosPorProdutoId.first;
        }

        return null;
      }

      final nomeLimpo = nome.trim();

      if (nomeLimpo.isNotEmpty) {
        final porNome = await _supabaseLoja
            .from('produtos_app')
            .select()
            .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
            .eq('ativo', true)
            .eq('vende_no_app', true)
            .eq('nome_produto', nomeLimpo)
            .limit(1);

        final produtosPorNome = _produtosBancoParaModelos(
          List<dynamic>.from(porNome),
        );

        if (produtosPorNome.isNotEmpty) {
          return produtosPorNome.first;
        }
      }
    } catch (_) {}

    return null;
  }

  static Future<List<String>> listarCategorias() async {
    if (_usarBancoLoja) {
      // ignore: avoid_print
      print('APP_MERCADO PRODUTOS: usando BANCO_LOJA categorias');
      return _listarCategoriasBancoLoja();
    }

    try {
      final url = _uri('/categorias');

      final response = await _get(url);

      if (response.statusCode == 200) {
        final dados = jsonDecode(response.body);

        if (dados is Map && dados['categorias'] is List) {
          final configuracoes =
              await LojaFuncionamentoService.buscarConfiguracoes();
          return (dados['categorias'] as List)
              .map((item) {
                if (item is Map && item['nome_grupo'] != null) {
                  return item['nome_grupo'].toString();
                }

                return item.toString();
              })
              .where((categoria) => categoria.trim().isNotEmpty)
              .where(
                (categoria) => !_categoriaBloqueada(categoria, configuracoes),
              )
              .toList();
        }

        if (dados is List) {
          final configuracoes =
              await LojaFuncionamentoService.buscarConfiguracoes();
          return dados
              .map((item) {
                if (item is Map && item['nome_grupo'] != null) {
                  return item['nome_grupo'].toString();
                }

                return item.toString();
              })
              .where((categoria) => categoria.trim().isNotEmpty)
              .where(
                (categoria) => !_categoriaBloqueada(categoria, configuracoes),
              )
              .toList();
        }
      }
    } catch (_) {}

    return [];
  }

  static Future<List<String>> listarSubcategoriasPorCategoria(
    String categoria,
  ) async {
    final configuracoes = await LojaFuncionamentoService.buscarConfiguracoes();
    if (_categoriaBloqueada(categoria, configuracoes)) {
      return [];
    }

    if (_usarBancoLoja) {
      // ignore: avoid_print
      print(
        'APP_MERCADO PRODUTOS: usando BANCO_LOJA subcategorias categoria=$categoria',
      );
      return _listarSubcategoriasBancoLoja(categoria);
    }

    try {
      final url = _uri('/categorias-com-subcategorias');

      final response = await _get(url);

      if (response.statusCode == 200) {
        final dados = jsonDecode(response.body);

        if (dados is Map && dados['categorias'] is List) {
          final categorias = List<Map<String, dynamic>>.from(
            (dados['categorias'] as List).map(
              (item) => Map<String, dynamic>.from(item as Map),
            ),
          );

          final categoriaEncontrada = categorias.firstWhere(
            (item) =>
                item['nome_grupo'].toString().toUpperCase() ==
                categoria.toUpperCase(),
            orElse: () => {},
          );

          if (categoriaEncontrada.isEmpty) {
            return [];
          }

          if (categoriaEncontrada['subcategorias'] is List) {
            return (categoriaEncontrada['subcategorias'] as List)
                .map((item) {
                  if (item is Map && item['nome_subgrupo'] != null) {
                    return item['nome_subgrupo'].toString();
                  }

                  return item.toString();
                })
                .where((subcategoria) => subcategoria.trim().isNotEmpty)
                .toList();
          }
        }
      }
    } catch (_) {}

    return [];
  }

  static Future<List<Produto>> listarProdutosPorCategoria({
    required String categoria,
    int pagina = 1,
    int limite = 20,
    String busca = '',
  }) async {
    final configuracoes = await LojaFuncionamentoService.buscarConfiguracoes();
    if (_categoriaBloqueada(categoria, configuracoes)) {
      return [];
    }

    if (_usarBancoLoja) {
      // ignore: avoid_print
      print('APP_MERCADO PRODUTOS: usando BANCO_LOJA categoria=$categoria');
      return _listarProdutosBancoLoja(
        categoria: categoria,
        pagina: pagina,
        limite: limite,
        busca: busca,
      );
    }

    try {
      return _listarProdutosApiPaginados(
        path: '/produtos/categoria/${Uri.encodeComponent(categoria)}',
        pagina: pagina,
        limite: limite,
        busca: busca,
      );
    } catch (_) {}

    return [];
  }

  static Future<List<Produto>> listarProdutosPorSubcategoria({
    required String subcategoria,
    int pagina = 1,
    int limite = 20,
    String busca = '',
  }) async {
    if (_usarBancoLoja) {
      // ignore: avoid_print
      print(
        'APP_MERCADO PRODUTOS: usando BANCO_LOJA subcategoria=$subcategoria',
      );
      return _listarProdutosBancoLoja(
        subcategoria: subcategoria,
        pagina: pagina,
        limite: limite,
        busca: busca,
      );
    }

    try {
      return _listarProdutosApiPaginados(
        path: '/produtos/subcategoria/${Uri.encodeComponent(subcategoria)}',
        pagina: pagina,
        limite: limite,
        busca: busca,
      );
    } catch (_) {}

    return [];
  }

  static Future<Produto?> buscarProdutoAtualizado(Produto produto) async {
    try {
      final ean = produto.ean.trim();

      if (ean.isNotEmpty) {
        final produtos = await buscarProdutos(ean);

        if (produtos.isNotEmpty) {
          return produtos.first;
        }
      }

      final nome = produto.nome.trim();

      if (nome.isNotEmpty) {
        final produtos = await buscarProdutos(nome);

        if (produtos.isNotEmpty) {
          return produtos.first;
        }
      }
    } catch (_) {}

    return null;
  }

  static List<Produto> _converterResposta(String body) {
    if (body.trim().isEmpty) {
      return [];
    }

    final dados = jsonDecode(body);

    if (dados is List) {
      return removerProdutosDuplicados(
        dados
            .whereType<Map>()
            .map((item) => Produto.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      );
    }

    if (dados is Map && dados['produtos'] is List) {
      return removerProdutosDuplicados(
        (dados['produtos'] as List)
            .whereType<Map>()
            .map((item) => Produto.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      );
    }

    if (dados is Map && dados['produto'] is Map) {
      return removerProdutosDuplicados([
        Produto.fromJson(Map<String, dynamic>.from(dados['produto'] as Map)),
      ]);
    }

    if (dados is Map && dados.isNotEmpty && dados.containsKey('produto_id')) {
      return removerProdutosDuplicados([
        Produto.fromJson(Map<String, dynamic>.from(dados)),
      ]);
    }

    return [];
  }
}

class _ProdutoVendidoApp {
  final Map<String, dynamic> dados;
  final Set<String> pedidosIds;
  double quantidadeVendida;
  DateTime ultimaVenda;

  _ProdutoVendidoApp({
    required this.dados,
    required String pedidoId,
    required this.quantidadeVendida,
    required this.ultimaVenda,
  }) : pedidosIds = <String>{pedidoId};

  String get ean => dados['ean']?.toString().trim() ?? '';

  String get nome => dados['nome_produto']?.toString().trim() ?? '';

  int get totalPedidos => pedidosIds.length;

  void registrarVenda({
    required String pedidoId,
    required double quantidade,
    required DateTime dataVenda,
  }) {
    pedidosIds.add(pedidoId);
    quantidadeVendida += quantidade;

    if (dataVenda.isAfter(ultimaVenda)) {
      ultimaVenda = dataVenda;
    }
  }
}

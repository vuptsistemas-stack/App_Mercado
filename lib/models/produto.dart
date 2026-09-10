class Produto {
  final int produtoId;
  final String nome;
  final String ean;
  final double preco;
  final double estoque;
  final String unidadeMedida;
  final bool pesoVariavel;
  final double pesoMedioKg;
  final String produtoAppId;
  final String categoria;
  final String subcategoria;
  final String categoriaApi;
  final String subcategoriaApi;
  final String ncm;
  final int ordemCategoria;
  final int ordemSubcategoria;

  /// Campo opcional para quando a API já retornar uma imagem.
  /// No fluxo atual, as imagens continuam vindo pelo ImagemService/Central.
  final String imagemUrl;

  Produto({
    required this.produtoId,
    required this.nome,
    required this.ean,
    required this.preco,
    required this.estoque,
    this.unidadeMedida = 'UN',
    this.pesoVariavel = false,
    this.pesoMedioKg = 0,
    this.produtoAppId = '',
    this.categoria = '',
    this.subcategoria = '',
    this.categoriaApi = '',
    this.subcategoriaApi = '',
    this.ncm = '',
    this.ordemCategoria = 0,
    this.ordemSubcategoria = 0,
    this.imagemUrl = '',
  });

  factory Produto.fromJson(Map<String, dynamic> json) {
    final categoriaApi = _texto(
      json['categoria_api'] ??
          json['categoria'] ??
          json['nome_grupo'] ??
          json['grupo'] ??
          json['categoria_nome'],
    );
    final subcategoriaApi = _texto(
      json['subcategoria_api'] ??
          json['subcategoria'] ??
          json['nome_subgrupo'] ??
          json['subgrupo'] ??
          json['subcategoria_nome'],
    );

    return Produto(
      produtoId: _inteiro(
        json['produto_id'] ??
            json['produtoId'] ??
            json['id'] ??
            json['codigo'] ??
            json['cod_produto'],
      ),
      nome: _texto(
        json['nome_produto'] ??
            json['descricao'] ??
            json['nome'] ??
            json['produto'] ??
            json['desc_produto'],
      ),
      ean: _texto(
        json['ean_principal'] ??
            json['ean'] ??
            json['codigo_barras'] ??
            json['codigo_barra'] ??
            json['cod_barras'] ??
            json['gtin'],
      ),
      preco: _numero(
        json['preco_venda'] ??
            json['preco'] ??
            json['preco_unitario'] ??
            json['valor'] ??
            json['valor_venda'],
      ),
      estoque: _numero(
        json['estoque_atual'] ??
            json['estoque'] ??
            json['quantidade'] ??
            json['saldo_estoque'] ??
            json['qtd_estoque'],
      ),
      unidadeMedida: _normalizarUnidade(
        json['sigla_saida'] ??
            json['siglaSaida'] ??
            json['unidade_medida'] ??
            json['unidadeMedida'] ??
            json['unidade'] ??
            json['sigla_unidade'] ??
            json['unidade_sigla'] ??
            json['un'] ??
            json['um'],
      ),
      pesoVariavel: _booleano(
        json['peso_variavel'] ??
            json['pesoVariavel'] ??
            json['produto_peso_variavel'],
      ),
      pesoMedioKg: _numero(
        json['peso_medio_kg'] ?? json['pesoMedioKg'] ?? json['peso_medio'],
      ),
      produtoAppId: _texto(
        json['produto_app_id'] ??
            json['produtoAppId'] ??
            json['produtos_app_id'] ??
            json['id_produto_app'],
      ),
      categoria: categoriaApi,
      subcategoria: subcategoriaApi,
      categoriaApi: categoriaApi,
      subcategoriaApi: subcategoriaApi,
      ncm: _texto(
        json['ncm'] ??
            json['NCM'] ??
            json['codigo_ncm'] ??
            json['codigoNcm'] ??
            json['cod_ncm'] ??
            json['ncm_codigo'] ??
            json['classificacao_fiscal'] ??
            json['classificacaoFiscal'],
      ),
      ordemCategoria: _inteiro(json['ordem_categoria']),
      ordemSubcategoria: _inteiro(json['ordem_subcategoria']),
      imagemUrl: _texto(
        json['imagem_url'] ??
            json['imagemUrl'] ??
            json['image_url'] ??
            json['url_imagem'] ??
            json['foto'],
      ),
    );
  }

  bool get ehKg {
    final unidade = _normalizarUnidade(unidadeMedida);

    return unidade == 'KG' ||
        unidade == 'KGS' ||
        unidade == 'KILO' ||
        unidade == 'KILOS' ||
        unidade == 'QUILO' ||
        unidade == 'QUILOS' ||
        unidade == 'KILOGRAMA' ||
        unidade == 'KILOGRAMAS';
  }

  bool get ehUnidade => !ehKg;

  String get unidadeNormalizada {
    final unidade = _normalizarUnidade(unidadeMedida);
    return unidade.isEmpty ? 'UN' : unidade;
  }

  String get precoRotulo {
    if (ehKg) {
      return '${_moeda(preco)}/kg';
    }

    return _moeda(preco);
  }

  double pesoEstimadoKgParaQuantidade(int quantidade) {
    if (!ehKg || quantidade <= 0) {
      return 0;
    }

    if (pesoVariavel) {
      final double pesoMedio = pesoMedioKg > 0 ? pesoMedioKg : 1.0;
      return pesoMedio * quantidade;
    }

    return quantidade * 0.100;
  }

  double totalParaQuantidade(int quantidade) {
    if (quantidade <= 0) {
      return 0;
    }

    if (ehKg) {
      return preco * pesoEstimadoKgParaQuantidade(quantidade);
    }

    return preco * quantidade;
  }

  String textoQuantidadeCarrinho(int quantidade) {
    if (quantidade <= 0) {
      return '';
    }

    if (ehKg && pesoVariavel) {
      return '$quantidade ${quantidade == 1 ? 'unidade' : 'unidades'}';
    }

    if (ehKg) {
      final kg = pesoEstimadoKgParaQuantidade(quantidade);
      return _formatarPeso(kg);
    }

    return '$quantidade';
  }

  String textoQuantidadeCurto(int quantidade) {
    if (quantidade <= 0) {
      return '';
    }

    if (ehKg && pesoVariavel) {
      return '$quantidade un';
    }

    if (ehKg) {
      return _formatarPeso(pesoEstimadoKgParaQuantidade(quantidade));
    }

    return '$quantidade';
  }

  String get textoRegraVenda {
    if (ehKg && pesoVariavel) {
      final double pesoMedio = pesoMedioKg > 0 ? pesoMedioKg : 1.0;
      return 'Peso variável • média ${_formatarPeso(pesoMedio)}';
    }

    if (ehKg) {
      return 'Venda de 100g em 100g';
    }

    return 'Venda por unidade';
  }

  Map<String, dynamic> toJson() {
    return {
      'produto_id': produtoId,
      'nome_produto': nome,
      'ean_principal': ean,
      'preco_venda': preco,
      'estoque_atual': estoque,
      'unidade_medida': unidadeMedida,
      'peso_variavel': pesoVariavel,
      'peso_medio_kg': pesoMedioKg,
      'produto_app_id': produtoAppId,
      'categoria': categoria,
      'subcategoria': subcategoria,
      'categoria_api': categoriaApi,
      'subcategoria_api': subcategoriaApi,
      'ncm': ncm,
      'ordem_categoria': ordemCategoria,
      'ordem_subcategoria': ordemSubcategoria,
      'imagem_url': imagemUrl,
    };
  }

  Produto copyWith({
    int? produtoId,
    String? nome,
    String? ean,
    double? preco,
    double? estoque,
    String? unidadeMedida,
    bool? pesoVariavel,
    double? pesoMedioKg,
    String? produtoAppId,
    String? categoria,
    String? subcategoria,
    String? categoriaApi,
    String? subcategoriaApi,
    String? ncm,
    int? ordemCategoria,
    int? ordemSubcategoria,
    String? imagemUrl,
  }) {
    return Produto(
      produtoId: produtoId ?? this.produtoId,
      nome: nome ?? this.nome,
      ean: ean ?? this.ean,
      preco: preco ?? this.preco,
      estoque: estoque ?? this.estoque,
      unidadeMedida: unidadeMedida ?? this.unidadeMedida,
      pesoVariavel: pesoVariavel ?? this.pesoVariavel,
      pesoMedioKg: pesoMedioKg ?? this.pesoMedioKg,
      produtoAppId: produtoAppId ?? this.produtoAppId,
      categoria: categoria ?? this.categoria,
      subcategoria: subcategoria ?? this.subcategoria,
      categoriaApi: categoriaApi ?? this.categoriaApi,
      subcategoriaApi: subcategoriaApi ?? this.subcategoriaApi,
      ncm: ncm ?? this.ncm,
      ordemCategoria: ordemCategoria ?? this.ordemCategoria,
      ordemSubcategoria: ordemSubcategoria ?? this.ordemSubcategoria,
      imagemUrl: imagemUrl ?? this.imagemUrl,
    );
  }

  static String _texto(dynamic valor) {
    if (valor == null) {
      return '';
    }

    return valor.toString().trim();
  }

  static String _normalizarUnidade(dynamic valor) {
    final texto = _texto(valor)
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

    return texto.isEmpty ? 'UN' : texto;
  }

  static bool _booleano(dynamic valor) {
    if (valor is bool) {
      return valor;
    }

    if (valor is num) {
      return valor == 1;
    }

    final texto = _texto(valor).toLowerCase();

    return texto == 'true' ||
        texto == '1' ||
        texto == 'sim' ||
        texto == 's' ||
        texto == 'yes';
  }

  static int _inteiro(dynamic valor) {
    if (valor == null) {
      return 0;
    }

    if (valor is int) {
      return valor;
    }

    if (valor is num) {
      return valor.toInt();
    }

    final texto = valor.toString().trim();

    if (texto.isEmpty) {
      return 0;
    }

    return int.tryParse(texto) ??
        double.tryParse(texto.replaceAll(',', '.'))?.toInt() ??
        0;
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

  static String _moeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  static String _formatarPeso(double kg) {
    if (kg <= 0) {
      return '0g';
    }

    if (kg < 1) {
      final gramas = (kg * 1000).round();
      return '${gramas}g';
    }

    var texto = kg.toStringAsFixed(3).replaceAll('.', ',');

    while (texto.endsWith('0')) {
      texto = texto.substring(0, texto.length - 1);
    }

    if (texto.endsWith(',')) {
      texto = texto.substring(0, texto.length - 1);
    }

    return '${texto}kg';
  }
}

class ConfiguracaoEtiquetaBalanca {
  final bool habilitada;
  final String prefixo;
  final String tipoValor;
  final int tamanhoCodigo;
  final int tamanhoValor;
  final int casasDecimais;
  final bool validarDigitoVerificador;

  const ConfiguracaoEtiquetaBalanca({
    required this.habilitada,
    required this.prefixo,
    required this.tipoValor,
    required this.tamanhoCodigo,
    required this.tamanhoValor,
    required this.casasDecimais,
    required this.validarDigitoVerificador,
  });

  factory ConfiguracaoEtiquetaBalanca.fromMap(Map<String, dynamic> dados) {
    int inteiro(dynamic valor, int fallback) {
      return int.tryParse(valor?.toString() ?? '') ?? fallback;
    }

    bool booleano(dynamic valor, bool fallback) {
      if (valor is bool) return valor;
      final texto = valor?.toString().trim().toLowerCase() ?? '';
      if (['true', '1', 'sim', 's'].contains(texto)) return true;
      if (['false', '0', 'nao', 'não', 'n'].contains(texto)) return false;
      return fallback;
    }

    final tipo = dados['etiqueta_balanca_tipo_valor']
        ?.toString()
        .trim()
        .toUpperCase();

    return ConfiguracaoEtiquetaBalanca(
      habilitada: booleano(dados['etiqueta_balanca_habilitada'], false),
      prefixo: dados['etiqueta_balanca_prefixo']?.toString().trim() ?? '2',
      tipoValor: tipo == 'PESO' ? 'PESO' : 'PRECO',
      tamanhoCodigo: inteiro(dados['etiqueta_balanca_tamanho_codigo'], 6),
      tamanhoValor: inteiro(dados['etiqueta_balanca_tamanho_valor'], 5),
      casasDecimais: inteiro(dados['etiqueta_balanca_casas_decimais'], 2),
      validarDigitoVerificador: booleano(
        dados['etiqueta_balanca_validar_dv'],
        true,
      ),
    );
  }

  String? validar() {
    if (!RegExp(r'^\d{1,3}$').hasMatch(prefixo)) {
      return 'O prefixo deve conter de 1 a 3 números.';
    }
    if (tipoValor != 'PRECO' && tipoValor != 'PESO') {
      return 'O conteúdo da etiqueta deve ser PRECO ou PESO.';
    }
    if (tamanhoCodigo <= 0 || tamanhoValor <= 0) {
      return 'Os tamanhos do código e do valor devem ser maiores que zero.';
    }
    if (prefixo.length + tamanhoCodigo + tamanhoValor != 12) {
      return 'Prefixo + código do produto + valor devem ocupar 12 dígitos antes do dígito verificador.';
    }
    if (casasDecimais < 0 || casasDecimais > 4) {
      return 'As casas decimais devem ficar entre 0 e 4.';
    }
    return null;
  }

  bool pareceEtiqueta(String codigo) {
    final numeros = codigo.replaceAll(RegExp(r'\D'), '');
    return habilitada && numeros.length == 13 && numeros.startsWith(prefixo);
  }
}

class ResultadoEtiquetaBalanca {
  final String codigoCompleto;
  final String codigoProduto;
  final String valorBruto;
  final double valorInterpretado;
  final String tipoValor;
  final int digitoVerificador;

  const ResultadoEtiquetaBalanca({
    required this.codigoCompleto,
    required this.codigoProduto,
    required this.valorBruto,
    required this.valorInterpretado,
    required this.tipoValor,
    required this.digitoVerificador,
  });
}

class EtiquetaBalancaException implements Exception {
  final String mensagem;

  const EtiquetaBalancaException(this.mensagem);

  @override
  String toString() => mensagem;
}

class EtiquetaBalancaService {
  const EtiquetaBalancaService._();

  static ResultadoEtiquetaBalanca interpretar(
    String codigo,
    ConfiguracaoEtiquetaBalanca configuracao,
  ) {
    final erroConfiguracao = configuracao.validar();
    if (erroConfiguracao != null) {
      throw EtiquetaBalancaException(erroConfiguracao);
    }

    final numeros = codigo.replaceAll(RegExp(r'\D'), '');
    if (numeros.length != 13) {
      throw const EtiquetaBalancaException(
        'A etiqueta de balança deve possuir 13 dígitos.',
      );
    }
    if (!numeros.startsWith(configuracao.prefixo)) {
      throw EtiquetaBalancaException(
        'A etiqueta não começa com o prefixo ${configuracao.prefixo}.',
      );
    }

    if (configuracao.validarDigitoVerificador &&
        !digitoVerificadorValido(numeros)) {
      throw const EtiquetaBalancaException(
        'Dígito verificador inválido. Confira a leitura da etiqueta.',
      );
    }

    final inicioCodigo = configuracao.prefixo.length;
    final fimCodigo = inicioCodigo + configuracao.tamanhoCodigo;
    final fimValor = fimCodigo + configuracao.tamanhoValor;

    final codigoProduto = numeros.substring(inicioCodigo, fimCodigo);
    final valorBruto = numeros.substring(fimCodigo, fimValor);
    final divisor = potenciaDeDez(configuracao.casasDecimais);
    final valorInterpretado = int.parse(valorBruto) / divisor;

    return ResultadoEtiquetaBalanca(
      codigoCompleto: numeros,
      codigoProduto: codigoProduto,
      valorBruto: valorBruto,
      valorInterpretado: valorInterpretado,
      tipoValor: configuracao.tipoValor,
      digitoVerificador: int.parse(numeros.substring(12)),
    );
  }

  static bool digitoVerificadorValido(String codigo) {
    final numeros = codigo.replaceAll(RegExp(r'\D'), '');
    if (numeros.length != 13) return false;
    return calcularDigitoVerificador(numeros.substring(0, 12)) ==
        int.tryParse(numeros.substring(12));
  }

  static int calcularDigitoVerificador(String base) {
    final numeros = base.replaceAll(RegExp(r'\D'), '');
    if (numeros.length != 12) {
      throw const EtiquetaBalancaException(
        'A base do EAN-13 deve possuir 12 dígitos.',
      );
    }

    var soma = 0;
    for (var indice = 0; indice < numeros.length; indice++) {
      final digito = int.parse(numeros[indice]);
      soma += digito * (indice.isEven ? 1 : 3);
    }

    return (10 - (soma % 10)) % 10;
  }

  static int potenciaDeDez(int expoente) {
    var resultado = 1;
    for (var i = 0; i < expoente; i++) {
      resultado *= 10;
    }
    return resultado;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:app_preco/services/etiqueta_balanca_service.dart';

void main() {
  const configuracaoPreco = ConfiguracaoEtiquetaBalanca(
    habilitada: true,
    prefixo: '2',
    tipoValor: 'PRECO',
    tamanhoCodigo: 6,
    tamanhoValor: 5,
    casasDecimais: 2,
    validarDigitoVerificador: true,
  );

  String montarEan13(String base) {
    return '$base${EtiquetaBalancaService.calcularDigitoVerificador(base)}';
  }

  test('interpreta codigo interno e preco total da etiqueta', () {
    final codigo = montarEan13('200123401599');
    final resultado = EtiquetaBalancaService.interpretar(
      codigo,
      configuracaoPreco,
    );

    expect(resultado.codigoProduto, '001234');
    expect(resultado.valorInterpretado, 15.99);
    expect(resultado.tipoValor, 'PRECO');
  });

  test('interpreta peso com tres casas decimais', () {
    const configuracaoPeso = ConfiguracaoEtiquetaBalanca(
      habilitada: true,
      prefixo: '2',
      tipoValor: 'PESO',
      tamanhoCodigo: 6,
      tamanhoValor: 5,
      casasDecimais: 3,
      validarDigitoVerificador: true,
    );
    final codigo = montarEan13('200123400125');
    final resultado = EtiquetaBalancaService.interpretar(
      codigo,
      configuracaoPeso,
    );

    expect(resultado.codigoProduto, '001234');
    expect(resultado.valorInterpretado, 0.125);
    expect(resultado.tipoValor, 'PESO');
  });

  test('recusa etiqueta com digito verificador incorreto', () {
    final codigoValido = montarEan13('200123401599');
    final ultimo = int.parse(codigoValido.substring(12));
    final codigoInvalido =
        '${codigoValido.substring(0, 12)}${(ultimo + 1) % 10}';

    expect(
      () =>
          EtiquetaBalancaService.interpretar(codigoInvalido, configuracaoPreco),
      throwsA(isA<EtiquetaBalancaException>()),
    );
  });

  test('exige doze digitos antes do DV na configuracao', () {
    const configuracaoInvalida = ConfiguracaoEtiquetaBalanca(
      habilitada: true,
      prefixo: '2',
      tipoValor: 'PRECO',
      tamanhoCodigo: 5,
      tamanhoValor: 5,
      casasDecimais: 2,
      validarDigitoVerificador: true,
    );

    expect(configuracaoInvalida.validar(), isNotNull);
  });
}

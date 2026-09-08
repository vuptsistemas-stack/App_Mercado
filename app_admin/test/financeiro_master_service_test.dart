import 'package:app_preco/services/financeiro_master_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FinanceiroMasterService.calcularMensalidade', () {
    test('aplica os valores fixos nos limites das faixas', () {
      expect(FinanceiroMasterService.calcularMensalidade(15000), 159.90);
      expect(FinanceiroMasterService.calcularMensalidade(15000.01), 189.90);
      expect(FinanceiroMasterService.calcularMensalidade(30000), 189.90);
      expect(FinanceiroMasterService.calcularMensalidade(45000), 219.90);
      expect(FinanceiroMasterService.calcularMensalidade(60000), 249.90);
      expect(FinanceiroMasterService.calcularMensalidade(75000), 279.90);
      expect(FinanceiroMasterService.calcularMensalidade(90000), 309.90);
      expect(FinanceiroMasterService.calcularMensalidade(100000), 339.90);
    });

    test('cobra 0,25 por cento apenas sobre o excedente de 100 mil', () {
      expect(FinanceiroMasterService.calcularMensalidade(120000), 389.90);
    });
  });

  test('primeiro mes usa faturamento equivalente e proporcionalidade', () {
    final resultado = FinanceiroMasterService.simularPlano(
      faturamento: 7500,
      diasAtivos: 15,
      diasNoMes: 30,
      adicionais: 20,
      implantacao: 590,
    );

    expect(resultado['faturamento_equivalente'], 15000);
    expect(resultado['mensalidade'], 79.95);
    expect(resultado['adicionais'], 10);
    expect(resultado['implantacao'], 590);
    expect(resultado['total'], 679.95);
  });
}

import 'produto.dart';

class CarrinhoItem {
  Produto produto;
  int quantidade;

  CarrinhoItem({
    required this.produto,
    required this.quantidade,
  });

  factory CarrinhoItem.fromJson(Map<String, dynamic> json) {
    return CarrinhoItem(
      produto: Produto.fromJson(
        Map<String, dynamic>.from(json['produto'] ?? {}),
      ),
      quantidade: _inteiro(json['quantidade']),
    );
  }

  double get total {
    return produto.totalParaQuantidade(quantidade);
  }

  double get pesoEstimadoKg {
    return produto.pesoEstimadoKgParaQuantidade(quantidade);
  }

  bool get pesoVariavel {
    return produto.ehKg && produto.pesoVariavel;
  }

  bool get produtoKg {
    return produto.ehKg;
  }

  String get textoQuantidade {
    return produto.textoQuantidadeCarrinho(quantidade);
  }

  String get textoQuantidadeCurto {
    return produto.textoQuantidadeCurto(quantidade);
  }

  String get textoPrecoQuantidade {
    if (produto.ehKg && produto.pesoVariavel) {
      return '${produto.precoRotulo} • $textoQuantidade • estimado ${_formatarPeso(pesoEstimadoKg)}';
    }

    if (produto.ehKg) {
      return '${produto.precoRotulo} • $textoQuantidade';
    }

    return '${produto.precoRotulo} x $quantidade';
  }

  Map<String, dynamic> toJson() {
    return {
      'produto': produto.toJson(),
      'quantidade': quantidade,
    };
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
}


String _formatarPeso(double kg) {
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

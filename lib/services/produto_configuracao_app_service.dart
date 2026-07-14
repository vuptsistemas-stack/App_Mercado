import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/produto.dart';
import 'sessao_mercado_cliente.dart' as sessao;

class ProdutoConfiguracaoAppService {
  static final Map<String, Map<String, dynamic>?> _cachePorEan = {};

  static Future<List<Produto>> aplicarConfiguracoes(
    List<Produto> produtos,
  ) async {
    if (produtos.isEmpty) {
      return produtos;
    }

    final resultado = <Produto>[];

    for (final produto in produtos) {
      resultado.add(await aplicarConfiguracao(produto));
    }

    return resultado;
  }

  static Future<Produto> aplicarConfiguracao(Produto produto) async {
    if (!produto.ehKg || produto.ean.trim().isEmpty) {
      return produto;
    }

    final ean = produto.ean.trim();
    final config = await buscarConfiguracaoPorEan(ean);

    if (config == null) {
      return produto.copyWith(
        pesoVariavel: false,
        pesoMedioKg: 0,
      );
    }

    final pesoVariavel = config['peso_variavel'] == true;
    final pesoMedioKg = _numero(config['peso_medio_kg']);

    return produto.copyWith(
      pesoVariavel: pesoVariavel,
      pesoMedioKg: pesoVariavel ? pesoMedioKg : 0,
    );
  }

  static Future<Map<String, dynamic>?> buscarConfiguracaoPorEan(
    String ean,
  ) async {
    final chave = ean.trim();

    if (chave.isEmpty) {
      return null;
    }

    if (_cachePorEan.containsKey(chave)) {
      return _cachePorEan[chave];
    }

    try {
      final resposta = await Supabase.instance.client
          .from('produto_configuracoes_app')
          .select('ean, peso_variavel, peso_medio_kg, ativo')
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('ean', chave)
          .eq('ativo', true)
          .maybeSingle();

      final config = resposta == null
          ? null
          : Map<String, dynamic>.from(resposta);

      _cachePorEan[chave] = config;
      return config;
    } catch (_) {
      _cachePorEan[chave] = null;
      return null;
    }
  }

  static void limparCache() {
    _cachePorEan.clear();
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

    texto = texto
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .trim();

    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else {
      texto = texto.replaceAll(',', '.');
    }

    return double.tryParse(texto) ?? 0;
  }
}

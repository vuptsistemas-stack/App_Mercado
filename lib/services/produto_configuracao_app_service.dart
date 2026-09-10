import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/produto.dart';
import 'classificacao_ncm_service.dart';
import 'sessao_mercado_cliente.dart' as sessao;

class ProdutoConfiguracaoAppService {
  static final Map<String, Map<String, dynamic>?> _cachePorEan = {};

  static Future<List<Produto>> aplicarConfiguracoes(
    List<Produto> produtos,
  ) async {
    if (produtos.isEmpty) {
      return produtos;
    }

    final pendentes = produtos
        .where((produto) => produto.ehKg && produto.ean.trim().isNotEmpty)
        .map((produto) => produto.ean.trim())
        .where((ean) => !_cachePorEan.containsKey(ean))
        .toSet()
        .toList();
    if (pendentes.isNotEmpty) {
      await _buscarConfiguracoesPorEans(pendentes);
    }

    final resultado = produtos.map(_aplicarConfiguracaoEmCache).toList();
    return ClassificacaoNcmService.aplicar(resultado);
  }

  static Produto _aplicarConfiguracaoEmCache(Produto produto) {
    if (!produto.ehKg || produto.ean.trim().isEmpty) return produto;
    final config = _cachePorEan[produto.ean.trim()];
    if (config == null) {
      return produto.copyWith(pesoVariavel: false, pesoMedioKg: 0);
    }
    final pesoVariavel = config['peso_variavel'] == true;
    final pesoMedioKg = _numero(config['peso_medio_kg']);
    return produto.copyWith(
      pesoVariavel: pesoVariavel,
      pesoMedioKg: pesoVariavel ? pesoMedioKg : 0,
    );
  }

  static Future<Produto> aplicarConfiguracao(Produto produto) async {
    await aplicarConfiguracoes([produto]);
    return _aplicarConfiguracaoEmCache(produto);
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

    await _buscarConfiguracoesPorEans([chave]);
    return _cachePorEan[chave];
  }

  static Future<void> _buscarConfiguracoesPorEans(List<String> eans) async {
    if (eans.isEmpty) return;
    final unicos = eans.toSet().toList();
    final encontrados = <String, Map<String, dynamic>>{};
    try {
      for (var inicio = 0; inicio < unicos.length; inicio += 150) {
        final lote = unicos.sublist(
          inicio,
          inicio + 150 > unicos.length ? unicos.length : inicio + 150,
        );
        final resposta = await Supabase.instance.client
            .from('produto_configuracoes_app')
            .select('ean, peso_variavel, peso_medio_kg, ativo')
            .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
            .eq('ativo', true)
            .inFilter('ean', lote);
        for (final item in List<dynamic>.from(resposta)) {
          final dados = Map<String, dynamic>.from(item as Map);
          final ean = dados['ean']?.toString().trim() ?? '';
          if (ean.isNotEmpty) encontrados[ean] = dados;
        }
      }
    } catch (_) {
      // Registra ausentes como nulos para evitar uma consulta por produto.
    }
    for (final ean in unicos) {
      _cachePorEan[ean] = encontrados[ean];
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

    texto = texto.replaceAll('R\$', '').replaceAll(' ', '').trim();

    if (texto.contains(',') && texto.contains('.')) {
      texto = texto.replaceAll('.', '').replaceAll(',', '.');
    } else {
      texto = texto.replaceAll(',', '.');
    }

    return double.tryParse(texto) ?? 0;
  }
}

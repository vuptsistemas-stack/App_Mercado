import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_mercado_config.dart';
import '../models/carrinho_item.dart';
import 'sessao_mercado_cliente.dart' as sessao;

class CupomDescontoService {
  CupomDescontoService._();

  static final CupomDescontoService instance = CupomDescontoService._();

  final SupabaseClient _central = SupabaseClient(
    AppMercadoConfig.centralSupabaseUrl,
    AppMercadoConfig.centralSupabaseAnonKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  Future<Map<String, dynamic>> validar({
    required String codigo,
    required List<CarrinhoItem> itens,
    bool confirmarUso = false,
  }) async {
    final sessaoLoja = Supabase.instance.client.auth.currentSession;

    if (sessaoLoja == null) {
      throw Exception('Sua sessão expirou. Entre novamente.');
    }

    final resposta = await _central.functions.invoke(
      'validar-cupom-desconto',
      body: {
        'mercado_id': sessao.SessaoMercadoCliente.mercadoIdObrigatorio,
        'mercado_codigo': sessao.SessaoMercadoCliente.mercadoCodigoObrigatorio,
        'codigo': codigo.trim().toUpperCase(),
        'loja_access_token': sessaoLoja.accessToken,
        'confirmar_uso': confirmarUso,
        'itens': itens.map(_dadosItem).toList(),
      },
    );

    final dados = resposta.data;
    if (resposta.status >= 400 || dados is! Map || dados['sucesso'] != true) {
      final mensagem = dados is Map
          ? dados['erro']?.toString()
          : dados?.toString();
      throw Exception(
        (mensagem ?? '').trim().isEmpty
            ? 'Não foi possível validar o cupom.'
            : mensagem,
      );
    }

    return Map<String, dynamic>.from(dados['cupom'] as Map);
  }

  Map<String, dynamic> _dadosItem(CarrinhoItem item) {
    final produto = item.produto;

    return {
      'produto_id': produto.produtoId.toString(),
      'produto_app_id': produto.produtoAppId,
      'ean': produto.ean,
      'categoria': produto.categoria,
      'subcategoria': produto.subcategoria,
      'quantidade_elegivel': produto.ehKg
          ? item.pesoEstimadoKg
          : item.quantidade.toDouble(),
      'subtotal': item.total,
    };
  }
}

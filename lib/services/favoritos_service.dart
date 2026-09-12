import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/produto.dart';
import 'api_service.dart';
import 'sessao_mercado_cliente.dart' as sessao;

class FavoritoProduto {
  final String chaveProduto;
  final String produtoId;
  final String ean;
  final String nomeProduto;

  const FavoritoProduto({
    required this.chaveProduto,
    required this.produtoId,
    required this.ean,
    required this.nomeProduto,
  });

  factory FavoritoProduto.fromJson(Map<String, dynamic> json) {
    return FavoritoProduto(
      chaveProduto: json['produto_chave']?.toString() ?? '',
      produtoId: json['produto_id']?.toString() ?? '',
      ean: json['ean']?.toString() ?? '',
      nomeProduto: json['nome_produto']?.toString() ?? '',
    );
  }
}

class FavoritosService {
  FavoritosService._();

  static final FavoritosService instance = FavoritosService._();
  final ValueNotifier<Set<String>> chaves = ValueNotifier(<String>{});
  String _escopoCarregado = '';

  String chaveDoProduto(Produto produto) {
    if (produto.produtoId > 0) return 'id:${produto.produtoId}';
    final ean = produto.ean.trim();
    if (ean.isNotEmpty) return 'ean:$ean';
    return 'nome:${produto.nome.trim().toUpperCase()}';
  }

  String _escopoAtual() {
    final usuario = Supabase.instance.client.auth.currentUser;
    if (usuario == null) return '';
    return '${sessao.SessaoMercadoCliente.mercadoIdObrigatorio}:${usuario.id}';
  }

  Future<void> carregar({bool forcar = false}) async {
    final escopo = _escopoAtual();
    if (escopo.isEmpty) {
      chaves.value = <String>{};
      _escopoCarregado = '';
      return;
    }
    if (!forcar && _escopoCarregado == escopo) return;

    final usuario = Supabase.instance.client.auth.currentUser!;
    final resposta = await Supabase.instance.client
        .from('cliente_favoritos')
        .select('produto_chave')
        .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
        .eq('user_id', usuario.id);
    chaves.value = resposta
        .map((item) => item['produto_chave']?.toString() ?? '')
        .where((chave) => chave.isNotEmpty)
        .toSet();
    _escopoCarregado = escopo;
  }

  bool contem(Produto produto) =>
      chaves.value.contains(chaveDoProduto(produto));

  Future<bool> alternar(Produto produto) async {
    final usuario = Supabase.instance.client.auth.currentUser;
    if (usuario == null) throw StateError('Faça login para usar favoritos.');

    final chave = chaveDoProduto(produto);
    final favoritosAtuais = Set<String>.from(chaves.value);
    final existe = favoritosAtuais.contains(chave);
    final tabela = Supabase.instance.client.from('cliente_favoritos');

    if (existe) {
      await tabela
          .delete()
          .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
          .eq('user_id', usuario.id)
          .eq('produto_chave', chave);
      favoritosAtuais.remove(chave);
    } else {
      await tabela.insert({
        'mercado_id': sessao.SessaoMercadoCliente.mercadoIdObrigatorio,
        'user_id': usuario.id,
        'produto_chave': chave,
        'produto_id': produto.produtoId > 0
            ? produto.produtoId.toString()
            : null,
        'ean': produto.ean.trim().isEmpty ? null : produto.ean.trim(),
        'nome_produto': produto.nome.trim(),
      });
      favoritosAtuais.add(chave);
    }

    chaves.value = favoritosAtuais;
    return !existe;
  }

  Future<List<FavoritoProduto>> listar() async {
    final usuario = Supabase.instance.client.auth.currentUser;
    if (usuario == null) return [];
    final resposta = await Supabase.instance.client
        .from('cliente_favoritos')
        .select('produto_chave, produto_id, ean, nome_produto')
        .eq('mercado_id', sessao.SessaoMercadoCliente.mercadoIdObrigatorio)
        .eq('user_id', usuario.id)
        .order('criado_em', ascending: false);
    return resposta
        .map(
          (item) => FavoritoProduto.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<Produto?> produtoAtual(FavoritoProduto favorito) {
    return ApiService.buscarProdutoExatoParaOferta(
      ean: favorito.ean,
      produtoId: favorito.produtoId,
      nome: favorito.nomeProduto,
    );
  }
}

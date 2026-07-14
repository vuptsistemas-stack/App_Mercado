import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../models/carrinho_item.dart';
import '../models/produto.dart';
import '../services/api_service.dart';
import '../services/ofertas_service.dart';

class CarrinhoController extends ChangeNotifier {
  final List<CarrinhoItem> _itens = [];

  bool _carregado = false;
  bool _salvando = false;
  bool _atualizandoProdutos = false;
  bool _bloquearVendaSemEstoque = true;

  List<CarrinhoItem> get itens => List.unmodifiable(_itens);

  bool get carregado => _carregado;
  bool get atualizandoProdutos => _atualizandoProdutos;
  bool get bloquearVendaSemEstoque => _bloquearVendaSemEstoque;

  void atualizarBloqueioVendaSemEstoque(bool bloquear) {
    if (_bloquearVendaSemEstoque == bloquear) {
      return;
    }

    _bloquearVendaSemEstoque = bloquear;
    notifyListeners();
  }

  CarrinhoController() {
    carregarCarrinhoSalvo();
  }

  Box get _box {
    if (!Hive.isBoxOpen('carrinho')) {
      throw Exception(
        'Box carrinho não está aberta. Abra Hive.openBox("carrinho") no main.dart antes de criar CarrinhoController.',
      );
    }

    return Hive.box('carrinho');
  }

  Future<void> carregarCarrinhoSalvo() async {
    try {
      final dados = _box.get('itens');

      if (dados == null || dados is! List) {
        _carregado = true;
        notifyListeners();
        return;
      }

      _itens.clear();

      for (final item in dados) {
        try {
          if (item is! Map) {
            continue;
          }

          final mapa = Map<String, dynamic>.from(item);
          final carrinhoItem = CarrinhoItem.fromJson(mapa);

          if (carrinhoItem.produto.nome.trim().isEmpty) {
            continue;
          }

          if (carrinhoItem.quantidade <= 0) {
            continue;
          }

          _itens.add(carrinhoItem);
        } catch (_) {
          // Ignora item inválido salvo anteriormente.
        }
      }

      _carregado = true;
      notifyListeners();
    } catch (_) {
      _carregado = true;
      notifyListeners();
    }
  }

  Future<void> salvarCarrinho() async {
    if (_salvando) {
      return;
    }

    _salvando = true;

    try {
      final dados = _itens.map((item) => item.toJson()).toList();

      await _box.put('itens', dados);
    } catch (_) {
      // Não bloqueia a tela caso falhe ao salvar localmente.
    } finally {
      _salvando = false;
    }
  }

  Future<int> atualizarProdutosCarrinho() async {
    if (_atualizandoProdutos || _itens.isEmpty) {
      return 0;
    }

    _atualizandoProdutos = true;
    notifyListeners();

    var totalAtualizados = 0;

    try {
      final itensAtuais = List<CarrinhoItem>.from(_itens);
      final itensAtualizados = <CarrinhoItem>[];

      for (final item in itensAtuais) {
        final produtoAtual = await ApiService.buscarProdutoAtualizado(
          item.produto,
        );

        if (produtoAtual == null || produtoAtual.nome.trim().isEmpty) {
          itensAtualizados.add(item);
          continue;
        }

        final produtoComOferta =
            await OfertasService.aplicarPrecoOfertaAtiva(produtoAtual);

        if (_produtoMudou(item.produto, produtoComOferta)) {
          totalAtualizados++;
        }

        itensAtualizados.add(
          CarrinhoItem(
            produto: produtoComOferta,
            quantidade: item.quantidade,
          ),
        );
      }

      _itens
        ..clear()
        ..addAll(itensAtualizados);

      await salvarCarrinho();

      return totalAtualizados;
    } catch (_) {
      return totalAtualizados;
    } finally {
      _atualizandoProdutos = false;
      notifyListeners();
    }
  }

  int quantidadeProduto(Produto produto) {
    final index = _indexProduto(produto);

    if (index >= 0) {
      return _itens[index].quantidade;
    }

    return 0;
  }

  String textoQuantidadeProduto(Produto produto) {
    final index = _indexProduto(produto);

    if (index >= 0) {
      return _itens[index].textoQuantidadeCurto;
    }

    return '';
  }

  bool podeAdicionarProduto(Produto produto) {
    if (produto.nome.trim().isEmpty) {
      return false;
    }

    if (!_bloquearVendaSemEstoque) {
      return true;
    }

    if (produto.estoque <= 0) {
      return false;
    }

    final index = _indexProduto(produto);
    final proximaQuantidade = index >= 0 ? _itens[index].quantidade + 1 : 1;

    return _quantidadeDentroEstoque(produto, proximaQuantidade);
  }

  int get quantidadeTotal {
    return _itens.fold(0, (total, item) {
      if (item.produto.ehKg && !item.produto.pesoVariavel) {
        return total + 1;
      }

      return total + item.quantidade;
    });
  }

  double get valorTotal {
    return _itens.fold(0, (total, item) => total + item.total);
  }

  bool get carrinhoVazio => _itens.isEmpty;

  List<CarrinhoItem> get itensComProblemaEstoque {
    return _itens.where(_itemComProblemaEstoque).toList();
  }

  bool get possuiProblemaEstoque => itensComProblemaEstoque.isNotEmpty;

  void adicionarProduto(Produto produto) {
    if (!podeAdicionarProduto(produto)) {
      return;
    }

    final index = _indexProduto(produto);

    if (index >= 0) {
      _itens[index].quantidade++;
    } else {
      _itens.add(
        CarrinhoItem(
          produto: produto,
          quantidade: 1,
        ),
      );
    }

    salvarCarrinho();
    notifyListeners();
  }

  void removerProduto(Produto produto) {
    _itens.removeWhere(
      (item) => _mesmoProduto(item.produto, produto),
    );

    salvarCarrinho();
    notifyListeners();
  }

  void aumentarQuantidade(Produto produto) {
    adicionarProduto(produto);
  }

  void diminuirQuantidade(Produto produto) {
    final index = _indexProduto(produto);

    if (index < 0) {
      return;
    }

    if (_itens[index].quantidade > 1) {
      _itens[index].quantidade--;
    } else {
      _itens.removeAt(index);
    }

    salvarCarrinho();
    notifyListeners();
  }

  void definirQuantidade({
    required Produto produto,
    required int quantidade,
  }) {
    final index = _indexProduto(produto);

    if (quantidade <= 0) {
      if (index >= 0) {
        _itens.removeAt(index);
        salvarCarrinho();
        notifyListeners();
      }

      return;
    }

    var quantidadeAjustada = quantidade;

    while (quantidadeAjustada > 0 &&
        !_quantidadeDentroEstoque(produto, quantidadeAjustada)) {
      quantidadeAjustada--;
    }

    if (quantidadeAjustada <= 0) {
      return;
    }

    if (index >= 0) {
      _itens[index].quantidade = quantidadeAjustada;
    } else {
      _itens.add(
        CarrinhoItem(
          produto: produto,
          quantidade: quantidadeAjustada,
        ),
      );
    }

    salvarCarrinho();
    notifyListeners();
  }

  void limparCarrinho() {
    _itens.clear();

    try {
      _box.delete('itens');
    } catch (_) {}

    notifyListeners();
  }

  int _indexProduto(Produto produto) {
    return _itens.indexWhere(
      (item) => _mesmoProduto(item.produto, produto),
    );
  }

  bool _itemComProblemaEstoque(CarrinhoItem item) {
    if (!_bloquearVendaSemEstoque) {
      return false;
    }

    final estoque = item.produto.estoque;

    if (estoque <= 0) {
      return true;
    }

    if (item.produto.ehKg) {
      return item.pesoEstimadoKg > estoque + 0.0001;
    }

    return item.quantidade > estoque;
  }

  bool _quantidadeDentroEstoque(Produto produto, int quantidade) {
    if (quantidade <= 0) {
      return false;
    }

    if (!_bloquearVendaSemEstoque) {
      return true;
    }

    if (produto.estoque <= 0) {
      return false;
    }

    if (produto.ehKg) {
      final peso = produto.pesoEstimadoKgParaQuantidade(quantidade);
      return peso <= produto.estoque + 0.0001;
    }

    return quantidade <= produto.estoque;
  }

  bool _mesmoProduto(Produto a, Produto b) {
    if (a.produtoId > 0 && b.produtoId > 0) {
      return a.produtoId == b.produtoId;
    }

    final eanA = a.ean.trim();
    final eanB = b.ean.trim();

    if (eanA.isNotEmpty && eanB.isNotEmpty) {
      return eanA == eanB;
    }

    return a.nome.trim().toUpperCase() == b.nome.trim().toUpperCase();
  }

  bool _produtoMudou(Produto antigo, Produto novo) {
    if (antigo.produtoId != novo.produtoId) {
      return true;
    }

    if (antigo.nome.trim() != novo.nome.trim()) {
      return true;
    }

    if (antigo.ean.trim() != novo.ean.trim()) {
      return true;
    }

    if (antigo.unidadeNormalizada != novo.unidadeNormalizada) {
      return true;
    }

    if (antigo.pesoVariavel != novo.pesoVariavel) {
      return true;
    }

    if ((antigo.pesoMedioKg - novo.pesoMedioKg).abs() > 0.001) {
      return true;
    }

    if ((antigo.preco - novo.preco).abs() > 0.001) {
      return true;
    }

    if ((antigo.estoque - novo.estoque).abs() > 0.001) {
      return true;
    }

    return false;
  }
}

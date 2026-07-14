import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/produto.dart';

class ListaComprasItem {
  final Produto produto;
  final int quantidade;

  const ListaComprasItem({
    required this.produto,
    required this.quantidade,
  });

  double get total => produto.totalParaQuantidade(quantidade);

  Map<String, dynamic> toJson() {
    return {
      'produto': produto.toJson(),
      'quantidade': quantidade,
    };
  }

  factory ListaComprasItem.fromJson(Map<String, dynamic> json) {
    final produtoJson = json['produto'];

    return ListaComprasItem(
      produto: Produto.fromJson(
        produtoJson is Map
            ? Map<String, dynamic>.from(produtoJson)
            : <String, dynamic>{},
      ),
      quantidade: _inteiro(json['quantidade'], padrao: 1),
    );
  }

  static int _inteiro(dynamic valor, {int padrao = 0}) {
    if (valor == null) return padrao;
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();

    return int.tryParse(valor.toString().trim()) ?? padrao;
  }
}

class ListaComprasSalva {
  final String id;
  final String nome;
  final DateTime criadoEm;
  final List<ListaComprasItem> itens;

  const ListaComprasSalva({
    required this.id,
    required this.nome,
    required this.criadoEm,
    required this.itens,
  });

  int get quantidadeItens => itens.fold(0, (total, item) => total + item.quantidade);

  double get valorEstimado => itens.fold(0, (total, item) => total + item.total);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nome': nome,
      'criado_em': criadoEm.toIso8601String(),
      'itens': itens.map((item) => item.toJson()).toList(),
    };
  }

  factory ListaComprasSalva.fromJson(Map<String, dynamic> json) {
    final itensJson = json['itens'];

    return ListaComprasSalva(
      id: (json['id'] ?? '').toString(),
      nome: (json['nome'] ?? 'Lista de compras').toString(),
      criadoEm: DateTime.tryParse((json['criado_em'] ?? '').toString()) ??
          DateTime.now(),
      itens: itensJson is List
          ? itensJson
              .whereType<Map>()
              .map((item) => ListaComprasItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .where((item) => item.produto.nome.trim().isNotEmpty)
              .where((item) => item.quantidade > 0)
              .toList()
          : <ListaComprasItem>[],
    );
  }
}

class ListaComprasService {
  static const String _chave = 'listas_compras_cache_v1';

  static Future<List<ListaComprasSalva>> listarListas() async {
    final prefs = await SharedPreferences.getInstance();
    final texto = prefs.getString(_chave);

    if (texto == null || texto.trim().isEmpty) {
      return [];
    }

    try {
      final json = jsonDecode(texto);

      if (json is! List) {
        return [];
      }

      final listas = json
          .whereType<Map>()
          .map((item) => ListaComprasSalva.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((lista) => lista.itens.isNotEmpty)
          .toList();

      listas.sort((a, b) => b.criadoEm.compareTo(a.criadoEm));
      return listas;
    } catch (_) {
      return [];
    }
  }

  static Future<void> salvarListaDoCarrinho({
    required String nome,
    required List<dynamic> itensCarrinho,
  }) async {
    final nomeFinal = nome.trim().isEmpty ? 'Lista de compras' : nome.trim();

    final itens = itensCarrinho.map((item) {
      return ListaComprasItem(
        produto: item.produto as Produto,
        quantidade: item.quantidade as int,
      );
    }).where((item) {
      return item.produto.nome.trim().isNotEmpty && item.quantidade > 0;
    }).toList();

    if (itens.isEmpty) {
      return;
    }

    final listas = await listarListas();

    final novaLista = ListaComprasSalva(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      nome: nomeFinal,
      criadoEm: DateTime.now(),
      itens: itens,
    );

    listas.insert(0, novaLista);
    await _salvarTodas(listas);
  }

  static Future<void> excluirLista(String id) async {
    final listas = await listarListas();
    listas.removeWhere((lista) => lista.id == id);
    await _salvarTodas(listas);
  }

  static Future<void> limparTudo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chave);
  }

  static Future<void> _salvarTodas(List<ListaComprasSalva> listas) async {
    final prefs = await SharedPreferences.getInstance();
    final dados = listas.map((lista) => lista.toJson()).toList();
    await prefs.setString(_chave, jsonEncode(dados));
  }
}

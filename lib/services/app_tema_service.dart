import 'package:flutter/material.dart';

import 'sessao_mercado_cliente.dart' as sessao;

class AppTemaService {
  static const Color primariaPadrao = Color(0xFFE30613);
  static const Color secundariaPadrao = Color(0xFFC90010);
  static const Color fundoPadrao = Color(0xFFF5F5F5);

  static Color corHex(dynamic valor, Color padrao) {
    if (valor == null) {
      return padrao;
    }

    var texto = valor.toString().trim();

    if (texto.isEmpty) {
      return padrao;
    }

    if (texto.startsWith('#')) {
      texto = texto.substring(1);
    }

    if (texto.length == 6) {
      texto = 'FF$texto';
    }

    final numero = int.tryParse(texto, radix: 16);

    if (numero == null) {
      return padrao;
    }

    return Color(numero);
  }

  static Color get primaria {
    return corHex(
      sessao.SessaoMercadoCliente.clienteCorPrimaria,
      primariaPadrao,
    );
  }

  static Color get secundaria {
    return corHex(
      sessao.SessaoMercadoCliente.clienteCorSecundaria,
      secundariaPadrao,
    );
  }

  static Color get fundo {
    return corHex(
      sessao.SessaoMercadoCliente.clienteCorFundo,
      fundoPadrao,
    );
  }
}

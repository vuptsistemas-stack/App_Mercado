import 'package:flutter/material.dart';

// APP-NAVIGATOR-GLOBAL-PARA-ABA-FLUANTE
// ABA-MODO-MASTER-LOJA-FORCADO-CORRIGIDO
// CORRECAO-NOTIFICAR-SEMPRE-APOS-BUILD
// Usado pela aba flutuante global para navegar/abrir modal usando
// um contexto que pertence ao Navigator do MaterialApp.
class AppNavigator {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static NavigatorState? get state => navigatorKey.currentState;

  static BuildContext? get context => navigatorKey.currentContext;

  // Controla o modo visual da aba flutuante.
  // Isso resolve o caso do usuário Master acessando uma loja:
  // o usuário continua sendo master na Central, mas a aba precisa virar "Loja".
  static final ValueNotifier<int> alteracoesAba = ValueNotifier<int>(0);

  static bool _modoLojaForcado = false;
  static bool _conteudoEstendidoAteRodape = false;
  static bool _notificacaoAgendada = false;

  static bool get modoLojaForcado => _modoLojaForcado;
  static bool get conteudoEstendidoAteRodape => _conteudoEstendidoAteRodape;

  static void definirModoLoja() {
    _modoLojaForcado = true;
    _notificarAbaDepoisDoBuild();
  }

  static void definirModoMaster() {
    _modoLojaForcado = false;
    _notificarAbaDepoisDoBuild();
  }

  static void definirConteudoEstendidoAteRodape(bool estendido) {
    if (_conteudoEstendidoAteRodape == estendido) return;
    _conteudoEstendidoAteRodape = estendido;
    _notificarAbaDepoisDoBuild();
  }

  static void _notificarAbaDepoisDoBuild() {
    if (_notificacaoAgendada) {
      return;
    }

    _notificacaoAgendada = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificacaoAgendada = false;
      alteracoesAba.value++;
    });
  }
}

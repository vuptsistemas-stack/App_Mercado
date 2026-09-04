import 'package:shared_preferences/shared_preferences.dart';

enum LayoutConsultaItem { compacto, classico }

class PreferenciasInterfaceService {
  static const String _chaveLayoutConsultaItem = 'layout_consulta_item';

  static Future<LayoutConsultaItem> carregarLayoutConsultaItem() async {
    final preferencias = await SharedPreferences.getInstance();
    final valor = preferencias.getString(_chaveLayoutConsultaItem);

    return LayoutConsultaItem.values.firstWhere(
      (layout) => layout.name == valor,
      orElse: () => LayoutConsultaItem.compacto,
    );
  }

  static Future<void> salvarLayoutConsultaItem(
    LayoutConsultaItem layout,
  ) async {
    final preferencias = await SharedPreferences.getInstance();
    await preferencias.setString(_chaveLayoutConsultaItem, layout.name);
  }
}

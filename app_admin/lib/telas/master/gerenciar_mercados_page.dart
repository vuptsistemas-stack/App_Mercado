import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/central_service.dart';

bool lerBooleanoDinamico(dynamic valor, {required bool padrao}) {
  if (valor == true) {
    return true;
  }

  if (valor == false) {
    return false;
  }

  if (valor is String) {
    final texto = valor.trim().toLowerCase();

    if (texto == 'true' || texto == '1' || texto == 'sim' || texto == 's') {
      return true;
    }

    if (texto == 'false' ||
        texto == '0' ||
        texto == 'nao' ||
        texto == 'não' ||
        texto == 'n') {
      return false;
    }
  }

  if (valor is num) {
    return valor == 1;
  }

  return padrao;
}

class GerenciarMercadosPage extends StatefulWidget {
  const GerenciarMercadosPage({super.key});

  @override
  State<GerenciarMercadosPage> createState() => _GerenciarMercadosPageState();
}

class _GerenciarMercadosPageState extends State<GerenciarMercadosPage> {
  final service = CentralService();
  final buscaController = TextEditingController();

  static const Color vermelho = Color(0xFFE30613);

  bool carregando = true;
  String filtroStatus = 'todos';

  List<Map<String, dynamic>> mercados = [];

  @override
  void initState() {
    super.initState();
    carregarMercados();
  }

  @override
  void dispose() {
    buscaController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get mercadosFiltrados {
    final busca = buscaController.text.trim().toLowerCase();

    return mercados.where((mercado) {
      final ativo = mercado['ativo'] == true;

      if (filtroStatus == 'ativos' && !ativo) {
        return false;
      }

      if (filtroStatus == 'inativos' && ativo) {
        return false;
      }

      if (busca.isEmpty) {
        return true;
      }

      final nome = mercado['nome']?.toString().toLowerCase() ?? '';
      final codigo = mercado['codigo']?.toString().toLowerCase() ?? '';
      final cidade = mercado['cidade']?.toString().toLowerCase() ?? '';
      final estado = mercado['estado']?.toString().toLowerCase() ?? '';
      final apiBaseUrl =
          mercado['api_base_url']?.toString().toLowerCase() ?? '';
      final supabaseUrl =
          mercado['supabase_url']?.toString().toLowerCase() ?? '';
      final appNome = mercado['app_nome']?.toString().toLowerCase() ?? '';
      final appPackage = mercado['app_package']?.toString().toLowerCase() ?? '';
      final appBuildCodigo =
          mercado['app_build_codigo']?.toString().toLowerCase() ?? '';
      final adminAppNome =
          mercado['admin_app_nome']?.toString().toLowerCase() ?? '';
      final adminAppPackage =
          mercado['admin_app_package']?.toString().toLowerCase() ?? '';
      final adminAppBuildCodigo =
          mercado['admin_app_build_codigo']?.toString().toLowerCase() ?? '';
      final mercadoAppNome =
          mercado['mercado_app_nome']?.toString().toLowerCase() ?? '';
      final mercadoAppPackage =
          mercado['mercado_app_package']?.toString().toLowerCase() ?? '';
      final mercadoAppBuildCodigo =
          mercado['mercado_app_build_codigo']?.toString().toLowerCase() ?? '';
      final fonteProdutos =
          mercado['fonte_produtos']?.toString().toLowerCase() ?? '';

      return nome.contains(busca) ||
          codigo.contains(busca) ||
          cidade.contains(busca) ||
          estado.contains(busca) ||
          apiBaseUrl.contains(busca) ||
          supabaseUrl.contains(busca) ||
          appNome.contains(busca) ||
          appPackage.contains(busca) ||
          appBuildCodigo.contains(busca) ||
          adminAppNome.contains(busca) ||
          adminAppPackage.contains(busca) ||
          adminAppBuildCodigo.contains(busca) ||
          mercadoAppNome.contains(busca) ||
          mercadoAppPackage.contains(busca) ||
          mercadoAppBuildCodigo.contains(busca) ||
          fonteProdutos.contains(busca);
    }).toList();
  }

  Future<void> carregarMercados() async {
    if (!mounted) return;

    setState(() {
      carregando = true;
    });

    try {
      final resposta = await service.listarMercadosAdmin();

      if (!mounted) return;

      debugPrint('================ DEBUG LISTAR MERCADOS ================');
      for (final mercado in resposta) {
        final codigo = mercado['codigo']?.toString() ?? '';
        if (codigo == 'sao_mateus' || codigo.isNotEmpty) {
          debugPrint(
            'MERCADO codigo=$codigo '
            'admin=[${mercado['admin_cor_primaria']} | ${mercado['admin_cor_secundaria']} | ${mercado['admin_cor_fundo']}] '
            'cliente=[${mercado['cliente_cor_primaria']} | ${mercado['cliente_cor_secundaria']} | ${mercado['cliente_cor_fundo']}]',
          );
        }
      }
      debugPrint('=======================================================');

      setState(() {
        mercados = resposta;
        carregando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao carregar mercados: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> abrirEditarMercado(
    Map<String, dynamic> mercado, {
    String secaoInicial = 'dados',
  }) async {
    var mercadoAtualizado = Map<String, dynamic>.from(mercado);
    final mercadoId = mercadoAtualizado['id']?.toString() ?? '';

    if (mercadoId.isNotEmpty) {
      try {
        final conexaoAtual = await service.buscarConexaoMercado(mercadoId);

        mercadoAtualizado = {...mercadoAtualizado, ...conexaoAtual};

        debugPrint(
          '================ DEBUG ABRIR EDITAR ATUALIZADO ================',
        );
        debugPrint(
          'codigo=${mercadoAtualizado['codigo']} '
          'admin=[${mercadoAtualizado['admin_cor_primaria']} | ${mercadoAtualizado['admin_cor_secundaria']} | ${mercadoAtualizado['admin_cor_fundo']}] '
          'cliente=[${mercadoAtualizado['cliente_cor_primaria']} | ${mercadoAtualizado['cliente_cor_secundaria']} | ${mercadoAtualizado['cliente_cor_fundo']}]',
        );
        debugPrint(
          '===============================================================',
        );
      } catch (e) {
        debugPrint(
          'Não foi possível atualizar dados antes de editar: ${CentralService.mensagemErroUsuario(e)}',
        );
      }
    }

    final alterado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditarMercadoPage(
          mercado: mercadoAtualizado,
          secaoInicial: secaoInicial,
        ),
      ),
    );

    if (alterado == true) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mercado atualizado com sucesso'),
          backgroundColor: Colors.green,
        ),
      );

      await carregarMercados();
    }
  }

  Future<void> abrirOpcoesMercado(Map<String, dynamic> mercado) async {
    final alterado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditarMercadoOpcoesPage(mercado: mercado),
      ),
    );

    if (alterado == true) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mercado atualizado com sucesso'),
          backgroundColor: Colors.green,
        ),
      );

      await carregarMercados();
    }
  }

  Widget areaBuscaFiltros() {
    final total = mercadosFiltrados.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: buscaController,
          onChanged: (_) {
            setState(() {});
          },
          decoration: InputDecoration(
            hintText: 'Buscar por nome, código, conexão ou APK',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: buscaController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      buscaController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close),
                  ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Todos'),
                selected: filtroStatus == 'todos',
                selectedColor: vermelho.withValues(alpha: 0.15),
                onSelected: (_) {
                  setState(() {
                    filtroStatus = 'todos';
                  });
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Ativos'),
                selected: filtroStatus == 'ativos',
                selectedColor: Colors.green.withValues(alpha: 0.15),
                onSelected: (_) {
                  setState(() {
                    filtroStatus = 'ativos';
                  });
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Inativos'),
                selected: filtroStatus == 'inativos',
                selectedColor: Colors.red.withValues(alpha: 0.15),
                onSelected: (_) {
                  setState(() {
                    filtroStatus = 'inativos';
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$total mercado(s) encontrado(s)',
          style: const TextStyle(color: Colors.black54, fontSize: 13),
        ),
      ],
    );
  }

  Widget logoMercadoCard({required String logoUrl, required bool ativo}) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: ativo
            ? vermelho.withValues(alpha: 0.12)
            : Colors.grey.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ativo
              ? vermelho.withValues(alpha: 0.18)
              : Colors.grey.withValues(alpha: 0.20),
        ),
      ),
      child: logoUrl.trim().isEmpty
          ? Icon(Icons.store, color: ativo ? vermelho : Colors.grey)
          : ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Image.network(
                logoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return Icon(
                    Icons.store,
                    color: ativo ? vermelho : Colors.grey,
                  );
                },
              ),
            ),
    );
  }

  Widget cardMercado(Map<String, dynamic> mercado) {
    final nome = mercado['nome']?.toString() ?? 'Mercado';
    final codigo = mercado['codigo']?.toString() ?? '';
    final cidade = mercado['cidade']?.toString() ?? '';
    final estado = mercado['estado']?.toString() ?? '';
    final apiBaseUrl = mercado['api_base_url']?.toString() ?? '';
    final supabaseUrl = mercado['supabase_url']?.toString() ?? '';
    final logoLoginUrl = mercado['logo_login_url']?.toString() ?? '';
    final logoUrlAntigo = mercado['logo_url']?.toString() ?? '';
    final logoUrl = logoLoginUrl.trim().isNotEmpty
        ? logoLoginUrl
        : logoUrlAntigo;
    final splashLogoUrl = mercado['splash_logo_url']?.toString() ?? '';
    final mercadoSplashLogoUrl =
        mercado['mercado_splash_logo_url']?.toString() ?? '';
    final appIconeUrlAtualCard = mercado['app_icone_url']?.toString() ?? '';
    final mercadoAppIconeUrlAtualCard =
        mercado['mercado_app_icone_url']?.toString() ?? '';
    final adminCorPrimaria =
        mercado['admin_cor_primaria']?.toString() ?? '#E30613';
    final adminCorSecundaria =
        mercado['admin_cor_secundaria']?.toString() ?? '#C90010';
    final adminCorFundo = mercado['admin_cor_fundo']?.toString() ?? '#F5F7FA';
    final clienteCorPrimaria =
        mercado['cliente_cor_primaria']?.toString() ?? '#E30613';
    final clienteCorSecundaria =
        mercado['cliente_cor_secundaria']?.toString() ?? '#C90010';
    final clienteCorFundo =
        mercado['cliente_cor_fundo']?.toString() ?? '#FFF7F7';
    final ativo = mercado['ativo'] == true;
    final usarApiImagens = lerBooleanoDinamico(
      mercado['usar_api_imagens'],
      padrao: false,
    );
    final serpapiConfigurada = mercado['serpapi_configurada'] == true;
    final apkPersonalizado = mercado['apk_personalizado'] == true;
    final appNome = mercado['app_nome']?.toString() ?? '';
    final appPackage = mercado['app_package']?.toString() ?? '';
    final appBuildCodigo = mercado['app_build_codigo']?.toString() ?? '';

    final gerarApkAdmin = lerBooleanoDinamico(
      mercado['gerar_apk_admin'],
      padrao: false,
    );
    final adminAppNome = mercado['admin_app_nome']?.toString() ?? '';
    final adminAppPackage = mercado['admin_app_package']?.toString() ?? '';
    final adminAppBuildCodigo =
        mercado['admin_app_build_codigo']?.toString() ?? '';

    final gerarApkMercado = lerBooleanoDinamico(
      mercado['gerar_apk_mercado'] ?? mercado['apk_personalizado'],
      padrao: false,
    );
    final mercadoAppNome =
        mercado['mercado_app_nome']?.toString().trim().isNotEmpty == true
        ? mercado['mercado_app_nome'].toString()
        : appNome;
    final mercadoAppPackage =
        mercado['mercado_app_package']?.toString().trim().isNotEmpty == true
        ? mercado['mercado_app_package'].toString()
        : appPackage;
    final mercadoAppBuildCodigo =
        mercado['mercado_app_build_codigo']?.toString().trim().isNotEmpty ==
            true
        ? mercado['mercado_app_build_codigo'].toString()
        : appBuildCodigo;
    final estoqueUpdateTokenAtivo = lerBooleanoDinamico(
      mercado['estoque_update_token_ativo'],
      padrao: false,
    );
    final estoqueUpdateTokenConfigurado =
        lerBooleanoDinamico(
          mercado['estoque_update_token_configurado'],
          padrao: false,
        ) ||
        (mercado['estoque_update_token']?.toString().trim().isNotEmpty ??
            false);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              logoMercadoCard(logoUrl: logoUrl, ativo: ativo),
              const SizedBox(width: 14),
              Expanded(
                child: Opacity(
                  opacity: ativo ? 1 : 0.72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              nome,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: ativo
                                  ? Colors.green.withValues(alpha: 0.12)
                                  : Colors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              ativo ? 'Ativo' : 'Inativo',
                              style: TextStyle(
                                color: ativo ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        codigo.isEmpty ? 'Sem código' : 'Código: $codigo',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        cidade.isEmpty && estado.isEmpty
                            ? 'Cidade não informada'
                            : '$cidade - $estado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Use Alterar para editar dados, visual, APKs, conexões e estoque.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.45),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => abrirOpcoesMercado(mercado),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text(
                  'Alterar',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: vermelho,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = mercadosFiltrados;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Gerenciar mercados'),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: carregarMercados,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: carregarMercados,
              child: mercados.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('Nenhum mercado cadastrado')),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text(
                          'Mercados cadastrados',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Liste, edite conexões e ative ou inative mercados.',
                          style: TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 18),
                        areaBuscaFiltros(),
                        const SizedBox(height: 18),
                        if (lista.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 80),
                            child: Center(
                              child: Text(
                                'Nenhum mercado encontrado com esse filtro',
                              ),
                            ),
                          )
                        else
                          ...lista.map(cardMercado),
                      ],
                    ),
            ),
    );
  }
}

class EditarMercadoOpcoesPage extends StatelessWidget {
  final Map<String, dynamic> mercado;

  const EditarMercadoOpcoesPage({super.key, required this.mercado});

  static const Color vermelho = Color(0xFFE30613);

  String get nomeMercado => mercado['nome']?.toString() ?? 'Mercado';
  String get codigoMercado => mercado['codigo']?.toString() ?? '';
  String get cidadeMercado => mercado['cidade']?.toString() ?? '';
  String get estadoMercado => mercado['estado']?.toString() ?? '';
  bool get mercadoAtivo => mercado['ativo'] == true;

  Future<void> abrirSecao(BuildContext context, String secao) async {
    if (secao == 'módulos') {
      final alterado = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => ModulosLojaPage(mercado: mercado)),
      );

      if (alterado == true && context.mounted) {
        Navigator.pop(context, true);
      }

      return;
    }

    final alterado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EditarMercadoPage(mercado: mercado, secaoInicial: secao),
      ),
    );

    if (alterado == true && context.mounted) {
      Navigator.pop(context, true);
    }
  }

  Widget resumoMercado() {
    final cidadeEstado = cidadeMercado.isEmpty && estadoMercado.isEmpty
        ? 'Localização não informada'
        : '$cidadeMercado${cidadeMercado.isNotEmpty && estadoMercado.isNotEmpty ? ' - ' : ''}$estadoMercado';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: vermelho.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.storefront, color: vermelho, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nomeMercado,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  codigoMercado.isEmpty
                      ? cidadeEstado
                      : '$codigoMercado • $cidadeEstado',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: mercadoAtivo
                  ? Colors.green.withValues(alpha: 0.12)
                  : Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              mercadoAtivo ? 'Ativo' : 'Inativo',
              style: TextStyle(
                color: mercadoAtivo ? Colors.green : Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget itemSecao({
    required BuildContext context,
    required String id,
    required String titulo,
    required String subtitulo,
    required IconData icone,
    required Color cor,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => abrirSecao(context, id),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icone, color: cor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cor, size: 28),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text('Editar $nomeMercado'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'O que deseja alterar?',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Escolha uma área para abrir em uma tela separada.',
            style: TextStyle(color: Colors.black54, fontSize: 14),
          ),
          const SizedBox(height: 16),
          resumoMercado(),
          const SizedBox(height: 18),
          itemSecao(
            context: context,
            id: 'dados',
            titulo: 'Dados da loja',
            subtitulo: 'Nome, código, cidade e status',
            icone: Icons.store_mall_directory,
            cor: vermelho,
          ),
          const SizedBox(height: 12),
          itemSecao(
            context: context,
            id: 'visual_admin',
            titulo: 'Visual Admin',
            subtitulo: 'Logo, splash, ícone e cores do Admin',
            icone: Icons.palette,
            cor: Colors.deepPurple,
          ),
          const SizedBox(height: 12),
          itemSecao(
            context: context,
            id: 'visual_mercado',
            titulo: 'Visual Mercado',
            subtitulo: 'Splash e ícone do app Mercado',
            icone: Icons.shopping_bag,
            cor: Colors.blue,
          ),
          const SizedBox(height: 12),
          itemSecao(
            context: context,
            id: 'apks',
            titulo: 'APKs',
            subtitulo: 'Admin e app de compras',
            icone: Icons.android,
            cor: Colors.teal,
          ),
          const SizedBox(height: 12),
          itemSecao(
            context: context,
            id: 'conexoes',
            titulo: 'Conexões',
            subtitulo: 'API e Supabase da loja',
            icone: Icons.cloud_sync,
            cor: Colors.indigo,
          ),
          const SizedBox(height: 12),
          itemSecao(
            context: context,
            id: 'módulos',
            titulo: 'Botões liberados',
            subtitulo: 'Definir o que o admin da loja pode acessar',
            icone: Icons.fact_check,
            cor: Colors.blueGrey,
          ),
          const SizedBox(height: 12),
          itemSecao(
            context: context,
            id: 'imagens',
            titulo: 'API de imagens',
            subtitulo: 'SerpAPI e busca automática',
            icone: Icons.image_search,
            cor: Colors.orange,
          ),
          const SizedBox(height: 12),
          itemSecao(
            context: context,
            id: 'estoque',
            titulo: 'Estoque',
            subtitulo: 'Token de update pela API',
            icone: Icons.inventory_2,
            cor: Colors.green,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class ModulosLojaPage extends StatefulWidget {
  final Map<String, dynamic> mercado;

  const ModulosLojaPage({super.key, required this.mercado});

  @override
  State<ModulosLojaPage> createState() => _ModulosLojaPageState();
}

class _ModulosLojaPageState extends State<ModulosLojaPage> {
  final service = CentralService();

  static const Color vermelho = Color(0xFFE30613);

  bool carregando = true;
  bool salvando = false;

  List<Map<String, dynamic>> modulos = [];
  Set<String> modulosLiberados = {};

  final List<Map<String, dynamic>> modulosPadraoLoja = const [
    {
      'codigo': 'pedidos',
      'nome': 'Pedidos',
      'descricao': 'Visualizar e alterar pedidos da loja.',
    },
    {
      'codigo': 'consulta_preco',
      'nome': 'Consulta Item P/ Compra',
      'descricao': 'Consulta antiga/padrão de item para compra.',
    },
    {
      'codigo': 'produtos_inativos',
      'nome': 'Produtos inativos',
      'descricao':
          'Permite consultar produtos inativos quando o item não for encontrado.',
    },
    {
      'codigo': 'consulta_item',
      'nome': 'Consulta Item',
      'descricao': 'Consulta visual com imagem grande do produto.',
    },
    {
      'codigo': 'alterar_preco',
      'nome': 'Alterar preço',
      'descricao': 'Permite alterar o preço pela tela de consulta.',
    },
    {
      'codigo': 'balanco',
      'nome': 'Balanço',
      'descricao': 'Coletar itens e gerar arquivo TXT.',
    },
    {
      'codigo': 'conferencia_notas',
      'nome': 'Conferencia NF-e',
      'descricao': 'Consultar notas de entrada para conferencia do Sao Mateus.',
    },
    {
      'codigo': 'estoque',
      'nome': 'Estoque',
      'descricao': 'Acesso ao menu geral de estoque.',
    },
    {
      'codigo': 'estoque_entrada',
      'nome': 'Entrada de estoque',
      'descricao': 'Registrar entrada de estoque.',
    },
    {
      'codigo': 'estoque_correcao',
      'nome': 'Correção de estoque',
      'descricao': 'Corrigir saldo de estoque.',
    },
    {
      'codigo': 'estoque_baixa_avaria',
      'nome': 'Baixa por avaria',
      'descricao': 'Baixar produtos avariados do estoque.',
    },
    {
      'codigo': 'estoque_baixa_validade',
      'nome': 'Baixa por validade',
      'descricao': 'Baixar produtos vencidos do estoque.',
    },
    {
      'codigo': 'estoque_abrir_pacote',
      'nome': 'Abrir pacote / granel',
      'descricao':
          'Baixar uma embalagem fechada e somar quantidade no item a granel.',
    },
    {
      'codigo': 'estoque_consumo_interno',
      'nome': 'Consumo interno',
      'descricao': 'Registrar consumo interno de produtos.',
    },
    {
      'codigo': 'estoque_auditoria',
      'nome': 'Auditoria de estoque',
      'descricao': 'Consultar alterações de estoque.',
    },
    {
      'codigo': 'produtos_app',
      'nome': 'Produtos app',
      'descricao': 'Cadastrar produtos do modo BANCO_LOJA.',
    },
    {
      'codigo': 'receitas',
      'nome': 'Receitas e produção',
      'descricao': 'Criar ficha técnica e produzir itens.',
    },
    {
      'codigo': 'cupons',
      'nome': 'Cupons',
      'descricao': 'Criar e gerenciar cupons de desconto.',
    },
    {
      'codigo': 'ofertas',
      'nome': 'Ofertas',
      'descricao': 'Criar ofertas do app Mercado.',
    },
    {
      'codigo': 'jornal_promocoes',
      'nome': 'Jornal de promocoes',
      'descricao': 'Gerar encarte para impressao e redes sociais.',
    },
    {
      'codigo': 'clientes_app',
      'nome': 'Clientes do app',
      'descricao': 'Listar e bloquear clientes cadastrados no app Mercado.',
    },
    {
      'codigo': 'acoes_validade',
      'nome': 'Ações de validade',
      'descricao': 'Criar descontos por validade e monitorar estoque.',
    },
    {
      'codigo': 'peso_variavel',
      'nome': 'Peso variável',
      'descricao': 'Configurar produtos vendidos por KG/peso.',
    },
    {
      'codigo': 'loja_configuracoes',
      'nome': 'Configurações da loja',
      'descricao': 'Editar dados, entrega, horários e aparência da loja.',
    },
    {
      'codigo': 'usuarios',
      'nome': 'Usuários',
      'descricao': 'Cadastrar usuários e liberar permissões.',
    },
    {
      'codigo': 'relatorios',
      'nome': 'Relatórios',
      'descricao': 'Visualizar relatórios da loja.',
    },
  ];

  List<Map<String, dynamic>> normalizarModulos(
    List<Map<String, dynamic>> resposta,
  ) {
    final porCodigo = <String, Map<String, dynamic>>{};

    for (final modulo in modulosPadraoLoja) {
      final codigo = modulo['codigo']?.toString() ?? '';
      if (codigo.isEmpty) continue;
      porCodigo[codigo] = Map<String, dynamic>.from(modulo);
    }

    for (final modulo in resposta) {
      final codigo =
          (modulo['codigo'] ?? modulo['modulo_codigo'])?.toString() ?? '';
      if (codigo.isEmpty) continue;

      porCodigo[codigo] = {
        ...?porCodigo[codigo],
        ...modulo,
        'codigo': codigo,
        'nome': (modulo['nome'] ?? porCodigo[codigo]?['nome'] ?? codigo)
            .toString(),
        'descricao':
            (modulo['descricao'] ?? porCodigo[codigo]?['descricao'] ?? '')
                .toString(),
        'permitido': modulo['permitido'] == true,
      };
    }

    return modulosPadraoLoja.map((modulo) {
      final codigo = modulo['codigo']?.toString() ?? '';
      return porCodigo[codigo] ?? Map<String, dynamic>.from(modulo);
    }).toList();
  }

  String get mercadoId => widget.mercado['id']?.toString() ?? '';
  String get nomeMercado => widget.mercado['nome']?.toString() ?? 'Loja';

  @override
  void initState() {
    super.initState();
    carregarModulos();
  }

  void mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> carregarModulos() async {
    if (mercadoId.isEmpty) {
      setState(() {
        carregando = false;
      });
      mostrarMensagem('Mercado sem id.', erro: true);
      return;
    }

    try {
      final resposta = await service.listarModulosLoja(mercadoId: mercadoId);
      final listaResposta = resposta['modulos'] == null
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(resposta['modulos']);
      final lista = normalizarModulos(listaResposta);
      final liberados = lista
          .where((modulo) => modulo['permitido'] == true)
          .map((modulo) => modulo['codigo']?.toString() ?? '')
          .where((codigo) => codigo.isNotEmpty)
          .toSet();

      if (!mounted) return;

      setState(() {
        modulos = lista;
        modulosLiberados = liberados;
        carregando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        carregando = false;
      });

      mostrarMensagem(
        'Erro ao carregar botões liberados: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    }
  }

  Future<void> salvar() async {
    if (mercadoId.isEmpty || salvando) return;

    setState(() {
      salvando = true;
    });

    try {
      final resposta = await service.salvarModulosLoja(
        mercadoId: mercadoId,
        modulosLiberados: modulosLiberados.toList(),
      );

      final lista = resposta['modulos'] == null
          ? modulos
          : normalizarModulos(
              List<Map<String, dynamic>>.from(resposta['modulos']),
            );

      if (!mounted) return;

      setState(() {
        modulos = lista;
        modulosLiberados = lista
            .where((modulo) => modulo['permitido'] == true)
            .map((modulo) => modulo['codigo']?.toString() ?? '')
            .where((codigo) => codigo.isNotEmpty)
            .toSet();
        salvando = false;
      });

      mostrarMensagem('Botões liberados atualizados.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        salvando = false;
      });

      mostrarMensagem(
        'Erro ao salvar botões liberados: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    }
  }

  Widget itemModulo(Map<String, dynamic> modulo) {
    final codigo = modulo['codigo']?.toString() ?? '';
    final nome = modulo['nome']?.toString() ?? codigo;
    final descricao = modulo['descricao']?.toString() ?? '';
    final liberado = modulosLiberados.contains(codigo);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: liberado
                  ? vermelho.withValues(alpha: 0.35)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: SwitchListTile(
            value: liberado,
            onChanged: salvando
                ? null
                : (valor) {
                    setState(() {
                      if (valor) {
                        modulosLiberados.add(codigo);
                      } else {
                        modulosLiberados.remove(codigo);
                      }
                    });
                  },
            title: Text(
              nome,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: descricao.isEmpty ? null : Text(descricao),
            activeColor: vermelho,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Botões liberados'),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    Text(
                      nomeMercado,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Marque os botões que o admin da loja poderá acessar e liberar para usuários.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 20),
                    if (modulos.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: 70),
                          child: Text('Nenhum módulo encontrado.'),
                        ),
                      )
                    else
                      ...modulos.map(itemModulo),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: salvando ? null : salvar,
                        icon: salvando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(salvando ? 'Salvando...' : 'Salvar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: vermelho,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (salvando)
                  Container(color: Colors.black.withValues(alpha: 0.06)),
              ],
            ),
    );
  }
}

class EditarMercadoPage extends StatefulWidget {
  final Map<String, dynamic> mercado;
  final String secaoInicial;

  const EditarMercadoPage({
    super.key,
    required this.mercado,
    this.secaoInicial = 'dados',
  });

  @override
  State<EditarMercadoPage> createState() => _EditarMercadoPageState();
}

class _EditarMercadoPageState extends State<EditarMercadoPage> {
  final service = CentralService();
  final ImagePicker picker = ImagePicker();

  static const Color vermelho = Color(0xFFE30613);

  String tituloSecaoAtual() {
    switch (secaoEdicaoSelecionada) {
      case 'visual_admin':
        return 'Visual Admin';
      case 'visual_mercado':
        return 'Visual Mercado';
      case 'apks':
        return 'APKs';
      case 'conexoes':
        return 'Conexões e produtos';
      case 'imagens':
        return 'API de imagens';
      case 'estoque':
        return 'Estoque';
      case 'dados':
      default:
        return 'Dados da loja';
    }
  }

  String subtituloSecaoAtual() {
    switch (secaoEdicaoSelecionada) {
      case 'visual_admin':
        return 'Logo, splash, ícone e cores do app Admin.';
      case 'visual_mercado':
        return 'Splash e ícone do app Mercado/Cliente.';
      case 'apks':
        return 'Configure os APKs personalizados da loja.';
      case 'conexoes':
        return 'Dados técnicos de API, Supabase e fonte dos produtos.';
      case 'imagens':
        return 'Configuração da busca automática pela SerpAPI.';
      case 'estoque':
        return 'Token de autorização para update de estoque pela API.';
      case 'dados':
      default:
        return 'Nome, código, cidade, UF e status da loja.';
    }
  }

  IconData iconeSecaoAtual() {
    switch (secaoEdicaoSelecionada) {
      case 'visual_admin':
        return Icons.palette;
      case 'visual_mercado':
        return Icons.shopping_bag;
      case 'apks':
        return Icons.android;
      case 'conexoes':
        return Icons.cloud_sync;
      case 'imagens':
        return Icons.image_search;
      case 'estoque':
        return Icons.inventory_2;
      case 'dados':
      default:
        return Icons.store_mall_directory;
    }
  }

  Color corSecaoAtual() {
    switch (secaoEdicaoSelecionada) {
      case 'visual_admin':
        return Colors.deepPurple;
      case 'visual_mercado':
        return Colors.blue;
      case 'apks':
        return Colors.teal;
      case 'conexoes':
        return Colors.indigo;
      case 'imagens':
        return Colors.orange;
      case 'estoque':
        return Colors.green;
      case 'dados':
      default:
        return vermelho;
    }
  }

  final nomeController = TextEditingController();
  final codigoController = TextEditingController();
  final cidadeController = TextEditingController();
  final estadoController = TextEditingController();

  final apiBaseUrlController = TextEditingController();
  final supabaseUrlController = TextEditingController();
  final supabaseAnonKeyController = TextEditingController();
  final supabaseServiceRoleKeyController = TextEditingController();
  final serpapiKeyController = TextEditingController();

  final appNomeController = TextEditingController();
  final appPackageController = TextEditingController();
  final appBuildCodigoController = TextEditingController();
  final appIconeUrlController = TextEditingController();
  final appIconePathController = TextEditingController();

  final adminAppNomeController = TextEditingController();
  final adminAppPackageController = TextEditingController();
  final adminAppBuildCodigoController = TextEditingController();

  final mercadoAppNomeController = TextEditingController();
  final mercadoAppPackageController = TextEditingController();
  final mercadoAppBuildCodigoController = TextEditingController();

  final adminCorPrimariaController = TextEditingController(text: '#E30613');
  final adminCorSecundariaController = TextEditingController(text: '#C90010');
  final adminCorFundoController = TextEditingController(text: '#F5F7FA');

  final clienteCorPrimariaController = TextEditingController(text: '#E30613');
  final clienteCorSecundariaController = TextEditingController(text: '#C90010');
  final clienteCorFundoController = TextEditingController(text: '#FFF7F7');

  final estoqueUpdateTokenController = TextEditingController();

  bool ativo = true;
  bool salvando = false;
  bool carregandoConexao = true;
  bool usarApiImagens = true;
  String fonteProdutos = 'API';
  bool serpapiConfigurada = false;
  bool apkPersonalizado = false;
  bool gerarApkAdmin = false;
  bool gerarApkMercado = false;
  bool estoqueUpdateTokenAtivo = false;
  bool estoqueUpdateTokenConfigurado = false;
  bool estoqueDetalhadoAtivo = false;
  bool alterarPrecoConsultaAtivo = false;

  String secaoEdicaoSelecionada = 'dados';

  File? logoSelecionada;
  File? mercadoLogoSelecionada;
  File? splashLogoSelecionada;
  File? mercadoSplashLogoSelecionada;
  File? iconeAppSelecionado;
  File? mercadoIconeAppSelecionado;

  String logoUrlAtual = '';
  String mercadoLogoUrlAtual = '';
  String mercadoLogoPathAtual = '';
  String splashLogoUrlAtual = '';
  String mercadoSplashLogoUrlAtual = '';
  String mercadoSplashLogoPathAtual = '';
  String appIconeUrlAtual = '';
  String mercadoAppIconeUrlAtual = '';
  String mercadoAppIconePathAtual = '';

  @override
  void initState() {
    super.initState();

    secaoEdicaoSelecionada = widget.secaoInicial;

    nomeController.text = widget.mercado['nome']?.toString() ?? '';
    codigoController.text = widget.mercado['codigo']?.toString() ?? '';
    cidadeController.text = widget.mercado['cidade']?.toString() ?? '';
    estadoController.text = widget.mercado['estado']?.toString() ?? '';

    apiBaseUrlController.text =
        widget.mercado['api_base_url']?.toString() ?? '';
    supabaseUrlController.text =
        widget.mercado['supabase_url']?.toString() ?? '';
    supabaseAnonKeyController.text =
        widget.mercado['supabase_anon_key']?.toString() ?? '';

    ativo = widget.mercado['ativo'] == true;
    usarApiImagens = lerBooleanoDinamico(
      widget.mercado['usar_api_imagens'],
      padrao: false,
    );
    final fonteProdutosInicial =
        widget.mercado['fonte_produtos']?.toString().trim().toUpperCase() ?? '';
    fonteProdutos = fonteProdutosInicial == 'BANCO_LOJA' ? 'BANCO_LOJA' : 'API';

    serpapiConfigurada = widget.mercado['serpapi_configurada'] == true;
    final logoLoginUrlInicial =
        widget.mercado['logo_login_url']?.toString().trim() ?? '';
    final mercadoLogoUrlInicial =
        widget.mercado['logo_url']?.toString().trim() ?? '';
    logoUrlAtual = logoLoginUrlInicial.isNotEmpty
        ? logoLoginUrlInicial
        : mercadoLogoUrlInicial;
    mercadoLogoUrlAtual = mercadoLogoUrlInicial.isNotEmpty
        ? mercadoLogoUrlInicial
        : logoUrlAtual;
    mercadoLogoPathAtual = widget.mercado['logo_path']?.toString() ?? '';
    splashLogoUrlAtual = widget.mercado['splash_logo_url']?.toString() ?? '';
    mercadoSplashLogoUrlAtual =
        widget.mercado['mercado_splash_logo_url']?.toString() ?? '';
    mercadoSplashLogoPathAtual =
        widget.mercado['mercado_splash_logo_path']?.toString() ?? '';
    appIconeUrlAtual = widget.mercado['app_icone_url']?.toString() ?? '';
    mercadoAppIconeUrlAtual =
        widget.mercado['mercado_app_icone_url']?.toString() ?? '';
    mercadoAppIconePathAtual =
        widget.mercado['mercado_app_icone_path']?.toString() ?? '';

    apkPersonalizado = widget.mercado['apk_personalizado'] == true;
    appNomeController.text = widget.mercado['app_nome']?.toString() ?? '';
    appPackageController.text = widget.mercado['app_package']?.toString() ?? '';
    appBuildCodigoController.text =
        widget.mercado['app_build_codigo']?.toString() ?? '';
    appIconeUrlController.text =
        widget.mercado['app_icone_url']?.toString() ?? '';
    appIconePathController.text =
        widget.mercado['app_icone_path']?.toString() ?? '';

    gerarApkAdmin = lerBooleanoDinamico(
      widget.mercado['gerar_apk_admin'],
      padrao: false,
    );
    adminAppNomeController.text =
        widget.mercado['admin_app_nome']?.toString() ?? '';
    adminAppPackageController.text =
        widget.mercado['admin_app_package']?.toString() ?? '';
    adminAppBuildCodigoController.text =
        widget.mercado['admin_app_build_codigo']?.toString() ?? '';

    adminCorPrimariaController.text =
        widget.mercado['admin_cor_primaria']?.toString().trim().isNotEmpty ==
            true
        ? widget.mercado['admin_cor_primaria'].toString()
        : '#E30613';
    adminCorSecundariaController.text =
        widget.mercado['admin_cor_secundaria']?.toString().trim().isNotEmpty ==
            true
        ? widget.mercado['admin_cor_secundaria'].toString()
        : '#C90010';
    adminCorFundoController.text =
        widget.mercado['admin_cor_fundo']?.toString().trim().isNotEmpty == true
        ? widget.mercado['admin_cor_fundo'].toString()
        : '#F5F7FA';

    clienteCorPrimariaController.text =
        widget.mercado['cliente_cor_primaria']?.toString().trim().isNotEmpty ==
            true
        ? widget.mercado['cliente_cor_primaria'].toString()
        : '#E30613';
    clienteCorSecundariaController.text =
        widget.mercado['cliente_cor_secundaria']
                ?.toString()
                .trim()
                .isNotEmpty ==
            true
        ? widget.mercado['cliente_cor_secundaria'].toString()
        : '#C90010';
    clienteCorFundoController.text =
        widget.mercado['cliente_cor_fundo']?.toString().trim().isNotEmpty ==
            true
        ? widget.mercado['cliente_cor_fundo'].toString()
        : '#FFF7F7';

    debugPrint('================ DEBUG CORES TELA EDITAR ================');
    debugPrint(
      'Mercado: ${widget.mercado['codigo']} - ${widget.mercado['nome']}',
    );
    debugPrint(
      'LISTA admin=[${widget.mercado['admin_cor_primaria']} | ${widget.mercado['admin_cor_secundaria']} | ${widget.mercado['admin_cor_fundo']}] '
      'cliente=[${widget.mercado['cliente_cor_primaria']} | ${widget.mercado['cliente_cor_secundaria']} | ${widget.mercado['cliente_cor_fundo']}]',
    );
    debugPrint(
      'CONTROLLERS inicial admin=[${adminCorPrimariaController.text} | ${adminCorSecundariaController.text} | ${adminCorFundoController.text}] '
      'cliente=[${clienteCorPrimariaController.text} | ${clienteCorSecundariaController.text} | ${clienteCorFundoController.text}]',
    );
    debugPrint('=========================================================');

    gerarApkMercado = lerBooleanoDinamico(
      widget.mercado['gerar_apk_mercado'] ??
          widget.mercado['apk_personalizado'],
      padrao: apkPersonalizado,
    );
    mercadoAppNomeController.text =
        widget.mercado['mercado_app_nome']?.toString().trim().isNotEmpty == true
        ? widget.mercado['mercado_app_nome'].toString()
        : appNomeController.text;
    mercadoAppPackageController.text =
        widget.mercado['mercado_app_package']?.toString().trim().isNotEmpty ==
            true
        ? widget.mercado['mercado_app_package'].toString()
        : appPackageController.text;
    mercadoAppBuildCodigoController.text =
        widget.mercado['mercado_app_build_codigo']
                ?.toString()
                .trim()
                .isNotEmpty ==
            true
        ? widget.mercado['mercado_app_build_codigo'].toString()
        : appBuildCodigoController.text;

    estoqueUpdateTokenAtivo = lerBooleanoDinamico(
      widget.mercado['estoque_update_token_ativo'],
      padrao: false,
    );

    estoqueDetalhadoAtivo = lerBooleanoDinamico(
      widget.mercado['estoque_detalhado_ativo'],
      padrao: false,
    );

    alterarPrecoConsultaAtivo = lerBooleanoDinamico(
      widget.mercado['alterar_preco_consulta_ativo'],
      padrao: false,
    );

    final tokenEstoqueAtual =
        widget.mercado['estoque_update_token']?.toString() ?? '';

    if (tokenEstoqueAtual.trim().isNotEmpty) {
      estoqueUpdateTokenController.text = tokenEstoqueAtual.trim();
    }

    estoqueUpdateTokenConfigurado =
        lerBooleanoDinamico(
          widget.mercado['estoque_update_token_configurado'],
          padrao: false,
        ) ||
        tokenEstoqueAtual.trim().isNotEmpty;

    carregarConexaoMercado();
  }

  @override
  void dispose() {
    nomeController.dispose();
    codigoController.dispose();
    cidadeController.dispose();
    estadoController.dispose();
    apiBaseUrlController.dispose();
    supabaseUrlController.dispose();
    supabaseAnonKeyController.dispose();
    supabaseServiceRoleKeyController.dispose();
    serpapiKeyController.dispose();
    appNomeController.dispose();
    appPackageController.dispose();
    appBuildCodigoController.dispose();
    appIconeUrlController.dispose();
    appIconePathController.dispose();
    adminAppNomeController.dispose();
    adminAppPackageController.dispose();
    adminAppBuildCodigoController.dispose();
    mercadoAppNomeController.dispose();
    mercadoAppPackageController.dispose();
    mercadoAppBuildCodigoController.dispose();
    adminCorPrimariaController.dispose();
    adminCorSecundariaController.dispose();
    adminCorFundoController.dispose();
    clienteCorPrimariaController.dispose();
    clienteCorSecundariaController.dispose();
    clienteCorFundoController.dispose();
    estoqueUpdateTokenController.dispose();
    super.dispose();
  }

  Future<void> carregarConexaoMercado() async {
    final mercadoId = widget.mercado['id']?.toString() ?? '';

    if (mercadoId.isEmpty) {
      setState(() {
        carregandoConexao = false;
      });
      return;
    }

    try {
      final conexao = await service.buscarConexaoMercado(mercadoId);

      if (!mounted) return;

      setState(() {
        apiBaseUrlController.text =
            conexao['api_base_url']?.toString() ?? apiBaseUrlController.text;

        supabaseUrlController.text =
            conexao['supabase_url']?.toString() ?? supabaseUrlController.text;

        supabaseAnonKeyController.text =
            conexao['supabase_anon_key']?.toString() ??
            supabaseAnonKeyController.text;

        final logoLoginConexao =
            conexao['logo_login_url']?.toString().trim() ?? '';
        if (logoLoginConexao.isNotEmpty) {
          logoUrlAtual = logoLoginConexao;
        }

        final mercadoLogoConexao = conexao['logo_url']?.toString().trim() ?? '';
        if (mercadoLogoConexao.isNotEmpty) {
          mercadoLogoUrlAtual = mercadoLogoConexao;
        } else if (logoLoginConexao.isNotEmpty && mercadoLogoUrlAtual.isEmpty) {
          mercadoLogoUrlAtual = logoLoginConexao;
        }

        final mercadoLogoPathConexao =
            conexao['logo_path']?.toString().trim() ?? '';
        if (mercadoLogoPathConexao.isNotEmpty) {
          mercadoLogoPathAtual = mercadoLogoPathConexao;
        }

        final splashConexao =
            conexao['splash_logo_url']?.toString().trim() ?? '';
        if (splashConexao.isNotEmpty) {
          splashLogoUrlAtual = splashConexao;
        }

        final mercadoSplashConexao =
            conexao['mercado_splash_logo_url']?.toString().trim() ?? '';
        if (mercadoSplashConexao.isNotEmpty) {
          mercadoSplashLogoUrlAtual = mercadoSplashConexao;
        }

        final mercadoSplashPathConexao =
            conexao['mercado_splash_logo_path']?.toString().trim() ?? '';
        if (mercadoSplashPathConexao.isNotEmpty) {
          mercadoSplashLogoPathAtual = mercadoSplashPathConexao;
        }

        final appIconeConexao =
            conexao['app_icone_url']?.toString().trim() ?? '';
        if (appIconeConexao.isNotEmpty) {
          appIconeUrlAtual = appIconeConexao;
          appIconeUrlController.text = appIconeConexao;
        }

        final mercadoAppIconeConexao =
            conexao['mercado_app_icone_url']?.toString().trim() ?? '';
        if (mercadoAppIconeConexao.isNotEmpty) {
          mercadoAppIconeUrlAtual = mercadoAppIconeConexao;
        }

        final mercadoAppIconePathConexao =
            conexao['mercado_app_icone_path']?.toString().trim() ?? '';
        if (mercadoAppIconePathConexao.isNotEmpty) {
          mercadoAppIconePathAtual = mercadoAppIconePathConexao;
        }

        // Importante:
        // Não sobrescrevemos as cores aqui com o retorno de buscar-conexao-mercado.
        // Essa function pode estar em cache/versão antiga ou ser usada para dados técnicos.
        // As cores que aparecem na tela de edição devem vir da listagem/objeto atual
        // usado para abrir a tela. Assim evita voltar para vermelho depois de carregar conexão.
        debugPrint(
          'CORES mantidas da lista na tela: '
          'admin=[${adminCorPrimariaController.text} | ${adminCorSecundariaController.text} | ${adminCorFundoController.text}] '
          'cliente=[${clienteCorPrimariaController.text} | ${clienteCorSecundariaController.text} | ${clienteCorFundoController.text}]',
        );

        final valorUsarApiImagens = conexao.containsKey('usar_api_imagens')
            ? conexao['usar_api_imagens']
            : widget.mercado['usar_api_imagens'];

        usarApiImagens = lerBooleanoDinamico(
          valorUsarApiImagens,
          padrao: false,
        );

        final serpapiKey = conexao['serpapi_key']?.toString() ?? '';
        final serpapiConfig = conexao['serpapi_configurada'];

        serpapiConfigurada =
            serpapiConfig == true || serpapiKey.trim().isNotEmpty;

        final valorTokenEstoqueAtivo =
            conexao.containsKey('estoque_update_token_ativo')
            ? conexao['estoque_update_token_ativo']
            : widget.mercado['estoque_update_token_ativo'];

        estoqueUpdateTokenAtivo = lerBooleanoDinamico(
          valorTokenEstoqueAtivo,
          padrao: false,
        );

        final valorEstoqueDetalhadoAtivo =
            conexao.containsKey('estoque_detalhado_ativo')
            ? conexao['estoque_detalhado_ativo']
            : widget.mercado['estoque_detalhado_ativo'];

        estoqueDetalhadoAtivo = lerBooleanoDinamico(
          valorEstoqueDetalhadoAtivo,
          padrao: false,
        );

        final valorAlterarPrecoConsultaAtivo =
            conexao.containsKey('alterar_preco_consulta_ativo')
            ? conexao['alterar_preco_consulta_ativo']
            : widget.mercado['alterar_preco_consulta_ativo'];

        alterarPrecoConsultaAtivo = lerBooleanoDinamico(
          valorAlterarPrecoConsultaAtivo,
          padrao: false,
        );

        final tokenEstoque =
            conexao['estoque_update_token']?.toString().trim() ?? '';
        final tokenEstoqueConfig = conexao['estoque_update_token_configurado'];

        if (tokenEstoque.isNotEmpty) {
          estoqueUpdateTokenController.text = tokenEstoque;
        }

        estoqueUpdateTokenConfigurado =
            tokenEstoque.isNotEmpty ||
            lerBooleanoDinamico(
              tokenEstoqueConfig,
              padrao: estoqueUpdateTokenConfigurado,
            );

        carregandoConexao = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        carregandoConexao = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao carregar conexão do mercado: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> selecionarLogo() async {
    if (salvando) return;

    try {
      final imagem = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 900,
      );

      if (imagem == null) {
        return;
      }

      setState(() {
        logoSelecionada = File(imagem.path);
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao selecionar logo: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> selecionarLogoMercado() async {
    if (salvando) return;

    try {
      final imagem = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 900,
      );

      if (imagem == null) {
        return;
      }

      setState(() {
        mercadoLogoSelecionada = File(imagem.path);
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao selecionar logo do app Mercado: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> selecionarSplashLogo() async {
    if (salvando) return;

    try {
      final imagem = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1024,
      );

      if (imagem == null) {
        return;
      }

      setState(() {
        splashLogoSelecionada = File(imagem.path);
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao selecionar splash: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> selecionarSplashLogoMercado() async {
    if (salvando) return;

    try {
      final imagem = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1024,
      );

      if (imagem == null) {
        return;
      }

      setState(() {
        mercadoSplashLogoSelecionada = File(imagem.path);
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao selecionar splash do app Mercado: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> selecionarIconeApp() async {
    if (salvando) return;

    try {
      final imagem = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1024,
      );

      if (imagem == null) {
        return;
      }

      setState(() {
        iconeAppSelecionado = File(imagem.path);
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao selecionar ícone do app: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> selecionarIconeAppMercado() async {
    if (salvando) return;

    try {
      final imagem = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1024,
      );

      if (imagem == null) {
        return;
      }

      setState(() {
        mercadoIconeAppSelecionado = File(imagem.path);
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao selecionar ícone do app Mercado: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void removerLogoSelecionada() {
    if (salvando) return;

    setState(() {
      logoSelecionada = null;
    });
  }

  void removerLogoMercadoSelecionada() {
    if (salvando) return;

    setState(() {
      mercadoLogoSelecionada = null;
    });
  }

  void removerSplashLogoSelecionado() {
    if (salvando) return;

    setState(() {
      splashLogoSelecionada = null;
    });
  }

  void removerSplashLogoMercadoSelecionado() {
    if (salvando) return;

    setState(() {
      mercadoSplashLogoSelecionada = null;
    });
  }

  void removerIconeAppSelecionado() {
    if (salvando) return;

    setState(() {
      iconeAppSelecionado = null;
    });
  }

  void removerIconeAppMercadoSelecionado() {
    if (salvando) return;

    setState(() {
      mercadoIconeAppSelecionado = null;
    });
  }

  String gerarCodigoApk(String texto) {
    return texto
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[áàãâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòõôö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String gerarPackageSegmento(String texto) {
    return gerarCodigoApk(texto).replaceAll('_', '');
  }

  bool packageValido(String package) {
    return RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$').hasMatch(package);
  }

  void preencherPadraoApkAdmin() {
    final nome = nomeController.text.trim();
    final codigo = gerarCodigoApk(
      codigoController.text.trim().isEmpty
          ? nome
          : codigoController.text.trim(),
    );
    final segmento = gerarPackageSegmento(codigo);

    if (adminAppNomeController.text.trim().isEmpty && nome.isNotEmpty) {
      adminAppNomeController.text = '$nome Admin';
    }

    if (adminAppPackageController.text.trim().isEmpty && segmento.isNotEmpty) {
      adminAppPackageController.text = 'br.com.apppreco.admin.$segmento';
    }

    if (adminAppBuildCodigoController.text.trim().isEmpty &&
        codigo.isNotEmpty) {
      adminAppBuildCodigoController.text = 'admin_$codigo';
    }
  }

  void preencherPadraoApkMercado() {
    final nome = nomeController.text.trim();
    final codigo = gerarCodigoApk(
      codigoController.text.trim().isEmpty
          ? nome
          : codigoController.text.trim(),
    );
    final segmento = gerarPackageSegmento(codigo);

    if (mercadoAppNomeController.text.trim().isEmpty && nome.isNotEmpty) {
      mercadoAppNomeController.text = nome;
    }

    if (mercadoAppPackageController.text.trim().isEmpty &&
        segmento.isNotEmpty) {
      mercadoAppPackageController.text = 'br.com.apppreco.mercado.$segmento';
    }

    if (mercadoAppBuildCodigoController.text.trim().isEmpty &&
        codigo.isNotEmpty) {
      mercadoAppBuildCodigoController.text = 'mercado_$codigo';
    }
  }

  String gerarTokenSeguroEstoque() {
    const caracteres =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-@#';
    final random = Random.secure();

    return List.generate(48, (_) {
      return caracteres[random.nextInt(caracteres.length)];
    }).join();
  }

  void gerarTokenEstoque() {
    if (salvando || carregandoConexao) return;

    setState(() {
      estoqueUpdateTokenController.text = gerarTokenSeguroEstoque();
      estoqueUpdateTokenAtivo = true;
    });
  }

  Future<void> copiarTokenEstoque() async {
    final token = estoqueUpdateTokenController.text.trim();

    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum token informado para copiar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: token));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Token copiado'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> salvarTokenUpdateEstoqueMercado({
    required String mercadoId,
    required bool ativo,
    required String token,
    required bool estoqueDetalhadoAtivo,
    required bool alterarPrecoConsultaAtivo,
  }) async {
    final dados = <String, dynamic>{
      'estoque_update_token_ativo': ativo,
      'estoque_detalhado_ativo': estoqueDetalhadoAtivo,
      'alterar_preco_consulta_ativo': alterarPrecoConsultaAtivo,
    };

    if (token.trim().isNotEmpty) {
      dados['estoque_update_token'] = token.trim();
    }

    await service.supabase.from('mercados').update(dados).eq('id', mercadoId);
  }

  Future<void> salvarConfiguracaoApksMercado({
    required String mercadoId,
    required bool gerarAdmin,
    required String adminNome,
    required String adminPackage,
    required String adminBuildCodigo,
    required bool gerarMercado,
    required String mercadoNome,
    required String mercadoPackage,
    required String mercadoBuildCodigo,
  }) async {
    await service.supabase
        .from('mercados')
        .update({
          'gerar_apk_admin': gerarAdmin,
          'admin_app_nome': gerarAdmin ? adminNome : null,
          'admin_app_package': gerarAdmin ? adminPackage : null,
          'admin_app_build_codigo': gerarAdmin ? adminBuildCodigo : null,
          'gerar_apk_mercado': gerarMercado,
          'mercado_app_nome': gerarMercado ? mercadoNome : null,
          'mercado_app_package': gerarMercado ? mercadoPackage : null,
          'mercado_app_build_codigo': gerarMercado ? mercadoBuildCodigo : null,

          // Compatibilidade com scripts antigos.
          'apk_personalizado': gerarMercado,
          'app_nome': gerarMercado ? mercadoNome : null,
          'app_package': gerarMercado ? mercadoPackage : null,
          'app_build_codigo': gerarMercado ? mercadoBuildCodigo : null,
        })
        .eq('id', mercadoId);
  }

  Future<void> salvar() async {
    final mercadoId = widget.mercado['id']?.toString() ?? '';

    final nome = nomeController.text.trim();
    final codigo = codigoController.text.trim();
    final cidade = cidadeController.text.trim();
    final estado = estadoController.text.trim().toUpperCase();

    final apiBaseUrl = apiBaseUrlController.text.trim();
    final supabaseUrl = supabaseUrlController.text.trim();
    final supabaseAnonKey = supabaseAnonKeyController.text.trim();
    final serviceRole = supabaseServiceRoleKeyController.text.trim();
    final serpapiKey = serpapiKeyController.text.trim();

    final adminCorPrimaria = normalizarCorHex(
      adminCorPrimariaController.text,
      '#E30613',
    );
    final adminCorSecundaria = normalizarCorHex(
      adminCorSecundariaController.text,
      '#C90010',
    );
    final adminCorFundo = normalizarCorHex(
      adminCorFundoController.text,
      '#F5F7FA',
    );

    final clienteCorPrimaria = normalizarCorHex(
      clienteCorPrimariaController.text,
      '#E30613',
    );
    final clienteCorSecundaria = normalizarCorHex(
      clienteCorSecundariaController.text,
      '#C90010',
    );
    final clienteCorFundo = normalizarCorHex(
      clienteCorFundoController.text,
      '#FFF7F7',
    );

    final adminAppNome = adminAppNomeController.text.trim();
    final adminAppPackage = adminAppPackageController.text.trim();
    final adminAppBuildCodigo = gerarCodigoApk(
      adminAppBuildCodigoController.text.trim(),
    );

    final mercadoAppNome = mercadoAppNomeController.text.trim();
    final mercadoAppPackage = mercadoAppPackageController.text.trim();
    final mercadoAppBuildCodigo = gerarCodigoApk(
      mercadoAppBuildCodigoController.text.trim(),
    );

    // Campos antigos continuam recebendo os dados do APK Mercado,
    // para manter compatibilidade com scripts que ainda usam app_nome/app_package.
    final appNome = mercadoAppNome;
    final appPackage = mercadoAppPackage;
    final appBuildCodigo = mercadoAppBuildCodigo;
    final appIconeUrl = appIconeUrlController.text.trim();
    final appIconePath = appIconePathController.text.trim();

    final estoqueUpdateToken = estoqueUpdateTokenController.text.trim();

    if (mercadoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mercado sem ID'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (carregandoConexao) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aguarde carregar as configurações da loja'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (nome.isEmpty ||
        codigo.isEmpty ||
        (fonteProdutos == 'API' && apiBaseUrl.isEmpty) ||
        supabaseUrl.isEmpty ||
        supabaseAnonKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Informe nome, código, API base URL, Supabase URL e anon key',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (gerarApkAdmin &&
        (adminAppNome.isEmpty ||
            adminAppPackage.isEmpty ||
            adminAppBuildCodigo.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Para gerar APK Admin, informe nome, package e código de build do Admin',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (gerarApkAdmin && !packageValido(adminAppPackage)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Package do APK Admin inválido'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (gerarApkMercado &&
        (mercadoAppNome.isEmpty ||
            mercadoAppPackage.isEmpty ||
            mercadoAppBuildCodigo.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Para gerar APK Mercado, informe nome, package e código de build do Mercado',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (gerarApkMercado && !packageValido(mercadoAppPackage)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Package do APK Mercado inválido'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (estoqueUpdateTokenAtivo &&
        estoqueUpdateToken.isEmpty &&
        !estoqueUpdateTokenConfigurado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Para ativar o update de estoque, informe ou gere um token de autorização',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      salvando = true;
    });

    try {
      debugPrint('================ DEBUG SALVAR CORES ================');
      debugPrint('mercadoId=$mercadoId codigo=$codigo');
      debugPrint(
        'SALVAR admin=[$adminCorPrimaria | $adminCorSecundaria | $adminCorFundo] '
        'cliente=[$clienteCorPrimaria | $clienteCorSecundaria | $clienteCorFundo]',
      );
      debugPrint('===================================================');

      await service.atualizarMercado(
        mercadoId: mercadoId,
        nome: nome,
        codigo: codigo,
        ativo: ativo,
        cidade: cidade,
        estado: estado,
        apiBaseUrl: apiBaseUrl,
        supabaseUrl: supabaseUrl,
        supabaseAnonKey: supabaseAnonKey,
        supabaseServiceRoleKey: serviceRole.isEmpty ? null : serviceRole,
        usarApiImagens: usarApiImagens,
        fonteProdutos: fonteProdutos,
        serpapiKey: serpapiKey.isEmpty ? null : serpapiKey,
        adminCorPrimaria: adminCorPrimaria,
        adminCorSecundaria: adminCorSecundaria,
        adminCorFundo: adminCorFundo,
        clienteCorPrimaria: clienteCorPrimaria,
        clienteCorSecundaria: clienteCorSecundaria,
        clienteCorFundo: clienteCorFundo,
        estoqueUpdateToken: estoqueUpdateToken.isEmpty
            ? null
            : estoqueUpdateToken,
        estoqueUpdateTokenAtivo: estoqueUpdateTokenAtivo,
        estoqueDetalhadoAtivo: estoqueDetalhadoAtivo,
        alterarPrecoConsultaAtivo: alterarPrecoConsultaAtivo,

        // APK Admin
        gerarApkAdmin: gerarApkAdmin,
        adminAppNome: gerarApkAdmin ? adminAppNome : null,
        adminAppPackage: gerarApkAdmin ? adminAppPackage : null,
        adminAppBuildCodigo: gerarApkAdmin ? adminAppBuildCodigo : null,

        // APK Mercado / Cliente
        gerarApkMercado: gerarApkMercado,
        mercadoAppNome: gerarApkMercado ? mercadoAppNome : null,
        mercadoAppPackage: gerarApkMercado ? mercadoAppPackage : null,
        mercadoAppBuildCodigo: gerarApkMercado ? mercadoAppBuildCodigo : null,

        // Compatibilidade com campos antigos
        apkPersonalizado: gerarApkMercado,
        appNome: gerarApkMercado ? mercadoAppNome : null,
        appPackage: gerarApkMercado ? mercadoAppPackage : null,
        appBuildCodigo: gerarApkMercado ? mercadoAppBuildCodigo : null,
        logoLoginUrl: logoUrlAtual.isEmpty ? null : logoUrlAtual,
        logoUrl: mercadoLogoUrlAtual.isEmpty ? null : mercadoLogoUrlAtual,
        logoPath: mercadoLogoPathAtual.isEmpty ? null : mercadoLogoPathAtual,
        splashLogoUrl: splashLogoUrlAtual.isEmpty ? null : splashLogoUrlAtual,
        appIconeUrl: appIconeUrl.isEmpty ? null : appIconeUrl,
        appIconePath: appIconePath.isEmpty ? null : appIconePath,
        mercadoSplashLogoUrl: mercadoSplashLogoUrlAtual.isEmpty
            ? null
            : mercadoSplashLogoUrlAtual,
        mercadoSplashLogoPath: mercadoSplashLogoPathAtual.isEmpty
            ? null
            : mercadoSplashLogoPathAtual,
        mercadoAppIconeUrl: mercadoAppIconeUrlAtual.isEmpty
            ? null
            : mercadoAppIconeUrlAtual,
        mercadoAppIconePath: mercadoAppIconePathAtual.isEmpty
            ? null
            : mercadoAppIconePathAtual,
      );

      await salvarTokenUpdateEstoqueMercado(
        mercadoId: mercadoId,
        ativo: estoqueUpdateTokenAtivo,
        token: estoqueUpdateToken,
        estoqueDetalhadoAtivo: estoqueDetalhadoAtivo,
        alterarPrecoConsultaAtivo: alterarPrecoConsultaAtivo,
      );

      if (logoSelecionada != null) {
        await service.atualizarLogoLoginMercado(
          mercadoId: mercadoId,
          logoFile: logoSelecionada!,
        );
      }

      if (mercadoLogoSelecionada != null) {
        await service.atualizarLogoMercado(
          mercadoId: mercadoId,
          logoFile: mercadoLogoSelecionada!,
        );
      }

      if (splashLogoSelecionada != null) {
        await service.atualizarSplashLogoMercado(
          mercadoId: mercadoId,
          splashFile: splashLogoSelecionada!,
        );
      }

      if (mercadoSplashLogoSelecionada != null) {
        await service.atualizarSplashLogoMercadoCliente(
          mercadoId: mercadoId,
          splashFile: mercadoSplashLogoSelecionada!,
        );
      }

      if (iconeAppSelecionado != null) {
        await service.atualizarIconeAppMercado(
          mercadoId: mercadoId,
          iconeFile: iconeAppSelecionado!,
        );
      }

      if (mercadoIconeAppSelecionado != null) {
        await service.atualizarIconeAppMercadoCliente(
          mercadoId: mercadoId,
          iconeFile: mercadoIconeAppSelecionado!,
        );
      }

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        salvando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao atualizar mercado: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String normalizarCorHex(String valor, String padrao) {
    var cor = valor.trim();

    if (cor.isEmpty) {
      cor = padrao;
    }

    if (!cor.startsWith('#')) {
      cor = '#$cor';
    }

    cor = cor.toUpperCase();

    final valido = RegExp(r'^#[0-9A-F]{6}$').hasMatch(cor);

    return valido ? cor : padrao;
  }

  Color corHexParaColor(String valor, Color fallback) {
    final cor = normalizarCorHex(valor, '');
    if (cor.isEmpty) {
      return fallback;
    }

    try {
      return Color(int.parse('FF${cor.substring(1)}', radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  List<Map<String, dynamic>> get coresPrincipais => const [
    {'nome': 'Vermelho padrão', 'hex': '#E30613'},
    {'nome': 'Vermelho escuro', 'hex': '#C90010'},
    {'nome': 'Preto', 'hex': '#111111'},
    {'nome': 'Cinza escuro', 'hex': '#374151'},
    {'nome': 'Branco', 'hex': '#FFFFFF'},
    {'nome': 'Verde', 'hex': '#16A34A'},
    {'nome': 'Verde escuro', 'hex': '#0F7A35'},
    {'nome': 'Azul', 'hex': '#2563EB'},
    {'nome': 'Azul escuro', 'hex': '#1E3A8A'},
    {'nome': 'Amarelo', 'hex': '#FACC15'},
    {'nome': 'Laranja', 'hex': '#F97316'},
    {'nome': 'Roxo', 'hex': '#7C3AED'},
    {'nome': 'Rosa', 'hex': '#EC4899'},
    {'nome': 'Fundo claro', 'hex': '#FFF7F7'},
    {'nome': 'Fundo cinza', 'hex': '#F5F7FA'},
    {'nome': 'Fundo verde', 'hex': '#F4FFF8'},
    {'nome': 'Fundo preto', 'hex': '#111111'},
  ];

  Future<void> abrirPaletaCores({
    required TextEditingController controller,
    required String titulo,
    required Color fallback,
  }) async {
    if (salvando || carregandoConexao) {
      return;
    }

    final corAtual = normalizarCorHex(
      controller.text,
      '#${fallback.value.toRadixString(16).substring(2).toUpperCase()}',
    );

    final corSelecionada = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          constraints: const BoxConstraints(maxHeight: 560),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Toque em uma cor abaixo ou digite o código manualmente no campo.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: coresPrincipais.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = coresPrincipais[index];
                      final hex = item['hex'] as String;
                      final nome = item['nome'] as String;
                      final cor = corHexParaColor(hex, fallback);
                      final selecionada =
                          hex.toUpperCase() == corAtual.toUpperCase();

                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.pop(context, hex),
                        child: Container(
                          height: 58,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selecionada
                                ? cor.withValues(alpha: 0.10)
                                : const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selecionada
                                  ? cor
                                  : Colors.black.withValues(alpha: 0.08),
                              width: selecionada ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: cor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.black.withValues(alpha: 0.14),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  nome,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF374151),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                hex,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black.withValues(alpha: 0.55),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (selecionada) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.check_circle, color: cor, size: 20),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (corSelecionada == null || corSelecionada.trim().isEmpty) {
      return;
    }

    setState(() {
      controller.text = normalizarCorHex(corSelecionada, corAtual);
    });
  }

  Widget campoCor({
    required TextEditingController controller,
    required String label,
    required String hint,
    required Color fallback,
  }) {
    final cor = corHexParaColor(controller.text, fallback);

    return TextField(
      controller: controller,
      enabled: !salvando && !carregandoConexao,
      onChanged: (valor) {
        final normalizada = valor.trim();

        // Recria a prévia assim que o valor parece uma cor completa.
        if (normalizada.length >= 6) {
          setState(() {});
        }
      },
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
        LengthLimitingTextInputFormatter(7),
      ],
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Padding(
          padding: const EdgeInsets.all(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => abrirPaletaCores(
              controller: controller,
              titulo: label,
              fallback: fallback,
            ),
            child: Tooltip(
              message: 'Escolher cor',
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: cor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: cor.withValues(alpha: 0.20),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        suffixIcon: IconButton(
          tooltip: 'Abrir paleta de cores',
          onPressed: salvando || carregandoConexao
              ? null
              : () => abrirPaletaCores(
                  controller: controller,
                  titulo: label,
                  fallback: fallback,
                ),
          icon: const Icon(Icons.palette_outlined),
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget campoTexto({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    int maxLines = 1,
    bool obrigatorio = false,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      enabled: !salvando && !carregandoConexao,
      decoration: InputDecoration(
        labelText: obrigatorio ? '$label *' : label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget avisoCarregandoConexao() {
    if (!carregandoConexao) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Carregando configurações da loja...',
              style: TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget cardImagemEdicao({
    required String titulo,
    required String descricaoSemImagem,
    required String descricaoImagemAtual,
    required String descricaoImagemNova,
    required String urlAtual,
    required File? arquivoSelecionado,
    required IconData iconeVazio,
    required VoidCallback selecionar,
    required VoidCallback remover,
    required BoxFit fitImagem,
    bool formatoIcone = false,
  }) {
    final temImagemAtual = urlAtual.trim().isNotEmpty;
    final temImagemNova = arquivoSelecionado != null;

    final double larguraPreview = formatoIcone ? 92 : 130;
    final double alturaPreview = 92;
    final double raioPreview = formatoIcone ? 24 : 18;
    final double raioImagem = formatoIcone ? 22 : 16;

    Widget conteudoPreview;

    if (temImagemNova) {
      conteudoPreview = ClipRRect(
        borderRadius: BorderRadius.circular(raioImagem),
        child: Image.file(
          arquivoSelecionado!,
          width: larguraPreview,
          height: alturaPreview,
          fit: fitImagem,
        ),
      );
    } else if (temImagemAtual) {
      conteudoPreview = ClipRRect(
        borderRadius: BorderRadius.circular(raioImagem),
        child: Image.network(
          urlAtual,
          width: larguraPreview,
          height: alturaPreview,
          fit: fitImagem,
          errorBuilder: (_, __, ___) {
            return Icon(
              iconeVazio,
              color: vermelho,
              size: formatoIcone ? 42 : 44,
            );
          },
        ),
      );
    } else {
      conteudoPreview = Icon(
        iconeVazio,
        color: vermelho,
        size: formatoIcone ? 42 : 44,
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: larguraPreview,
            height: alturaPreview,
            decoration: BoxDecoration(
              color: vermelho.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(raioPreview),
              border: Border.all(color: vermelho.withValues(alpha: 0.18)),
            ),
            child: conteudoPreview,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  temImagemNova
                      ? descricaoImagemNova
                      : temImagemAtual
                      ? descricaoImagemAtual
                      : descricaoSemImagem,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: salvando ? null : selecionar,
                      icon: const Icon(Icons.photo_library),
                      label: Text(
                        temImagemAtual || temImagemNova
                            ? 'Trocar'
                            : 'Selecionar',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: vermelho,
                        side: const BorderSide(color: vermelho),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    if (temImagemNova)
                      OutlinedButton.icon(
                        onPressed: salvando ? null : remover,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Cancelar troca'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget areaDebugCores() {
    String valor(dynamic v) {
      final texto = v?.toString().trim() ?? '';
      return texto.isEmpty ? '(vazio)' : texto;
    }

    Widget linha(String titulo, String valorTexto) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(
          '$titulo: $valorTexto',
          style: const TextStyle(
            fontSize: 12,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: Color(0xFF374151),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.bug_report_outlined,
                size: 18,
                color: Color(0xFFB45309),
              ),
              SizedBox(width: 8),
              Text(
                'Debug de cores',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF92400E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          linha(
            'Lista Admin',
            '${valor(widget.mercado['admin_cor_primaria'])} | ${valor(widget.mercado['admin_cor_secundaria'])} | ${valor(widget.mercado['admin_cor_fundo'])}',
          ),
          linha(
            'Lista Mercado',
            '${valor(widget.mercado['cliente_cor_primaria'])} | ${valor(widget.mercado['cliente_cor_secundaria'])} | ${valor(widget.mercado['cliente_cor_fundo'])}',
          ),
          const Divider(height: 14),
          linha(
            'Tela Admin',
            '${adminCorPrimariaController.text} | ${adminCorSecundariaController.text} | ${adminCorFundoController.text}',
          ),
          linha(
            'Tela Mercado',
            '${clienteCorPrimariaController.text} | ${clienteCorSecundariaController.text} | ${clienteCorFundoController.text}',
          ),
        ],
      ),
    );
  }

  Widget areaCoresAdmin() {
    final corPrimaria = corHexParaColor(
      adminCorPrimariaController.text,
      const Color(0xFFE30613),
    );
    final corSecundaria = corHexParaColor(
      adminCorSecundariaController.text,
      const Color(0xFFC90010),
    );
    final corFundo = corHexParaColor(
      adminCorFundoController.text,
      const Color(0xFFF5F7FA),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cores do app Admin',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Altere as cores da tela de login do Admin. O app busca essas cores pela Central.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Container(
            height: 62,
            decoration: BoxDecoration(
              color: corFundo,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: corPrimaria,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(15),
                      ),
                    ),
                  ),
                ),
                Expanded(child: Container(color: corSecundaria)),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: corFundo,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(15),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          campoCor(
            controller: adminCorPrimariaController,
            label: 'Cor primária Admin',
            hint: '#E30613',
            fallback: const Color(0xFFE30613),
          ),
          const SizedBox(height: 14),
          campoCor(
            controller: adminCorSecundariaController,
            label: 'Cor secundária Admin',
            hint: '#C90010',
            fallback: const Color(0xFFC90010),
          ),
          const SizedBox(height: 14),
          campoCor(
            controller: adminCorFundoController,
            label: 'Cor de fundo Admin',
            hint: '#F5F7FA',
            fallback: const Color(0xFFF5F7FA),
          ),
        ],
      ),
    );
  }

  Widget areaCoresMercado() {
    final corPrimaria = corHexParaColor(
      clienteCorPrimariaController.text,
      const Color(0xFFE30613),
    );
    final corSecundaria = corHexParaColor(
      clienteCorSecundariaController.text,
      const Color(0xFFC90010),
    );
    final corFundo = corHexParaColor(
      clienteCorFundoController.text,
      const Color(0xFFFFF7F7),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cores do app Mercado',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Altere as cores do app de compras do cliente. O app Mercado busca essas cores pela Central.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Container(
            height: 62,
            decoration: BoxDecoration(
              color: corFundo,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: corPrimaria,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(15),
                      ),
                    ),
                  ),
                ),
                Expanded(child: Container(color: corSecundaria)),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: corFundo,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(15),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          campoCor(
            controller: clienteCorPrimariaController,
            label: 'Cor primária Mercado',
            hint: '#E30613',
            fallback: const Color(0xFFE30613),
          ),
          const SizedBox(height: 14),
          campoCor(
            controller: clienteCorSecundariaController,
            label: 'Cor secundária Mercado',
            hint: '#C90010',
            fallback: const Color(0xFFC90010),
          ),
          const SizedBox(height: 14),
          campoCor(
            controller: clienteCorFundoController,
            label: 'Cor de fundo Mercado',
            hint: '#FFF7F7',
            fallback: const Color(0xFFFFF7F7),
          ),
        ],
      ),
    );
  }

  Widget areaLogo() {
    return cardImagemEdicao(
      titulo: 'Logo do app Admin/login',
      descricaoSemImagem:
          'Nenhuma logo Admin cadastrada. Essa imagem aparece dentro do app Admin e na tela inicial/login.',
      descricaoImagemAtual:
          'Logo Admin atual cadastrada. Toque em Trocar para escolher outra.',
      descricaoImagemNova: 'Nova logo Admin selecionada para envio.',
      urlAtual: logoUrlAtual,
      arquivoSelecionado: logoSelecionada,
      iconeVazio: Icons.store,
      selecionar: selecionarLogo,
      remover: removerLogoSelecionada,
      fitImagem: BoxFit.contain,
      formatoIcone: false,
    );
  }

  Widget areaLogoMercado() {
    return cardImagemEdicao(
      titulo: 'Logo do app Mercado/Cliente',
      descricaoSemImagem:
          'Nenhuma logo Mercado cadastrada. Essa imagem aparece no app dos clientes.',
      descricaoImagemAtual:
          'Logo Mercado atual cadastrada. Toque em Trocar para escolher outra.',
      descricaoImagemNova: 'Nova logo Mercado selecionada para envio.',
      urlAtual: mercadoLogoUrlAtual,
      arquivoSelecionado: mercadoLogoSelecionada,
      iconeVazio: Icons.shopping_basket,
      selecionar: selecionarLogoMercado,
      remover: removerLogoMercadoSelecionada,
      fitImagem: BoxFit.contain,
      formatoIcone: false,
    );
  }

  Widget areaSplashLogo() {
    return cardImagemEdicao(
      titulo: 'Splash fixo ao abrir o app',
      descricaoSemImagem:
          'Nenhum splash cadastrado. Essa imagem será aplicada pelo script no APK.',
      descricaoImagemAtual:
          'Splash atual cadastrado. Toque em Trocar para escolher outro.',
      descricaoImagemNova: 'Novo splash selecionado para envio.',
      urlAtual: splashLogoUrlAtual,
      arquivoSelecionado: splashLogoSelecionada,
      iconeVazio: Icons.screenshot_monitor,
      selecionar: selecionarSplashLogo,
      remover: removerSplashLogoSelecionado,
      fitImagem: BoxFit.contain,
      formatoIcone: true,
    );
  }

  Widget areaSplashLogoMercado() {
    return cardImagemEdicao(
      titulo: 'Splash do app Mercado/Cliente',
      descricaoSemImagem:
          'Nenhum splash Mercado cadastrado. Essa imagem será aplicada pelo script no APK Mercado/Cliente.',
      descricaoImagemAtual:
          'Splash Mercado atual cadastrado. Toque em Trocar para escolher outro.',
      descricaoImagemNova: 'Novo splash do app Mercado selecionado para envio.',
      urlAtual: mercadoSplashLogoUrlAtual,
      arquivoSelecionado: mercadoSplashLogoSelecionada,
      iconeVazio: Icons.storefront,
      selecionar: selecionarSplashLogoMercado,
      remover: removerSplashLogoMercadoSelecionado,
      fitImagem: BoxFit.contain,
      formatoIcone: true,
    );
  }

  Widget areaIconeApp() {
    return cardImagemEdicao(
      titulo: 'Ícone do app Admin Android',
      descricaoSemImagem:
          'Nenhum ícone Admin cadastrado. Essa imagem será usada como ícone do APK Admin.',
      descricaoImagemAtual:
          'Ícone Admin atual cadastrado. Toque em Trocar para escolher outro.',
      descricaoImagemNova: 'Novo ícone do app Admin selecionado para envio.',
      urlAtual: appIconeUrlAtual,
      arquivoSelecionado: iconeAppSelecionado,
      iconeVazio: Icons.admin_panel_settings,
      selecionar: selecionarIconeApp,
      remover: removerIconeAppSelecionado,
      fitImagem: BoxFit.cover,
      formatoIcone: true,
    );
  }

  Widget areaIconeAppMercado() {
    return cardImagemEdicao(
      titulo: 'Ícone do app Mercado Android',
      descricaoSemImagem:
          'Nenhum ícone Mercado cadastrado. Essa imagem será usada como ícone do APK Mercado/Cliente.',
      descricaoImagemAtual:
          'Ícone Mercado atual cadastrado. Toque em Trocar para escolher outro.',
      descricaoImagemNova: 'Novo ícone do app Mercado selecionado para envio.',
      urlAtual: mercadoAppIconeUrlAtual,
      arquivoSelecionado: mercadoIconeAppSelecionado,
      iconeVazio: Icons.shopping_bag,
      selecionar: selecionarIconeAppMercado,
      remover: removerIconeAppMercadoSelecionado,
      fitImagem: BoxFit.cover,
      formatoIcone: true,
    );
  }

  Widget cardApkPersonalizado({
    required String titulo,
    required String descricaoAtivo,
    required String descricaoInativo,
    required bool ativo,
    required ValueChanged<bool> onChanged,
    required TextEditingController nomeAppController,
    required TextEditingController packageController,
    required TextEditingController buildCodigoController,
    required VoidCallback preencherPadrao,
    required String hintNome,
    required String hintPackage,
    required String hintBuild,
    required Color cor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ativo
              ? cor.withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ativo ? descricaoAtivo : descricaoInativo,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: ativo,
                activeThumbColor: vermelho,
                onChanged: salvando || carregandoConexao ? null : onChanged,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cor.withValues(alpha: 0.18)),
            ),
            child: const Text(
              'O package precisa ser único. Se dois APKs tiverem o mesmo package, o Android sobrescreve um pelo outro.',
              style: TextStyle(color: Colors.black87, fontSize: 13),
            ),
          ),
          if (ativo) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: salvando || carregandoConexao ? null : preencherPadrao,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Preencher padrão'),
              style: OutlinedButton.styleFrom(
                foregroundColor: vermelho,
                side: const BorderSide(color: vermelho),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 14),
            campoTexto(
              controller: nomeAppController,
              label: 'Nome do app',
              icon: Icons.app_shortcut,
              hint: hintNome,
              obrigatorio: true,
            ),
            const SizedBox(height: 14),
            campoTexto(
              controller: packageController,
              label: 'Package Android',
              icon: Icons.android,
              hint: hintPackage,
              obrigatorio: true,
            ),
            const SizedBox(height: 14),
            campoTexto(
              controller: buildCodigoController,
              label: 'Código de build',
              icon: Icons.code,
              hint: hintBuild,
              obrigatorio: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget areaApkPersonalizado() {
    return Column(
      children: [
        cardApkPersonalizado(
          titulo: 'APK Admin',
          descricaoAtivo:
              'Esta loja entrará na geração automática do app Admin.',
          descricaoInativo: 'Não gerar APK Admin para esta loja.',
          ativo: gerarApkAdmin,
          onChanged: (valor) {
            setState(() {
              gerarApkAdmin = valor;
              if (valor) preencherPadraoApkAdmin();
            });
          },
          nomeAppController: adminAppNomeController,
          packageController: adminAppPackageController,
          buildCodigoController: adminAppBuildCodigoController,
          preencherPadrao: () {
            setState(preencherPadraoApkAdmin);
          },
          hintNome: 'Ex: SM Admin',
          hintPackage: 'Ex: br.com.apppreco.admin.saomateus',
          hintBuild: 'Ex: admin_sao_mateus',
          cor: Colors.deepPurple,
        ),
        const SizedBox(height: 14),
        cardApkPersonalizado(
          titulo: 'APK Mercado / Cliente',
          descricaoAtivo:
              'Esta loja entrará na geração automática do app de compras.',
          descricaoInativo: 'Não gerar APK Mercado para esta loja.',
          ativo: gerarApkMercado,
          onChanged: (valor) {
            setState(() {
              gerarApkMercado = valor;
              apkPersonalizado = valor;
              if (valor) preencherPadraoApkMercado();
            });
          },
          nomeAppController: mercadoAppNomeController,
          packageController: mercadoAppPackageController,
          buildCodigoController: mercadoAppBuildCodigoController,
          preencherPadrao: () {
            setState(preencherPadraoApkMercado);
          },
          hintNome: 'Ex: SM Compras',
          hintPackage: 'Ex: br.com.apppreco.mercado.saomateus',
          hintBuild: 'Ex: mercado_sao_mateus',
          cor: Colors.blue,
        ),
      ],
    );
  }

  Widget areaTokenUpdateEstoque() {
    final tokenDigitado = estoqueUpdateTokenController.text.trim().isNotEmpty;
    final tokenOk = tokenDigitado || estoqueUpdateTokenConfigurado;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: estoqueUpdateTokenAtivo
              ? Colors.green.withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Autorizar update de estoque',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      estoqueUpdateTokenAtivo
                          ? 'A API poderá aceitar alteração de estoque usando o token abaixo.'
                          : 'A alteração de estoque pela API fica desativada para esta loja.',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: estoqueUpdateTokenAtivo,
                activeThumbColor: vermelho,
                onChanged: salvando || carregandoConexao
                    ? null
                    : (valor) {
                        setState(() {
                          estoqueUpdateTokenAtivo = valor;
                        });
                      },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: estoqueUpdateTokenAtivo
                  ? tokenOk
                        ? Colors.green.withValues(alpha: 0.08)
                        : Colors.orange.withValues(alpha: 0.08)
                  : Colors.grey.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: estoqueUpdateTokenAtivo
                    ? tokenOk
                          ? Colors.green.withValues(alpha: 0.18)
                          : Colors.orange.withValues(alpha: 0.18)
                    : Colors.grey.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              estoqueUpdateTokenAtivo
                  ? tokenOk
                        ? 'Token configurado. Use este mesmo valor no .env da API como ESTOQUE_UPDATE_TOKEN.'
                        : 'Ativo, mas sem token. Gere ou informe um token antes de salvar.'
                  : 'Desativado. A tela salva o status na Central, mas a API também precisa estar configurada.',
              style: const TextStyle(color: Colors.black87, fontSize: 13),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: estoqueDetalhadoAtivo
                  ? Colors.blue.withValues(alpha: 0.08)
                  : Colors.grey.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: estoqueDetalhadoAtivo
                    ? Colors.blue.withValues(alpha: 0.20)
                    : Colors.grey.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Estoque detalhado por local',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        estoqueDetalhadoAtivo
                            ? 'A tela de entrada/correcao buscara /estoque-locais e permitira escolher o local.'
                            : 'A tela usara o estoque total do produto e nao chamara /estoque-locais.',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: estoqueDetalhadoAtivo,
                  activeThumbColor: Colors.blue,
                  onChanged: salvando || carregandoConexao
                      ? null
                      : (valor) {
                          setState(() {
                            estoqueDetalhadoAtivo = valor;
                          });
                        },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: alterarPrecoConsultaAtivo
                  ? Colors.green.withValues(alpha: 0.08)
                  : Colors.grey.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: alterarPrecoConsultaAtivo
                    ? Colors.green.withValues(alpha: 0.20)
                    : Colors.grey.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Alterar preço na consulta',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        alterarPrecoConsultaAtivo
                            ? 'A tela de imagem do produto exibirá o botão Alterar preço e enviará o update para a API da loja.'
                            : 'O botão Alterar preço ficará oculto na tela de imagem do produto.',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: alterarPrecoConsultaAtivo,
                  activeThumbColor: Colors.green,
                  onChanged: salvando || carregandoConexao
                      ? null
                      : (valor) {
                          setState(() {
                            alterarPrecoConsultaAtivo = valor;
                          });
                        },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          campoTexto(
            controller: estoqueUpdateTokenController,
            label: 'Token de update de estoque',
            icon: Icons.security,
            hint: 'Ex: Diamante_Estoque_2026_@Update_7291',
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: salvando || carregandoConexao
                    ? null
                    : gerarTokenEstoque,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Gerar token'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: vermelho,
                  side: const BorderSide(color: vermelho),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: salvando || carregandoConexao
                    ? null
                    : copiarTokenEstoque,
                icon: const Icon(Icons.copy),
                label: const Text('Copiar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                  side: const BorderSide(color: Colors.blue),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget resumoMercadoEdicao(String nomeMercado) {
    final codigo = codigoController.text.trim();
    final cidade = cidadeController.text.trim();
    final estado = estadoController.text.trim();
    final logo = logoUrlAtual.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: vermelho.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: vermelho.withValues(alpha: 0.16)),
            ),
            child: logo.isEmpty
                ? const Icon(Icons.store, color: vermelho, size: 30)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.network(
                      logo,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return const Icon(
                          Icons.store,
                          color: vermelho,
                          size: 30,
                        );
                      },
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nomeMercado,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  codigo.isEmpty ? 'Código não informado' : 'Código: $codigo',
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
                if (cidade.isNotEmpty || estado.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    '$cidade${cidade.isNotEmpty && estado.isNotEmpty ? ' - ' : ''}$estado',
                    style: const TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: ativo
                  ? Colors.green.withValues(alpha: 0.12)
                  : Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              ativo ? 'Ativo' : 'Inativo',
              style: TextStyle(
                color: ativo ? Colors.green : Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget botaoSecaoEdicao({
    required double largura,
    required String id,
    required String titulo,
    required String subtitulo,
    required IconData icone,
    required Color cor,
  }) {
    final selecionado = secaoEdicaoSelecionada == id;

    return SizedBox(
      width: largura,
      child: Material(
        color: selecionado ? cor : Colors.white,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: salvando
              ? null
              : () {
                  setState(() {
                    secaoEdicaoSelecionada = id;
                  });
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selecionado ? cor : Colors.black.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: selecionado
                      ? cor.withValues(alpha: 0.22)
                      : Colors.black.withValues(alpha: 0.03),
                  blurRadius: selecionado ? 12 : 8,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: selecionado
                        ? Colors.white.withValues(alpha: 0.18)
                        : cor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icone, color: selecionado ? Colors.white : cor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          color: selecionado
                              ? Colors.white
                              : const Color(0xFF1F2937),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selecionado
                              ? Colors.white.withValues(alpha: 0.82)
                              : Colors.black54,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget painelSecoesEdicao() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final larguraDisponivel = constraints.maxWidth;
        final larguraBotao = larguraDisponivel >= 760
            ? (larguraDisponivel - 24) / 3
            : larguraDisponivel >= 520
            ? (larguraDisponivel - 12) / 2
            : larguraDisponivel;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'O que deseja alterar?',
              style: TextStyle(
                color: Color(0xFF1F2937),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Escolha uma área abaixo para editar somente as configurações daquele grupo.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                botaoSecaoEdicao(
                  largura: larguraBotao,
                  id: 'dados',
                  titulo: 'Dados da loja',
                  subtitulo: 'Nome, código, cidade e status',
                  icone: Icons.store_mall_directory,
                  cor: vermelho,
                ),
                botaoSecaoEdicao(
                  largura: larguraBotao,
                  id: 'visual_admin',
                  titulo: 'Visual Admin',
                  subtitulo: 'Logo, splash, ícone e cores',
                  icone: Icons.palette,
                  cor: Colors.deepPurple,
                ),
                botaoSecaoEdicao(
                  largura: larguraBotao,
                  id: 'visual_mercado',
                  titulo: 'Visual Mercado',
                  subtitulo: 'Splash, ícone e cores do cliente',
                  icone: Icons.shopping_bag,
                  cor: Colors.blue,
                ),
                botaoSecaoEdicao(
                  largura: larguraBotao,
                  id: 'apks',
                  titulo: 'APKs',
                  subtitulo: 'Admin e app de compras',
                  icone: Icons.android,
                  cor: Colors.teal,
                ),
                botaoSecaoEdicao(
                  largura: larguraBotao,
                  id: 'conexoes',
                  titulo: 'Conexões',
                  subtitulo: 'API, Supabase e produtos',
                  icone: Icons.cloud_sync,
                  cor: Colors.indigo,
                ),
                botaoSecaoEdicao(
                  largura: larguraBotao,
                  id: 'imagens',
                  titulo: 'API de imagens',
                  subtitulo: 'SerpAPI e busca automática',
                  icone: Icons.image_search,
                  cor: Colors.orange,
                ),
                botaoSecaoEdicao(
                  largura: larguraBotao,
                  id: 'estoque',
                  titulo: 'Estoque',
                  subtitulo: 'Token de update pela API',
                  icone: Icons.inventory_2,
                  cor: Colors.green,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget cardSecaoFormulario({
    required String titulo,
    required String subtitulo,
    required IconData icone,
    required Color cor,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icone, color: cor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget areaDadosBasicos() {
    return cardSecaoFormulario(
      titulo: 'Dados da loja',
      subtitulo: 'Informações principais usadas na Central e nos apps.',
      icone: Icons.store_mall_directory,
      cor: vermelho,
      children: [
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            value: ativo,
            activeThumbColor: vermelho,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Mercado ativo',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              ativo
                  ? 'Este mercado aparece para seleção e acesso.'
                  : 'Este mercado fica oculto da seleção normal.',
            ),
            onChanged: salvando
                ? null
                : (valor) {
                    setState(() {
                      ativo = valor;
                    });
                  },
          ),
        ),
        const SizedBox(height: 14),
        campoTexto(
          controller: nomeController,
          label: 'Nome do mercado',
          icon: Icons.store,
          obrigatorio: true,
        ),
        const SizedBox(height: 14),
        campoTexto(
          controller: codigoController,
          label: 'Código interno',
          icon: Icons.tag,
          hint: 'Ex: sao_mateus',
          obrigatorio: true,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: campoTexto(
                controller: cidadeController,
                label: 'Cidade',
                icon: Icons.location_city,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: campoTexto(
                controller: estadoController,
                label: 'UF',
                icon: Icons.map,
                hint: 'BA',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget areaVisualAdmin() {
    return Column(
      children: [
        areaLogo(),
        const SizedBox(height: 14),
        areaSplashLogo(),
        const SizedBox(height: 14),
        areaIconeApp(),
        const SizedBox(height: 14),
        areaDebugCores(),
        const SizedBox(height: 14),
        areaCoresAdmin(),
      ],
    );
  }

  Widget areaVisualMercado() {
    return Column(
      children: [
        areaLogoMercado(),
        const SizedBox(height: 14),
        areaSplashLogoMercado(),
        const SizedBox(height: 14),
        areaIconeAppMercado(),
        const SizedBox(height: 14),
        areaCoresMercado(),
      ],
    );
  }

  Widget areaConexoesLoja() {
    return cardSecaoFormulario(
      titulo: 'Conexões da loja',
      subtitulo:
          'Dados técnicos usados para comunicar com a API e Supabase da loja.',
      icone: Icons.cloud_sync,
      cor: Colors.indigo,
      children: [
        DropdownButtonFormField<String>(
          value: fonteProdutos,
          decoration: InputDecoration(
            labelText: 'Fonte dos produtos',
            prefixIcon: const Icon(Icons.inventory_2_outlined),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          items: const [
            DropdownMenuItem(
              value: 'API',
              child: Text('API do mercado / SQL Server'),
            ),
            DropdownMenuItem(
              value: 'BANCO_LOJA',
              child: Text('Banco da loja / Supabase'),
            ),
          ],
          onChanged: salvando || carregandoConexao
              ? null
              : (valor) {
                  if (valor == null) return;

                  setState(() {
                    fonteProdutos = valor;
                  });
                },
        ),
        const SizedBox(height: 10),
        Text(
          fonteProdutos == 'API'
              ? 'Os produtos serão buscados na API Node/SQL Server configurada para a loja.'
              : 'Os produtos serão buscados na tabela produtos_app da base Supabase compartilhada.',
          style: const TextStyle(color: Colors.black54, fontSize: 13),
        ),
        if (fonteProdutos == 'API') ...[
          const SizedBox(height: 14),
          campoTexto(
            controller: apiBaseUrlController,
            label: 'API base URL',
            icon: Icons.link,
            obrigatorio: true,
          ),
        ],
        const SizedBox(height: 14),
        campoTexto(
          controller: supabaseUrlController,
          label: 'Supabase URL',
          icon: Icons.cloud,
          obrigatorio: true,
        ),
        const SizedBox(height: 14),
        campoTexto(
          controller: supabaseAnonKeyController,
          label: 'Supabase anon key',
          icon: Icons.vpn_key,
          maxLines: 3,
          obrigatorio: true,
        ),
        const SizedBox(height: 14),
        campoTexto(
          controller: supabaseServiceRoleKeyController,
          label: 'Nova service role key',
          icon: Icons.admin_panel_settings,
          hint: 'Deixe vazio para manter a atual',
          maxLines: 3,
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
          ),
          child: const Text(
            'A service role key atual não é exibida por segurança. '
            'Preencha esse campo apenas se quiser trocar por uma nova.',
            style: TextStyle(color: Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget areaApiImagensProdutos() {
    return cardSecaoFormulario(
      titulo: 'API de imagens dos produtos',
      subtitulo: 'Configuração da busca automática de imagens pela SerpAPI.',
      icone: Icons.image_search,
      cor: Colors.orange,
      children: [
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            value: usarApiImagens,
            activeThumbColor: vermelho,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Usar busca automática de imagens',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              usarApiImagens
                  ? 'O sistema poderá buscar imagens pela SerpAPI quando não encontrar no Supabase.'
                  : 'O sistema não usará busca automática de imagens.',
            ),
            onChanged: salvando || carregandoConexao
                ? null
                : (valor) {
                    setState(() {
                      usarApiImagens = valor;
                    });
                  },
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: !usarApiImagens
                ? Colors.grey.withValues(alpha: 0.10)
                : serpapiConfigurada
                ? Colors.green.withValues(alpha: 0.10)
                : Colors.orange.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: !usarApiImagens
                  ? Colors.grey.withValues(alpha: 0.25)
                  : serpapiConfigurada
                  ? Colors.green.withValues(alpha: 0.25)
                  : Colors.orange.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              Icon(
                !usarApiImagens
                    ? Icons.block
                    : serpapiConfigurada
                    ? Icons.check_circle
                    : Icons.warning_amber,
                color: !usarApiImagens
                    ? Colors.black45
                    : serpapiConfigurada
                    ? Colors.green
                    : Colors.orange,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  carregandoConexao
                      ? 'Verificando SerpAPI Key...'
                      : !usarApiImagens
                      ? 'Busca automática de imagens desativada para este mercado.'
                      : serpapiConfigurada
                      ? 'SerpAPI Key já configurada para este mercado.'
                      : 'SerpAPI Key ainda não configurada para este mercado.',
                  style: const TextStyle(color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        campoTexto(
          controller: serpapiKeyController,
          label: 'Nova SerpAPI Key',
          icon: Icons.image_search,
          hint: 'Deixe vazio para manter a atual',
          maxLines: 3,
        ),
      ],
    );
  }

  Widget areaApks() {
    return Column(
      children: [
        cardSecaoFormulario(
          titulo: 'Configuração dos APKs',
          subtitulo:
              'Separe o APK Admin do APK Mercado/Cliente e mantenha packages únicos.',
          icone: Icons.android,
          cor: Colors.teal,
          children: [areaApkPersonalizado()],
        ),
      ],
    );
  }

  Widget cabecalhoSecaoInterna() {
    final cor = corSecaoAtual();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(iconeSecaoAtual(), color: cor, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tituloSecaoAtual(),
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtituloSecaoAtual(),
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget conteudoSecaoSelecionada() {
    switch (secaoEdicaoSelecionada) {
      case 'visual_admin':
        return areaVisualAdmin();
      case 'visual_mercado':
        return areaVisualMercado();
      case 'apks':
        return areaApks();
      case 'conexoes':
        return areaConexoesLoja();
      case 'imagens':
        return areaApiImagensProdutos();
      case 'estoque':
        return areaTokenUpdateEstoque();
      case 'dados':
      default:
        return areaDadosBasicos();
    }
  }

  Widget botaoSalvarAlteracoes() {
    return SizedBox(
      height: 54,
      child: ElevatedButton.icon(
        onPressed: salvando || carregandoConexao ? null : salvar,
        icon: salvando
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.save),
        label: const Text('Salvar alterações'),
        style: ElevatedButton.styleFrom(
          backgroundColor: vermelho,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nomeMercado = widget.mercado['nome']?.toString() ?? 'Mercado';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(tituloSecaoAtual()),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(18),
            children: [
              resumoMercadoEdicao(nomeMercado),
              const SizedBox(height: 18),
              avisoCarregandoConexao(),
              cabecalhoSecaoInterna(),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: KeyedSubtree(
                  key: ValueKey(secaoEdicaoSelecionada),
                  child: conteudoSecaoSelecionada(),
                ),
              ),
              const SizedBox(height: 22),
              botaoSalvarAlteracoes(),
              const SizedBox(height: 26),
            ],
          ),
          if (salvando)
            Container(
              color: Colors.black.withValues(alpha: 0.08),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

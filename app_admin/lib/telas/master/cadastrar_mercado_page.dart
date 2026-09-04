import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/central_service.dart';

class CadastrarMercadoPage extends StatefulWidget {
  const CadastrarMercadoPage({super.key});

  @override
  State<CadastrarMercadoPage> createState() => _CadastrarMercadoPageState();
}

class _CadastrarMercadoPageState extends State<CadastrarMercadoPage> {
  final service = CentralService();
  final ImagePicker picker = ImagePicker();

  final nomeController = TextEditingController();
  final codigoController = TextEditingController();
  final cidadeController = TextEditingController();
  final estadoController = TextEditingController();

  final apiBaseUrlController = TextEditingController();
  final supabaseUrlController = TextEditingController();
  final supabaseAnonKeyController = TextEditingController();
  final supabaseServiceRoleKeyController = TextEditingController();

  final serpapiKeyController = TextEditingController();

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

  bool carregando = false;
  bool usarApiImagens = true;
  String fonteProdutos = 'API';
  bool gerarApkAdmin = false;
  bool gerarApkMercado = false;
  bool alterarPrecoConsultaAtivo = false;

  File? logoSelecionada;
  File? mercadoLogoSelecionada;
  File? splashLogoSelecionada;
  File? mercadoSplashLogoSelecionada;
  File? iconeAppSelecionado;
  File? mercadoIconeAppSelecionado;

  static const Color vermelho = Color(0xFFE30613);

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
    super.dispose();
  }

  String gerarCodigo(String texto) {
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
    return gerarCodigo(texto).replaceAll('_', '');
  }

  void preencherPadraoApkAdmin() {
    final nome = nomeController.text.trim();
    final codigo = codigoController.text.trim().isEmpty
        ? gerarCodigo(nome)
        : gerarCodigo(codigoController.text.trim());
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
    final codigo = codigoController.text.trim().isEmpty
        ? gerarCodigo(nome)
        : gerarCodigo(codigoController.text.trim());
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

  bool packageValido(String package) {
    return RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$').hasMatch(package);
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

  Widget campoCor({
    required TextEditingController controller,
    required String label,
    required String hint,
    required Color fallback,
  }) {
    final cor = corHexParaColor(controller.text, fallback);

    return TextField(
      controller: controller,
      enabled: !carregando,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: cor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
            ),
          ),
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  String extrairMercadoId(Map<String, dynamic> resposta) {
    final mercado = resposta['mercado'];

    if (mercado is Map && mercado['id'] != null) {
      return mercado['id'].toString();
    }

    if (mercado is Map && mercado['mercado_id'] != null) {
      return mercado['mercado_id'].toString();
    }

    if (resposta['id'] != null) {
      return resposta['id'].toString();
    }

    if (resposta['mercado_id'] != null) {
      return resposta['mercado_id'].toString();
    }

    return '';
  }

  Future<File?> selecionarImagem({
    required String tipo,
    required int maxWidth,
  }) async {
    if (carregando) return null;

    try {
      final imagem = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: maxWidth.toDouble(),
      );

      if (imagem == null) {
        return null;
      }

      return File(imagem.path);
    } catch (e) {
      if (!mounted) return null;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao selecionar $tipo: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );

      return null;
    }
  }

  Future<void> selecionarLogo() async {
    final imagem = await selecionarImagem(tipo: 'logo interno', maxWidth: 1200);

    if (imagem == null) return;

    setState(() {
      logoSelecionada = imagem;
    });
  }

  Future<void> selecionarLogoMercado() async {
    final imagem = await selecionarImagem(
      tipo: 'logo do app Mercado',
      maxWidth: 1200,
    );

    if (imagem == null) return;

    setState(() {
      mercadoLogoSelecionada = imagem;
    });
  }

  Future<void> selecionarSplashLogo() async {
    final imagem = await selecionarImagem(
      tipo: 'splash de abertura',
      maxWidth: 1024,
    );

    if (imagem == null) return;

    setState(() {
      splashLogoSelecionada = imagem;
    });
  }

  Future<void> selecionarSplashLogoMercado() async {
    final imagem = await selecionarImagem(
      tipo: 'splash do app Mercado',
      maxWidth: 1024,
    );

    if (imagem == null) return;

    setState(() {
      mercadoSplashLogoSelecionada = imagem;
    });
  }

  Future<void> selecionarIconeApp() async {
    final imagem = await selecionarImagem(tipo: 'ícone do app', maxWidth: 1024);

    if (imagem == null) return;

    setState(() {
      iconeAppSelecionado = imagem;
    });
  }

  Future<void> selecionarIconeAppMercado() async {
    final imagem = await selecionarImagem(
      tipo: 'ícone do app Mercado',
      maxWidth: 1024,
    );

    if (imagem == null) return;

    setState(() {
      mercadoIconeAppSelecionado = imagem;
    });
  }

  void removerLogo() {
    if (carregando) return;

    setState(() {
      logoSelecionada = null;
    });
  }

  void removerLogoMercado() {
    if (carregando) return;

    setState(() {
      mercadoLogoSelecionada = null;
    });
  }

  void removerSplashLogo() {
    if (carregando) return;

    setState(() {
      splashLogoSelecionada = null;
    });
  }

  void removerSplashLogoMercado() {
    if (carregando) return;

    setState(() {
      mercadoSplashLogoSelecionada = null;
    });
  }

  void removerIconeApp() {
    if (carregando) return;

    setState(() {
      iconeAppSelecionado = null;
    });
  }

  void removerIconeAppMercado() {
    if (carregando) return;

    setState(() {
      mercadoIconeAppSelecionado = null;
    });
  }

  Future<void> cadastrar() async {
    final nome = nomeController.text.trim();
    final codigoDigitado = codigoController.text.trim();
    final cidade = cidadeController.text.trim();
    final estado = estadoController.text.trim().toUpperCase();

    final apiBaseUrl = apiBaseUrlController.text.trim();
    final supabaseUrl = supabaseUrlController.text.trim();
    final supabaseAnonKey = supabaseAnonKeyController.text.trim();
    final supabaseServiceRoleKey = supabaseServiceRoleKeyController.text.trim();

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
    final adminAppBuildCodigo = gerarCodigo(
      adminAppBuildCodigoController.text.trim(),
    );

    final mercadoAppNome = mercadoAppNomeController.text.trim();
    final mercadoAppPackage = mercadoAppPackageController.text.trim();
    final mercadoAppBuildCodigo = gerarCodigo(
      mercadoAppBuildCodigoController.text.trim(),
    );

    if (nome.isEmpty ||
        (fonteProdutos == 'API' && apiBaseUrl.isEmpty) ||
        supabaseUrl.isEmpty ||
        supabaseAnonKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            fonteProdutos == 'API'
                ? 'Informe nome, API base URL, Supabase URL e Supabase anon key'
                : 'Informe nome, Supabase URL e Supabase anon key',
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

    final codigo = codigoDigitado.isEmpty ? gerarCodigo(nome) : codigoDigitado;

    FocusScope.of(context).unfocus();

    setState(() {
      carregando = true;
    });

    try {
      final mercadoCriado = await service.cadastrarMercado(
        nome: nome,
        codigo: codigo,
        cidade: cidade,
        estado: estado,
        apiBaseUrl: apiBaseUrl,
        supabaseUrl: supabaseUrl,
        supabaseAnonKey: supabaseAnonKey,
        supabaseServiceRoleKey: supabaseServiceRoleKey.isEmpty
            ? null
            : supabaseServiceRoleKey,
        usarApiImagens: usarApiImagens,
        fonteProdutos: fonteProdutos,
        serpapiKey: serpapiKey.isEmpty ? null : serpapiKey,
        adminCorPrimaria: adminCorPrimaria,
        adminCorSecundaria: adminCorSecundaria,
        adminCorFundo: adminCorFundo,
        clienteCorPrimaria: clienteCorPrimaria,
        clienteCorSecundaria: clienteCorSecundaria,
        clienteCorFundo: clienteCorFundo,
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
      );

      final mercadoId = extrairMercadoId(mercadoCriado);

      if (logoSelecionada != null ||
          mercadoLogoSelecionada != null ||
          splashLogoSelecionada != null ||
          mercadoSplashLogoSelecionada != null ||
          iconeAppSelecionado != null ||
          mercadoIconeAppSelecionado != null ||
          gerarApkAdmin ||
          gerarApkMercado) {
        if (mercadoId.isEmpty) {
          throw Exception(
            'Mercado cadastrado, mas não foi possível identificar o ID para enviar as imagens.',
          );
        }
      }

      if (logoSelecionada != null) {
        await service.uploadLogoLoginMercado(
          mercadoId: mercadoId,
          logoFile: logoSelecionada!,
        );
      } else if (mercadoLogoSelecionada != null) {
        await service.uploadLogoLoginMercado(
          mercadoId: mercadoId,
          logoFile: mercadoLogoSelecionada!,
        );
      }

      if (mercadoLogoSelecionada != null) {
        await service.uploadLogoMercado(
          mercadoId: mercadoId,
          logoFile: mercadoLogoSelecionada!,
        );
      } else if (logoSelecionada != null) {
        await service.uploadLogoMercado(
          mercadoId: mercadoId,
          logoFile: logoSelecionada!,
        );
      }

      if (splashLogoSelecionada != null) {
        await service.uploadSplashLogoMercado(
          mercadoId: mercadoId,
          splashFile: splashLogoSelecionada!,
        );
      }

      if (mercadoSplashLogoSelecionada != null) {
        await service.uploadSplashLogoMercadoCliente(
          mercadoId: mercadoId,
          splashFile: mercadoSplashLogoSelecionada!,
        );
      }

      if (iconeAppSelecionado != null) {
        await service.uploadIconeAppMercado(
          mercadoId: mercadoId,
          iconeFile: iconeAppSelecionado!,
        );
      }

      if (mercadoIconeAppSelecionado != null) {
        await service.uploadIconeAppMercadoCliente(
          mercadoId: mercadoId,
          iconeFile: mercadoIconeAppSelecionado!,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mercado cadastrado com sucesso'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao cadastrar mercado: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );

      setState(() {
        carregando = false;
      });
    }
  }

  Future<void> salvarConfiguracaoApks({
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
    if (mercadoId.trim().isEmpty) {
      return;
    }

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

          // Mantém compatibilidade com os scripts antigos que ainda leem estes campos.
          'apk_personalizado': gerarMercado,
          'app_nome': gerarMercado ? mercadoNome : null,
          'app_package': gerarMercado ? mercadoPackage : null,
          'app_build_codigo': gerarMercado ? mercadoBuildCodigo : null,
        })
        .eq('id', mercadoId);
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
      enabled: !carregando,
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

  Widget aviso({
    required Color cor,
    required IconData icone,
    required String texto,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icone, color: cor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texto, style: const TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget cardImagem({
    required String titulo,
    required String descricao,
    required File? arquivo,
    required IconData iconeVazio,
    required VoidCallback selecionar,
    required VoidCallback remover,
    required String textoSelecionado,
    required BoxFit fitImagem,
    bool formatoIcone = false,
  }) {
    final preview = Container(
      width: formatoIcone ? 92 : 130,
      height: formatoIcone ? 92 : 92,
      decoration: BoxDecoration(
        color: vermelho.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(formatoIcone ? 24 : 18),
        border: Border.all(color: vermelho.withValues(alpha: 0.18)),
      ),
      child: arquivo == null
          ? Icon(iconeVazio, color: vermelho, size: formatoIcone ? 42 : 44)
          : ClipRRect(
              borderRadius: BorderRadius.circular(formatoIcone ? 22 : 16),
              child: Image.file(
                arquivo,
                width: formatoIcone ? 92 : 130,
                height: formatoIcone ? 92 : 92,
                fit: fitImagem,
              ),
            ),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          preview,
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
                  arquivo == null ? descricao : textoSelecionado,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: carregando ? null : selecionar,
                      icon: const Icon(Icons.photo_library),
                      label: Text(arquivo == null ? 'Selecionar' : 'Trocar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: vermelho,
                        side: const BorderSide(color: vermelho),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    if (arquivo != null)
                      OutlinedButton.icon(
                        onPressed: carregando ? null : remover,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remover'),
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

  Widget areaFonteProdutos() {
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
            'Fonte dos produtos',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Define de onde o app Mercado/Cliente vai carregar os produtos desta loja.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: fonteProdutos,
            decoration: InputDecoration(
              labelText: 'Fonte dos produtos',
              prefixIcon: const Icon(Icons.inventory_2_outlined),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
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
            onChanged: carregando
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
            'Essas cores serão usadas dinamicamente na tela de login do Admin.',
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
            'Essas cores serão usadas dinamicamente no app de compras do cliente.',
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

  Widget areaImagens() {
    return Column(
      children: [
        cardImagem(
          titulo: 'Logo do app Admin/login',
          descricao:
              'Imagem dinâmica usada no app Admin e na tela de login. Fica salva no banco em logo_login_url.',
          arquivo: logoSelecionada,
          iconeVazio: Icons.store,
          selecionar: selecionarLogo,
          remover: removerLogo,
          textoSelecionado: 'Logo do app Admin selecionada para envio',
          fitImagem: BoxFit.contain,
          formatoIcone: false,
        ),
        const SizedBox(height: 14),
        cardImagem(
          titulo: 'Logo do app Mercado/Cliente',
          descricao:
              'Imagem dinâmica usada no app Mercado para os clientes. Fica salva no banco em logo_url.',
          arquivo: mercadoLogoSelecionada,
          iconeVazio: Icons.shopping_basket,
          selecionar: selecionarLogoMercado,
          remover: removerLogoMercado,
          textoSelecionado: 'Logo do app Mercado selecionada para envio',
          fitImagem: BoxFit.contain,
          formatoIcone: false,
        ),
        const SizedBox(height: 14),
        cardImagem(
          titulo: 'Splash fixo ao abrir o app',
          descricao:
              'Imagem usada no primeiro splash do Android. Fica salva no banco em splash_logo_url e o script aplica no APK.',
          arquivo: splashLogoSelecionada,
          iconeVazio: Icons.screenshot_monitor,
          selecionar: selecionarSplashLogo,
          remover: removerSplashLogo,
          textoSelecionado: 'Splash de abertura selecionado para envio',
          fitImagem: BoxFit.contain,
          formatoIcone: true,
        ),
        const SizedBox(height: 14),
        cardImagem(
          titulo: 'Splash do app Mercado/Cliente',
          descricao:
              'Imagem usada no splash do APK Mercado/Cliente. Fica salva no banco em mercado_splash_logo_url.',
          arquivo: mercadoSplashLogoSelecionada,
          iconeVazio: Icons.storefront,
          selecionar: selecionarSplashLogoMercado,
          remover: removerSplashLogoMercado,
          textoSelecionado: 'Splash do app Mercado selecionado para envio',
          fitImagem: BoxFit.contain,
          formatoIcone: true,
        ),
        const SizedBox(height: 14),
        cardImagem(
          titulo: 'Ícone do app Admin Android',
          descricao:
              'Imagem usada como ícone do APK Admin na tela inicial do celular. Fica salva no banco em app_icone_url.',
          arquivo: iconeAppSelecionado,
          iconeVazio: Icons.admin_panel_settings,
          selecionar: selecionarIconeApp,
          remover: removerIconeApp,
          textoSelecionado: 'Ícone do app Admin selecionado para envio',
          fitImagem: BoxFit.cover,
          formatoIcone: true,
        ),
        const SizedBox(height: 14),
        cardImagem(
          titulo: 'Ícone do app Mercado Android',
          descricao:
              'Imagem usada como ícone do APK Mercado/Cliente. Fica salva no banco em mercado_app_icone_url.',
          arquivo: mercadoIconeAppSelecionado,
          iconeVazio: Icons.shopping_bag,
          selecionar: selecionarIconeAppMercado,
          remover: removerIconeAppMercado,
          textoSelecionado: 'Ícone do app Mercado selecionado para envio',
          fitImagem: BoxFit.cover,
          formatoIcone: true,
        ),
      ],
    );
  }

  Widget cardConfiguracaoApkCadastro({
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
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ativo
              ? Colors.blue.withValues(alpha: 0.25)
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
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
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
                onChanged: carregando ? null : onChanged,
              ),
            ],
          ),
          if (ativo) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: carregando ? null : preencherPadrao,
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

  Widget areaConfiguracaoApks() {
    return Column(
      children: [
        aviso(
          cor: Colors.blue,
          icone: Icons.apps,
          texto:
              'Configure packages diferentes para instalar Admin e Mercado no mesmo celular sem sobrescrever.',
        ),
        const SizedBox(height: 14),
        cardConfiguracaoApkCadastro(
          titulo: 'APK Admin',
          descricaoAtivo:
              'O script poderá gerar um APK Admin próprio para esta loja.',
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
        ),
        const SizedBox(height: 14),
        cardConfiguracaoApkCadastro(
          titulo: 'APK Mercado / Cliente',
          descricaoAtivo:
              'O script poderá gerar o app de compras próprio para esta loja.',
          descricaoInativo: 'Não gerar APK Mercado para esta loja.',
          ativo: gerarApkMercado,
          onChanged: (valor) {
            setState(() {
              gerarApkMercado = valor;
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
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Cadastrar mercado'),
        backgroundColor: vermelho,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Novo cliente / mercado',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Cadastre a loja, as imagens e as conexões que o sistema usará para acessar os dados dela.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 22),

                areaImagens(),

                const SizedBox(height: 22),

                areaCoresAdmin(),

                const SizedBox(height: 14),

                areaCoresMercado(),

                const SizedBox(height: 22),

                campoTexto(
                  controller: nomeController,
                  label: 'Nome do mercado',
                  icon: Icons.store,
                  hint: 'Ex: Mercado São Mateus',
                  obrigatorio: true,
                ),

                const SizedBox(height: 14),

                campoTexto(
                  controller: codigoController,
                  label: 'Código interno',
                  icon: Icons.tag,
                  hint: 'Ex: sao_mateus',
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
                        hint: 'Ex: Bom Jesus da Serra',
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

                const SizedBox(height: 24),

                const Text(
                  'Configuração dos APKs',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),

                const SizedBox(height: 12),

                areaConfiguracaoApks(),

                const SizedBox(height: 24),

                const Text(
                  'Conexões da loja',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),

                const SizedBox(height: 12),

                areaFonteProdutos(),

                if (fonteProdutos == 'API') ...[
                  const SizedBox(height: 14),
                  campoTexto(
                    controller: apiBaseUrlController,
                    label: 'API base URL',
                    icon: Icons.link,
                    hint: 'Ex: http://192.141.122.71:34000',
                    obrigatorio: true,
                  ),
                ],

                const SizedBox(height: 14),

                campoTexto(
                  controller: supabaseUrlController,
                  label: 'Supabase URL da loja',
                  icon: Icons.cloud,
                  hint: 'Ex: https://xxxx.supabase.co',
                  obrigatorio: true,
                ),

                const SizedBox(height: 14),

                campoTexto(
                  controller: supabaseAnonKeyController,
                  label: 'Supabase anon key da loja',
                  icon: Icons.vpn_key,
                  hint: 'Cole a anon key da loja',
                  maxLines: 3,
                  obrigatorio: true,
                ),

                const SizedBox(height: 14),

                campoTexto(
                  controller: supabaseServiceRoleKeyController,
                  label: 'Service role key da loja',
                  icon: Icons.admin_panel_settings,
                  hint:
                      'Opcional. Use somente se precisar em funções administrativas',
                  maxLines: 3,
                ),

                const SizedBox(height: 24),

                const Text(
                  'API de imagens dos produtos',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),

                const SizedBox(height: 8),

                SwitchListTile(
                  value: usarApiImagens,
                  activeThumbColor: vermelho,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text(
                    'Usar busca automática de imagens',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    usarApiImagens
                        ? 'Quando o produto não tiver imagem no Supabase, o sistema poderá buscar pela SerpAPI.'
                        : 'O sistema não usará busca automática de imagens.',
                  ),
                  onChanged: carregando
                      ? null
                      : (valor) {
                          setState(() {
                            usarApiImagens = valor;
                          });
                        },
                ),

                const SizedBox(height: 8),

                campoTexto(
                  controller: serpapiKeyController,
                  label: 'SerpAPI Key',
                  icon: Icons.image_search,
                  hint:
                      'Cole a chave da SerpAPI. Pode deixar vazio e cadastrar depois.',
                  maxLines: 3,
                ),

                const SizedBox(height: 12),

                SwitchListTile(
                  value: alterarPrecoConsultaAtivo,
                  activeThumbColor: vermelho,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text(
                    'Liberar alterar preco na consulta',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    alterarPrecoConsultaAtivo
                        ? 'A tela de imagem do produto exibira o botao Alterar preco.'
                        : 'O botao Alterar preco ficara oculto para esta loja.',
                  ),
                  onChanged: carregando
                      ? null
                      : (valor) {
                          setState(() {
                            alterarPrecoConsultaAtivo = valor;
                          });
                        },
                ),

                const SizedBox(height: 12),

                aviso(
                  cor: Colors.blue,
                  icone: Icons.info_outline,
                  texto:
                      'A chave SerpAPI ficará salva na base central de forma privada. Ela não será exibida no app depois do cadastro.',
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: carregando ? null : cadastrar,
                    icon: carregando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Cadastrar mercado'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: vermelho,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                aviso(
                  cor: Colors.orange,
                  icone: Icons.warning_amber,
                  texto:
                      'Atenção: essas informações ficam salvas na base central. O app usa esses dados para conectar na loja selecionada.',
                ),
              ],
            ),
          ),
          if (carregando)
            Container(
              color: Colors.black.withValues(alpha: 0.08),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

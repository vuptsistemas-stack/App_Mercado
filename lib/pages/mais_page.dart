import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_tema_service.dart';
import '../services/sessao_mercado_cliente.dart' as sessao;
import 'conta_page.dart';
import 'login_page.dart';

class MaisPage extends StatelessWidget {
  final VoidCallback? onVoltarInicio;

  const MaisPage({super.key, this.onVoltarInicio});

  static const String versaoApp = '1.0.0';
  static const String desenvolvedorPadrao = 'Mercado Digital Tecnologia';

  Map<String, dynamic> get dadosLoja {
    return sessao.SessaoMercadoCliente.dadosOriginais;
  }

  Map<String, dynamic> get lojaConfiguracoes {
    final configuracoes = dadosLoja['loja_configuracoes'];

    if (configuracoes is Map) {
      return Map<String, dynamic>.from(configuracoes);
    }

    return {};
  }

  String texto(dynamic valor) {
    final convertido = valor?.toString().trim() ?? '';
    return convertido.toLowerCase() == 'null' ? '' : convertido;
  }

  String primeiroTexto(List<dynamic> valores, {String fallback = ''}) {
    for (final valor in valores) {
      final convertido = texto(valor);
      if (convertido.isNotEmpty) return convertido;
    }

    return fallback;
  }

  List<String> meiosPagamentoLoja() {
    final valor = lojaConfiguracoes['meios_pagamento'];
    Iterable<dynamic> itens = const [];

    if (valor is List) {
      itens = valor;
    } else if (valor is String && valor.trim().isNotEmpty) {
      itens = valor.split(',');
    }

    final nomes = <String>[];
    final chaves = <String>{};

    for (final item in itens) {
      final nome = item.toString().trim();
      final chave = nome.toLowerCase();

      if (nome.isEmpty || chaves.contains(chave)) continue;

      nomes.add(nome);
      chaves.add(chave);
    }

    return nomes.isEmpty ? ['Pix', 'Dinheiro', 'Cartão na entrega'] : nomes;
  }

  String nomeLoja() {
    return primeiroTexto([
      lojaConfiguracoes['nome_loja'],
      sessao.SessaoMercadoCliente.mercadoNome,
      dadosLoja['mercado_nome'],
      dadosLoja['nome'],
      dadosLoja['nome_loja'],
    ], fallback: 'Mercado Online');
  }

  String whatsappLoja() {
    return primeiroTexto([
      lojaConfiguracoes['whatsapp'],
      lojaConfiguracoes['telefone_whatsapp'],
      lojaConfiguracoes['telefone_loja'],
      lojaConfiguracoes['telefone'],
      lojaConfiguracoes['celular'],
      sessao.SessaoMercadoCliente.whatsapp,
      dadosLoja['whatsapp'],
      dadosLoja['telefone_whatsapp'],
      dadosLoja['telefone_loja'],
      dadosLoja['telefone'],
      dadosLoja['celular'],
    ]);
  }

  String instagramLoja() {
    return primeiroTexto([
      lojaConfiguracoes['instagram'],
      lojaConfiguracoes['instagram_url'],
      dadosLoja['instagram'],
      dadosLoja['instagram_url'],
    ]);
  }

  String facebookLoja() {
    return primeiroTexto([
      lojaConfiguracoes['facebook'],
      lojaConfiguracoes['facebook_url'],
      dadosLoja['facebook'],
      dadosLoja['facebook_url'],
    ]);
  }

  bool urlHttpValida(String valor) {
    final uri = Uri.tryParse(valor.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  Future<void> abrirUrlExterna(
    BuildContext context, {
    required String url,
    required String nome,
  }) async {
    if (!urlHttpValida(url)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$nome da loja não informado.')));
      return;
    }

    final abriu = await launchUrl(
      Uri.parse(url.trim()),
      mode: LaunchMode.externalApplication,
    );

    if (!abriu && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Não foi possível abrir $nome.')));
    }
  }

  String emailLoja() {
    return primeiroTexto([
      lojaConfiguracoes['email_contato'],
      lojaConfiguracoes['email'],
      lojaConfiguracoes['loja_email'],
      lojaConfiguracoes['suporte_email'],
      dadosLoja['email_contato'],
      dadosLoja['email'],
      dadosLoja['loja_email'],
      dadosLoja['suporte_email'],
    ], fallback: 'Atendimento pelo WhatsApp da loja');
  }

  String enderecoLoja() {
    final enderecoFormatado = primeiroTexto([
      lojaConfiguracoes['endereco_loja_formatado'],
      dadosLoja['endereco_loja_formatado'],
    ]);

    if (enderecoFormatado.isNotEmpty) {
      return enderecoFormatado.replaceAll(' | ', '\n');
    }

    final endereco = primeiroTexto([
      lojaConfiguracoes['endereco_loja'],
      lojaConfiguracoes['loja_endereco'],
      lojaConfiguracoes['endereco'],
      lojaConfiguracoes['rua'],
      dadosLoja['endereco_loja'],
      dadosLoja['loja_endereco'],
      dadosLoja['endereco'],
      dadosLoja['rua'],
    ]);
    final numero = primeiroTexto([
      lojaConfiguracoes['numero_loja'],
      lojaConfiguracoes['loja_numero'],
      lojaConfiguracoes['numero'],
      dadosLoja['numero_loja'],
      dadosLoja['loja_numero'],
      dadosLoja['numero'],
    ]);
    final bairro = primeiroTexto([
      lojaConfiguracoes['bairro_loja'],
      lojaConfiguracoes['loja_bairro'],
      lojaConfiguracoes['bairro'],
      dadosLoja['bairro_loja'],
      dadosLoja['loja_bairro'],
      dadosLoja['bairro'],
    ]);
    final cidade = primeiroTexto([
      lojaConfiguracoes['cidade_loja'],
      lojaConfiguracoes['loja_cidade'],
      lojaConfiguracoes['cidade'],
      dadosLoja['cidade_loja'],
      dadosLoja['loja_cidade'],
      dadosLoja['cidade'],
    ]);

    final linha1 = [
      endereco,
      numero,
    ].where((item) => item.isNotEmpty).join(', ');
    final linha2 = [
      bairro,
      cidade,
    ].where((item) => item.isNotEmpty).join(' - ');
    final completo = [
      linha1,
      linha2,
    ].where((item) => item.isNotEmpty).join('\n');

    return completo.isEmpty ? 'Endereço da loja não informado' : completo;
  }

  String horarioLoja() {
    return primeiroTexto([
      lojaConfiguracoes['horario_funcionamento'],
      lojaConfiguracoes['funcionamento'],
      lojaConfiguracoes['horarios'],
      lojaConfiguracoes['horario_atendimento'],
      lojaConfiguracoes['horario_retirada'],
      dadosLoja['horario_funcionamento'],
      dadosLoja['funcionamento'],
      dadosLoja['horarios'],
    ], fallback: 'Consulte a disponibilidade no momento do pedido.');
  }

  String desenvolvedor() {
    return primeiroTexto([
      lojaConfiguracoes['empresa_desenvolvedora'],
      lojaConfiguracoes['desenvolvedor'],
      lojaConfiguracoes['app_desenvolvedor'],
      dadosLoja['empresa_desenvolvedora'],
      dadosLoja['desenvolvedor'],
      dadosLoja['app_desenvolvedor'],
    ], fallback: desenvolvedorPadrao);
  }

  String versao() {
    return primeiroTexto([
      lojaConfiguracoes['app_versao'],
      lojaConfiguracoes['versao_app'],
      dadosLoja['app_versao'],
      dadosLoja['versao_app'],
    ], fallback: versaoApp);
  }

  String whatsappLojaNumeros() {
    var digitos = whatsappLoja().replaceAll(RegExp(r'[^0-9]'), '');

    if (digitos.isNotEmpty &&
        !digitos.startsWith('55') &&
        (digitos.length == 10 || digitos.length == 11)) {
      digitos = '55$digitos';
    }

    return digitos;
  }

  String telefoneFormatado() {
    final digitos = whatsappLojaNumeros();

    if (digitos.length == 13 && digitos.startsWith('55')) {
      final ddd = digitos.substring(2, 4);
      final parte1 = digitos.substring(4, 9);
      final parte2 = digitos.substring(9);
      return '($ddd) $parte1-$parte2';
    }

    if (digitos.length == 12 && digitos.startsWith('55')) {
      final ddd = digitos.substring(2, 4);
      final parte1 = digitos.substring(4, 8);
      final parte2 = digitos.substring(8);
      return '($ddd) $parte1-$parte2';
    }

    if (digitos.length == 11) {
      final ddd = digitos.substring(0, 2);
      final parte1 = digitos.substring(2, 7);
      final parte2 = digitos.substring(7);
      return '($ddd) $parte1-$parte2';
    }

    return whatsappLoja().isEmpty ? 'WhatsApp não informado' : whatsappLoja();
  }

  Future<void> abrirWhatsApp(BuildContext context) async {
    final numero = whatsappLojaNumeros();

    if (numero.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp da loja não informado.')),
      );
      return;
    }

    final mensagem = Uri.encodeComponent(
      'Olá, preciso de atendimento pelo aplicativo ${nomeLoja()}.',
    );
    final uri = Uri.parse('https://wa.me/$numero?text=$mensagem');
    final abriu = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!abriu && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')),
      );
    }
  }

  Future<void> sair(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sair da conta?'),
          content: const Text(
            'Você precisará entrar novamente para fazer pedidos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTemaService.primaria,
                foregroundColor: Colors.white,
              ),
              child: const Text('Sair'),
            ),
          ],
        );
      },
    );

    if (confirmar != true || !context.mounted) return;

    await Supabase.instance.client.auth.signOut();

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void abrirConta(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (routeContext) =>
            ContaPage(onVoltar: () => Navigator.of(routeContext).pop()),
      ),
    );
  }

  void abrirDetalhe(
    BuildContext context, {
    required String titulo,
    required IconData icone,
    required List<MaisSecaoConteudo> secoes,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MaisDetalhePage(titulo: titulo, icone: icone, secoes: secoes),
      ),
    );
  }

  Widget cabecalho() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTemaService.primaria.withValues(alpha: 0.16),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTemaService.primaria.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTemaService.primaria.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.storefront_outlined,
              color: AppTemaService.primaria,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nomeLoja(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Conta, atendimento, políticas e informações do aplicativo',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget grupo({required String titulo, required List<Widget> children}) {
    return const SizedBox.shrink();
  }

  Widget itemMenu({
    required IconData icone,
    required String titulo,
    required String descricao,
    required VoidCallback onTap,
    Color? cor,
    String? detalhe,
    bool iconeWhatsapp = false,
  }) {
    final itemCor = cor ?? AppTemaService.primaria;
    final textoAuxiliar = detalhe ?? descricao;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: itemCor.withValues(alpha: 0.18), width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 7, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: itemCor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: iconeWhatsapp
                    ? iconeWhatsApp(itemCor)
                    : Icon(icone, color: itemCor, size: 19),
              ),
              const SizedBox(height: 5),
              Text(
                titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF1F2937),
                  fontSize: 10.5,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Text(
                    textoAuxiliar,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: detalhe == null ? Colors.black54 : itemCor,
                      fontSize: 8.6,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget iconeWhatsApp(Color cor) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(Icons.chat_bubble_rounded, color: cor, size: 22),
        const Padding(
          padding: EdgeInsets.only(bottom: 1),
          child: Icon(Icons.phone, color: Colors.white, size: 10),
        ),
      ],
    );
  }

  Widget gradeMenu(BuildContext context) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        mainAxisExtent: 90,
      ),
      children: [
        itemMenu(
          icone: Icons.person_outline,
          titulo: 'Minha conta',
          descricao: 'Dados pessoais',
          onTap: () => abrirConta(context),
        ),
        itemMenu(
          icone: Icons.location_on_outlined,
          titulo: 'Meus endereços',
          descricao: 'Entrega',
          onTap: () => abrirConta(context),
        ),
        itemMenu(
          icone: Icons.support_agent_outlined,
          titulo: 'Atendimento',
          descricao: telefoneFormatado(),
          detalhe: 'WhatsApp',
          onTap: () => abrirDetalhe(
            context,
            titulo: 'Atendimento',
            icone: Icons.support_agent_outlined,
            secoes: secoesAtendimento(),
          ),
        ),
        itemMenu(
          icone: Icons.chat_outlined,
          titulo: 'Chamar no WhatsApp',
          descricao: 'Falar com a loja',
          cor: Colors.green,
          iconeWhatsapp: true,
          onTap: () => abrirWhatsApp(context),
        ),
        if (instagramLoja().trim().isNotEmpty)
          itemMenu(
            icone: Icons.camera_alt_outlined,
            titulo: 'Instagram',
            descricao: 'Perfil da loja',
            cor: const Color(0xFFE1306C),
            onTap: () => abrirUrlExterna(
              context,
              url: instagramLoja(),
              nome: 'Instagram',
            ),
          ),
        if (facebookLoja().trim().isNotEmpty)
          itemMenu(
            icone: Icons.facebook,
            titulo: 'Facebook',
            descricao: 'Perfil da loja',
            cor: const Color(0xFF1877F2),
            onTap: () =>
                abrirUrlExterna(context, url: facebookLoja(), nome: 'Facebook'),
          ),
        itemMenu(
          icone: Icons.storefront_outlined,
          titulo: 'Sobre a loja',
          descricao: 'Dados da loja',
          onTap: () => abrirDetalhe(
            context,
            titulo: 'Sobre a loja',
            icone: Icons.storefront_outlined,
            secoes: secoesSobreLoja(),
          ),
        ),
        itemMenu(
          icone: Icons.payments_outlined,
          titulo: 'Pagamentos',
          descricao: 'Na entrega',
          onTap: () => abrirDetalhe(
            context,
            titulo: 'Pagamentos',
            icone: Icons.payments_outlined,
            secoes: secoesPagamento(),
          ),
        ),
        itemMenu(
          icone: Icons.local_shipping_outlined,
          titulo: 'Entrega e retirada',
          descricao: 'Pedido',
          onTap: () => abrirDetalhe(
            context,
            titulo: 'Entrega e retirada',
            icone: Icons.local_shipping_outlined,
            secoes: secoesEntregaRetirada(),
          ),
        ),
        itemMenu(
          icone: Icons.description_outlined,
          titulo: 'Termos de uso',
          descricao: 'Regras',
          onTap: () => abrirDetalhe(
            context,
            titulo: 'Termos de uso',
            icone: Icons.description_outlined,
            secoes: secoesTermosUso(),
          ),
        ),
        itemMenu(
          icone: Icons.privacy_tip_outlined,
          titulo: 'Privacidade',
          descricao: 'Dados',
          onTap: () => abrirDetalhe(
            context,
            titulo: 'Privacidade',
            icone: Icons.privacy_tip_outlined,
            secoes: secoesPrivacidade(),
          ),
        ),
        itemMenu(
          icone: Icons.info_outline,
          titulo: 'Sobre o app',
          descricao: versao(),
          onTap: () => abrirDetalhe(
            context,
            titulo: 'Sobre o app',
            icone: Icons.info_outline,
            secoes: secoesSobreApp(),
          ),
        ),
        itemMenu(
          icone: Icons.logout,
          titulo: 'Sair da conta',
          descricao: 'Encerrar',
          cor: const Color(0xFF8A4A4A),
          onTap: () => sair(context),
        ),
      ],
    );
  }

  List<MaisSecaoConteudo> secoesAtendimento() {
    return [
      MaisSecaoConteudo(
        titulo: 'Canais de atendimento',
        paragrafos: [
          'WhatsApp: ${telefoneFormatado()}',
          if (instagramLoja().trim().isNotEmpty)
            'Instagram: ${instagramLoja()}',
          if (facebookLoja().trim().isNotEmpty) 'Facebook: ${facebookLoja()}',
          'E-mail: ${emailLoja()}',
          'Use o atendimento para dúvidas sobre pedidos, prazos, produtos, valores, retirada ou entrega.',
        ],
      ),
      const MaisSecaoConteudo(
        titulo: 'Antes de chamar',
        paragrafos: [
          'Tenha em mãos o número do pedido, o nome usado no cadastro e uma breve descrição do que precisa.',
          'Para pedidos em andamento, acompanhe primeiro a tela Meus pedidos. Ela mostra o status atualizado do pedido.',
        ],
      ),
    ];
  }

  List<MaisSecaoConteudo> secoesSobreLoja() {
    return [
      MaisSecaoConteudo(
        titulo: nomeLoja(),
        paragrafos: [
          enderecoLoja(),
          'Horário: ${horarioLoja()}',
          'Pedido mínimo: ${sessao.SessaoMercadoCliente.pedidoMinimo > 0 ? formatarMoeda(sessao.SessaoMercadoCliente.pedidoMinimo) : 'não informado'}',
        ],
      ),
      const MaisSecaoConteudo(
        titulo: 'Sobre o atendimento',
        paragrafos: [
          'A loja é responsável por separar os produtos, confirmar disponibilidade, preparar o pedido e realizar a entrega ou retirada.',
          'Alguns produtos podem sofrer substituição, ajuste de peso ou indisponibilidade. Quando necessário, a loja poderá entrar em contato.',
        ],
      ),
    ];
  }

  List<MaisSecaoConteudo> secoesPagamento() {
    final formasAceitas = meiosPagamentoLoja().join(', ');

    return [
      MaisSecaoConteudo(
        titulo: 'Como o pagamento funciona',
        paragrafos: [
          'Os pagamentos são realizados sempre na entrega ou na retirada do pedido.',
          'O aplicativo registra o pedido e informa a forma escolhida, mas não realiza cobrança online.',
          'Formas aceitas pela loja: $formasAceitas.',
        ],
      ),
      const MaisSecaoConteudo(
        titulo: 'Valores do pedido',
        paragrafos: [
          'O total apresentado considera os produtos do carrinho, descontos aplicados e eventual taxa de entrega.',
          'Produtos de peso variável podem ter ajuste no valor final após a separação.',
          'Em caso de divergência, a loja deve informar o cliente antes da entrega ou retirada.',
        ],
      ),
    ];
  }

  List<MaisSecaoConteudo> secoesEntregaRetirada() {
    return const [
      MaisSecaoConteudo(
        titulo: 'Entrega',
        paragrafos: [
          'Ao escolher entrega, informe um endereço válido ou envie sua localização quando solicitado.',
          'O prazo pode variar conforme demanda da loja, distância, trânsito, disponibilidade de produtos e horário de funcionamento.',
          'O entregador pode solicitar confirmação do pedido no momento da entrega.',
        ],
      ),
      MaisSecaoConteudo(
        titulo: 'Retirada na loja',
        paragrafos: [
          'Ao escolher retirada, o pedido fica separado para busca no endereço físico da loja.',
          'Não há taxa de entrega na retirada.',
          'A loja poderá avisar quando o pedido estiver pronto. Leve um documento ou informe o número do pedido se solicitado.',
        ],
      ),
      MaisSecaoConteudo(
        titulo: 'Substituições e indisponibilidade',
        paragrafos: [
          'Caso algum produto não esteja disponível, a loja poderá propor substituição, remover o item ou ajustar o pedido.',
          'Produtos frescos, perecíveis ou de peso variável podem ter pequenas diferenças entre o valor estimado e o valor final.',
        ],
      ),
    ];
  }

  List<MaisSecaoConteudo> secoesTermosUso() {
    return const [
      MaisSecaoConteudo(
        titulo: 'Uso do aplicativo',
        paragrafos: [
          'Este aplicativo permite consultar produtos, montar carrinho, enviar pedidos para a loja e acompanhar o andamento da compra.',
          'Ao usar o app, o cliente se compromete a informar dados verdadeiros, manter seus dados atualizados e usar o serviço de forma adequada.',
          'A loja pode recusar, cancelar ou ajustar pedidos em caso de indisponibilidade, dados incompletos, suspeita de uso indevido ou impossibilidade de atendimento.',
        ],
      ),
      MaisSecaoConteudo(
        titulo: 'Pedidos e preços',
        paragrafos: [
          'Os preços e estoques podem mudar até a confirmação e separação do pedido pela loja.',
          'Ofertas, cupons e condições especiais podem ter regras próprias, prazo de validade, limite de uso ou quantidade limitada.',
          'O pedido é confirmado pela loja conforme disponibilidade operacional, estoque e área de atendimento.',
        ],
      ),
      MaisSecaoConteudo(
        titulo: 'Responsabilidades',
        paragrafos: [
          'A loja é responsável pela venda, separação, cobrança, entrega ou retirada dos produtos.',
          'O aplicativo atua como canal digital para facilitar o pedido e a comunicação entre cliente e loja.',
          'O cliente é responsável por conferir os produtos recebidos e comunicar qualquer problema pelo canal de atendimento da loja.',
        ],
      ),
    ];
  }

  List<MaisSecaoConteudo> secoesPrivacidade() {
    return const [
      MaisSecaoConteudo(
        titulo: 'Dados coletados',
        paragrafos: [
          'Para operar o serviço, o aplicativo pode utilizar nome, telefone, e-mail, endereço, localização informada pelo cliente, histórico de pedidos e dados necessários para atendimento.',
          'Esses dados são usados para identificar o cliente, montar pedidos, calcular entrega, facilitar atendimento e melhorar a experiência de compra.',
        ],
      ),
      MaisSecaoConteudo(
        titulo: 'Compartilhamento',
        paragrafos: [
          'Os dados do pedido são compartilhados com a loja para separação, cobrança, entrega ou retirada.',
          'Quando necessário, informações de endereço e contato podem ser acessadas por equipe de atendimento e entrega.',
          'O aplicativo não deve vender dados pessoais do cliente.',
        ],
      ),
      MaisSecaoConteudo(
        titulo: 'Segurança e controle',
        paragrafos: [
          'O cliente deve manter seus dados de acesso protegidos e avisar a loja caso identifique uso indevido.',
          'O cliente pode solicitar atualização, correção ou exclusão de dados entrando em contato com a loja ou suporte indicado no aplicativo.',
          'Alguns dados podem ser mantidos pelo tempo necessário para cumprimento legal, fiscal, atendimento ao cliente e segurança da operação.',
        ],
      ),
    ];
  }

  List<MaisSecaoConteudo> secoesSobreApp() {
    return [
      MaisSecaoConteudo(
        titulo: 'Aplicativo',
        paragrafos: [
          'Versão instalada: ${versao()}',
          'Desenvolvido por: ${desenvolvedor()}',
          'Este aplicativo foi criado para aproximar clientes e lojas, permitindo pedidos de mercado com entrega ou retirada.',
        ],
      ),
      const MaisSecaoConteudo(
        titulo: 'Observação',
        paragrafos: [
          'As informações comerciais, formas de atendimento, disponibilidade de produtos e operação logística são definidas pela loja.',
          'Novos canais e dados oficiais podem ser integrados futuramente pela central administrativa.',
        ],
      ),
    ];
  }

  String formatarMoeda(double valor) {
    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTemaService.fundo,
      appBar: AppBar(
        title: const Text('Mais'),
        leading: onVoltarInicio != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onVoltarInicio,
              )
            : null,
        backgroundColor: AppTemaService.primaria,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          cabecalho(),
          const SizedBox(height: 12),
          gradeMenu(context),
          grupo(
            titulo: 'Cliente',
            children: [
              itemMenu(
                icone: Icons.person_outline,
                titulo: 'Minha conta',
                descricao: 'Dados pessoais, telefone e acesso.',
                onTap: () => abrirConta(context),
              ),
              itemMenu(
                icone: Icons.location_on_outlined,
                titulo: 'Meus endereços',
                descricao: 'Endereço principal e referência para entrega.',
                onTap: () => abrirConta(context),
              ),
            ],
          ),
          grupo(
            titulo: 'Loja e atendimento',
            children: [
              itemMenu(
                icone: Icons.support_agent_outlined,
                titulo: 'Atendimento',
                descricao: telefoneFormatado(),
                detalhe: 'WhatsApp',
                onTap: () => abrirDetalhe(
                  context,
                  titulo: 'Atendimento',
                  icone: Icons.support_agent_outlined,
                  secoes: secoesAtendimento(),
                ),
              ),
              itemMenu(
                icone: Icons.chat_outlined,
                titulo: 'Chamar no WhatsApp',
                descricao: 'Fale direto com a loja sobre pedidos e dúvidas.',
                cor: Colors.green,
                onTap: () => abrirWhatsApp(context),
              ),
              itemMenu(
                icone: Icons.storefront_outlined,
                titulo: 'Sobre a loja',
                descricao: enderecoLoja().replaceAll('\n', ' - '),
                onTap: () => abrirDetalhe(
                  context,
                  titulo: 'Sobre a loja',
                  icone: Icons.storefront_outlined,
                  secoes: secoesSobreLoja(),
                ),
              ),
            ],
          ),
          grupo(
            titulo: 'Pedidos',
            children: [
              itemMenu(
                icone: Icons.payments_outlined,
                titulo: 'Pagamentos',
                descricao: meiosPagamentoLoja().join(', '),
                onTap: () => abrirDetalhe(
                  context,
                  titulo: 'Pagamentos',
                  icone: Icons.payments_outlined,
                  secoes: secoesPagamento(),
                ),
              ),
              itemMenu(
                icone: Icons.local_shipping_outlined,
                titulo: 'Entrega e retirada',
                descricao: 'Regras de entrega, retirada e substituições.',
                onTap: () => abrirDetalhe(
                  context,
                  titulo: 'Entrega e retirada',
                  icone: Icons.local_shipping_outlined,
                  secoes: secoesEntregaRetirada(),
                ),
              ),
            ],
          ),
          grupo(
            titulo: 'Legal',
            children: [
              itemMenu(
                icone: Icons.description_outlined,
                titulo: 'Termos de uso',
                descricao:
                    'Regras de uso, pedidos, preços e responsabilidades.',
                onTap: () => abrirDetalhe(
                  context,
                  titulo: 'Termos de uso',
                  icone: Icons.description_outlined,
                  secoes: secoesTermosUso(),
                ),
              ),
              itemMenu(
                icone: Icons.privacy_tip_outlined,
                titulo: 'Política de privacidade',
                descricao: 'Como os dados são usados para operar pedidos.',
                onTap: () => abrirDetalhe(
                  context,
                  titulo: 'Privacidade',
                  icone: Icons.privacy_tip_outlined,
                  secoes: secoesPrivacidade(),
                ),
              ),
            ],
          ),
          grupo(
            titulo: 'Aplicativo',
            children: [
              itemMenu(
                icone: Icons.info_outline,
                titulo: 'Sobre o app',
                descricao: 'Versão, desenvolvedor e observações.',
                detalhe: versao(),
                onTap: () => abrirDetalhe(
                  context,
                  titulo: 'Sobre o app',
                  icone: Icons.info_outline,
                  secoes: secoesSobreApp(),
                ),
              ),
              itemMenu(
                icone: Icons.logout,
                titulo: 'Sair da conta',
                descricao: 'Encerrar sessão neste aparelho.',
                cor: const Color(0xFF8A4A4A),
                onTap: () => sair(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MaisSecaoConteudo {
  final String titulo;
  final List<String> paragrafos;

  const MaisSecaoConteudo({required this.titulo, required this.paragrafos});
}

class MaisDetalhePage extends StatelessWidget {
  final String titulo;
  final IconData icone;
  final List<MaisSecaoConteudo> secoes;

  const MaisDetalhePage({
    super.key,
    required this.titulo,
    required this.icone,
    required this.secoes,
  });

  Widget secao(MaisSecaoConteudo secao) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTemaService.primaria.withValues(alpha: 0.14),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            secao.titulo,
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 9),
          ...secao.paragrafos.map(
            (texto) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                texto,
                textAlign: TextAlign.justify,
                style: const TextStyle(
                  color: Color(0xFF4B5563),
                  fontSize: 13,
                  height: 1.38,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTemaService.fundo,
      appBar: AppBar(
        title: Text(titulo),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: AppTemaService.primaria,
        foregroundColor: Colors.white,
      ),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTemaService.primaria.withValues(alpha: 0.16),
                  width: 1.4,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppTemaService.primaria.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icone,
                      color: AppTemaService.primaria,
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      titulo,
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...secoes.map(secao),
          ],
        ),
      ),
    );
  }
}

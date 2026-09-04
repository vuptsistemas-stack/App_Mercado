import 'package:flutter/material.dart';

import '../../services/central_service.dart';

class CadastrarUsuarioPage extends StatefulWidget {
  final String? mercadoIdFixo;
  final String? mercadoNomeFixo;

  const CadastrarUsuarioPage({
    super.key,
    this.mercadoIdFixo,
    this.mercadoNomeFixo,
  });

  @override
  State<CadastrarUsuarioPage> createState() => _CadastrarUsuarioPageState();
}

class _CadastrarUsuarioPageState extends State<CadastrarUsuarioPage> {
  final service = CentralService();

  static const Color vermelho = Color(0xFFE30613);

  final nomeController = TextEditingController();
  final loginController = TextEditingController();
  final senhaController = TextEditingController();
  final confirmarSenhaController = TextEditingController();

  bool carregando = true;
  bool salvando = false;

  String tipoSelecionado = 'admin_loja';
  String? mercadoSelecionadoId;

  List<Map<String, dynamic>> mercados = [];

  final List<Map<String, dynamic>> modulosSistema = const [
    {
      'codigo': 'pedidos',
      'nome': 'Pedidos',
      'descricao': 'Visualizar e gerenciar pedidos da loja',
      'icone': Icons.receipt_long,
    },
    {
      'codigo': 'consulta_preco',
      'nome': 'Consulta Item P/ Compra',
      'descricao': 'Consulta antiga/padrão de item para compra',
      'icone': Icons.search,
    },
    {
      'codigo': 'produtos_inativos',
      'nome': 'Produtos inativos',
      'descricao':
          'Consultar produtos inativos quando o item não for encontrado',
      'icone': Icons.inventory_2_outlined,
    },
    {
      'codigo': 'consulta_item',
      'nome': 'Consulta Item',
      'descricao': 'Consulta visual com imagem grande do produto',
      'icone': Icons.image_search_outlined,
    },
    {
      'codigo': 'alterar_preco',
      'nome': 'Alterar preço',
      'descricao': 'Alterar preço do produto pela tela de consulta',
      'icone': Icons.price_change_outlined,
    },
    {
      'codigo': 'balanco',
      'nome': 'Balanço',
      'descricao': 'Coletar itens e gerar arquivo TXT',
      'icone': Icons.assignment_turned_in_outlined,
    },
    {
      'codigo': 'conferencia_notas',
      'nome': 'Conferencia NF-e',
      'descricao': 'Consultar notas de entrada para conferencia',
      'icone': Icons.fact_check_outlined,
    },
    {
      'codigo': 'estoque',
      'nome': 'Estoque',
      'descricao': 'Acesso ao menu geral de estoque',
      'icone': Icons.inventory,
    },
    {
      'codigo': 'estoque_entrada',
      'nome': 'Entrada de Estoque',
      'descricao': 'Registrar entrada de estoque',
      'icone': Icons.add_box,
    },
    {
      'codigo': 'estoque_correcao',
      'nome': 'Correção de Estoque',
      'descricao': 'Corrigir quantidade de estoque',
      'icone': Icons.edit_note,
    },
    {
      'codigo': 'estoque_baixa_avaria',
      'nome': 'Baixa por Avaria',
      'descricao': 'Baixar produtos avariados do estoque',
      'icone': Icons.broken_image_outlined,
    },
    {
      'codigo': 'estoque_baixa_validade',
      'nome': 'Baixa por Validade',
      'descricao': 'Baixar produtos vencidos do estoque',
      'icone': Icons.event_busy_outlined,
    },
    {
      'codigo': 'estoque_abrir_pacote',
      'nome': 'Abrir pacote / granel',
      'descricao': 'Baixar embalagem fechada e somar no item a granel',
      'icone': Icons.inventory_2_outlined,
    },
    {
      'codigo': 'estoque_consumo_interno',
      'nome': 'Consumo Interno',
      'descricao': 'Registrar consumo interno da loja',
      'icone': Icons.inventory_2,
    },
    {
      'codigo': 'estoque_auditoria',
      'nome': 'Auditoria de Estoque',
      'descricao': 'Consultar alterações de estoque',
      'icone': Icons.fact_check_outlined,
    },
    {
      'codigo': 'produtos_app',
      'nome': 'Produtos app',
      'descricao': 'Cadastrar produtos do modo BANCO_LOJA',
      'icone': Icons.shopping_basket_outlined,
    },
    {
      'codigo': 'receitas',
      'nome': 'Receitas',
      'descricao': 'Criar ficha técnica e produzir itens',
      'icone': Icons.receipt_outlined,
    },
    {
      'codigo': 'cupons',
      'nome': 'Cupons',
      'descricao': 'Criar e gerenciar cupons de desconto',
      'icone': Icons.local_offer_outlined,
    },
    {
      'codigo': 'ofertas',
      'nome': 'Ofertas',
      'descricao': 'Criar ofertas do app Mercado',
      'icone': Icons.campaign_outlined,
    },
    {
      'codigo': 'jornal_promocoes',
      'nome': 'Jornal de promocoes',
      'descricao': 'Gerar encarte para impressao e redes sociais',
      'icone': Icons.newspaper_outlined,
    },
    {
      'codigo': 'clientes_app',
      'nome': 'Clientes do app',
      'descricao': 'Listar e bloquear clientes cadastrados no app Mercado',
      'icone': Icons.people_alt_outlined,
    },
    {
      'codigo': 'acoes_validade',
      'nome': 'Ações de validade',
      'descricao': 'Criar descontos por validade e monitorar estoque',
      'icone': Icons.timer_outlined,
    },
    {
      'codigo': 'peso_variavel',
      'nome': 'Peso variável',
      'descricao': 'Configurar produtos vendidos por KG/peso',
      'icone': Icons.scale_outlined,
    },
    {
      'codigo': 'relatorios',
      'nome': 'Relatórios',
      'descricao': 'Visualizar relatórios e exportar Excel',
      'icone': Icons.bar_chart,
    },
    {
      'codigo': 'loja_configuracoes',
      'nome': 'Configurações da Loja',
      'descricao': 'Alterar configurações da loja',
      'icone': Icons.store,
    },
    {
      'codigo': 'usuarios',
      'nome': 'Usuários',
      'descricao': 'Gerenciar usuários e permissões',
      'icone': Icons.people,
    },
  ];

  Set<String> permissoesSelecionadas = {};

  bool get modoLojaFixa {
    return widget.mercadoIdFixo != null && widget.mercadoIdFixo!.isNotEmpty;
  }

  bool get tipoMaster {
    return tipoSelecionado == 'master';
  }

  bool get adminLoja {
    return tipoSelecionado == 'admin_loja';
  }

  bool get entregador {
    return tipoSelecionado == 'entregador';
  }

  List<String> get todasPermissoes {
    return modulosSistema.map((modulo) => modulo['codigo'].toString()).toList();
  }

  @override
  void initState() {
    super.initState();

    if (modoLojaFixa) {
      tipoSelecionado = 'usuario';
      mercadoSelecionadoId = widget.mercadoIdFixo;
      aplicarPermissoesPadrao();

      carregando = false;
    } else {
      aplicarPermissoesPadrao();
      carregarMercados();
    }
  }

  @override
  void dispose() {
    nomeController.dispose();
    loginController.dispose();
    senhaController.dispose();
    confirmarSenhaController.dispose();
    super.dispose();
  }

  Future<void> carregarMercados() async {
    try {
      final resposta = await service.listarLojas();

      if (!mounted) return;

      setState(() {
        mercados = resposta;
        carregando = false;

        if (mercados.isNotEmpty) {
          mercadoSelecionadoId = mercados.first['id']?.toString();
        }
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

  void aplicarPermissoesPadrao() {
    if (tipoSelecionado == 'master') {
      permissoesSelecionadas = {};
      return;
    }

    if (tipoSelecionado == 'admin_loja') {
      permissoesSelecionadas = todasPermissoes.toSet();
      return;
    }

    if (tipoSelecionado == 'estoque') {
      permissoesSelecionadas = {
        'consulta_preco',
        'balanco',
        'estoque',
        'estoque_entrada',
        'estoque_correcao',
        'estoque_baixa_avaria',
        'estoque_baixa_validade',
        'estoque_abrir_pacote',
        'estoque_consumo_interno',
        'estoque_auditoria',
        'relatorios',
      };
      return;
    }

    if (tipoSelecionado == 'caixa') {
      permissoesSelecionadas = {'pedidos', 'consulta_preco'};
      return;
    }

    if (tipoSelecionado == 'entregador') {
      permissoesSelecionadas = {'pedidos'};
      return;
    }

    permissoesSelecionadas = {'consulta_preco'};
  }

  String textoTipo(String tipo) {
    switch (tipo) {
      case 'master':
        return 'Master do sistema';
      case 'admin_loja':
        return 'Admin da loja';
      case 'estoque':
        return 'Estoque';
      case 'caixa':
        return 'Caixa';
      case 'entregador':
        return 'Motoboy / entregador';
      case 'usuario':
        return 'Usuário comum';
      default:
        return tipo;
    }
  }

  IconData iconeTipo(String tipo) {
    switch (tipo) {
      case 'master':
        return Icons.admin_panel_settings;
      case 'admin_loja':
        return Icons.store_mall_directory;
      case 'estoque':
        return Icons.inventory_2;
      case 'caixa':
        return Icons.point_of_sale;
      case 'entregador':
        return Icons.delivery_dining;
      case 'usuario':
        return Icons.person;
      default:
        return Icons.person;
    }
  }

  Color corTipo(String tipo) {
    switch (tipo) {
      case 'master':
        return Colors.indigo;
      case 'admin_loja':
        return Colors.purple;
      case 'estoque':
        return Colors.teal;
      case 'caixa':
        return Colors.green;
      case 'entregador':
        return Colors.deepOrange;
      case 'usuario':
        return Colors.blueGrey;
      default:
        return Colors.blueGrey;
    }
  }

  Future<void> salvarUsuario() async {
    final nome = nomeController.text.trim();
    final login = loginController.text.trim();
    final senha = senhaController.text.trim();
    final confirmarSenha = confirmarSenhaController.text.trim();

    if (nome.isEmpty || login.isEmpty || senha.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe nome, login e senha'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (senha.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A senha precisa ter pelo menos 6 caracteres'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (confirmarSenha.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirme a senha'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (senha != confirmarSenha) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('As senhas não conferem'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!tipoMaster && mercadoSelecionadoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione o mercado do usuário'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!tipoMaster && !adminLoja && permissoesSelecionadas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione pelo menos uma permissão'),
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
      if (tipoMaster) {
        await service.cadastrarUsuarioMaster(
          nome: nome,
          login: login,
          senha: senha,
        );
      } else {
        await service.cadastrarUsuarioMercado(
          mercadoId: mercadoSelecionadoId!,
          nome: nome,
          login: login,
          senha: senha,
          perfil: tipoSelecionado,
          permissoes: permissoesSelecionadas.toList(),
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${textoTipo(tipoSelecionado)} cadastrado com sucesso'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        salvando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao cadastrar usuário: ${CentralService.mensagemErroUsuario(e)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget campoTexto({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool senha = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: senha,
      enabled: !salvando,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget cardAvisoTipo() {
    final cor = corTipo(tipoSelecionado);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(iconeTipo(tipoSelecionado), color: cor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tipoMaster
                  ? 'Usuário master terá acesso geral ao sistema central.'
                  : adminLoja
                  ? 'Admin da loja receberá os botões liberados pelo master para a loja selecionada.'
                  : 'Usuário será vinculado à loja e receberá apenas as permissões marcadas abaixo.',
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget cardLojaFixa() {
    final nomeLoja = widget.mercadoNomeFixo?.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          const Icon(Icons.store, color: vermelho),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              nomeLoja == null || nomeLoja.isEmpty
                  ? 'Loja selecionada'
                  : nomeLoja,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget blocoPermissoes() {
    if (tipoMaster) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.security, color: vermelho),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Permissões da loja',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              TextButton(
                onPressed: salvando || adminLoja || entregador
                    ? null
                    : () {
                        setState(() {
                          permissoesSelecionadas = todasPermissoes.toSet();
                        });
                      },
                child: const Text('Todas'),
              ),
              TextButton(
                onPressed: salvando || adminLoja || entregador
                    ? null
                    : () {
                        setState(() {
                          permissoesSelecionadas = {};
                        });
                      },
                child: const Text('Limpar'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            adminLoja
                ? 'O admin da loja usará o pacote de botões liberados pelo master.'
                : 'Marque o que este usuário poderá acessar.',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
          if (entregador) ...[
            const SizedBox(height: 6),
            const Text(
              'Acesso fixo: somente pedidos em entrega.',
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 10),
          ...modulosSistema.map((modulo) {
            final codigo = modulo['codigo'].toString();
            final nome = modulo['nome'].toString();
            final descricao = modulo['descricao'].toString();
            final icone = modulo['icone'] as IconData;
            final marcado =
                adminLoja || permissoesSelecionadas.contains(codigo);

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: marcado
                    ? vermelho.withOpacity(0.05)
                    : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: marcado
                      ? vermelho.withOpacity(0.25)
                      : Colors.black.withOpacity(0.04),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: CheckboxListTile(
                  value: marcado,
                  onChanged: salvando || adminLoja || entregador
                      ? null
                      : (valor) {
                          setState(() {
                            if (valor == true) {
                              permissoesSelecionadas.add(codigo);
                            } else {
                              permissoesSelecionadas.remove(codigo);
                            }
                          });
                        },
                  activeColor: vermelho,
                  controlAffinity: ListTileControlAffinity.trailing,
                  secondary: Icon(
                    icone,
                    color: marcado ? vermelho : Colors.black45,
                  ),
                  title: Text(
                    nome,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    descricao,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Cadastrar usuário'),
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
                    const Text(
                      'Novo usuário',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      modoLojaFixa
                          ? 'Cadastre um novo usuário para esta loja.'
                          : 'Escolha o tipo de usuário e preencha os dados de acesso.',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 22),
                    DropdownButtonFormField<String>(
                      value: tipoSelecionado,
                      decoration: InputDecoration(
                        labelText: 'Tipo de usuário',
                        prefixIcon: const Icon(Icons.manage_accounts),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      items: [
                        if (!modoLojaFixa)
                          const DropdownMenuItem(
                            value: 'master',
                            child: Text('Master do sistema'),
                          ),
                        const DropdownMenuItem(
                          value: 'admin_loja',
                          child: Text('Admin da loja'),
                        ),
                        const DropdownMenuItem(
                          value: 'estoque',
                          child: Text('Estoque'),
                        ),
                        const DropdownMenuItem(
                          value: 'caixa',
                          child: Text('Caixa'),
                        ),
                        const DropdownMenuItem(
                          value: 'entregador',
                          child: Text('Motoboy / entregador'),
                        ),
                        const DropdownMenuItem(
                          value: 'usuario',
                          child: Text('Usuário comum'),
                        ),
                      ],
                      onChanged: salvando
                          ? null
                          : (valor) {
                              if (valor == null) return;

                              setState(() {
                                tipoSelecionado = valor;
                                aplicarPermissoesPadrao();
                              });
                            },
                    ),
                    const SizedBox(height: 14),
                    cardAvisoTipo(),
                    if (!tipoMaster && !modoLojaFixa) ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: mercadoSelecionadoId,
                        decoration: InputDecoration(
                          labelText: 'Mercado',
                          prefixIcon: const Icon(Icons.store),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        items: mercados.map((mercado) {
                          final id = mercado['id']?.toString() ?? '';
                          final nome = mercado['nome']?.toString() ?? 'Mercado';

                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text(nome),
                          );
                        }).toList(),
                        onChanged: salvando
                            ? null
                            : (valor) {
                                setState(() {
                                  mercadoSelecionadoId = valor;
                                });
                              },
                      ),
                    ],
                    if (modoLojaFixa) ...[
                      const SizedBox(height: 14),
                      cardLojaFixa(),
                    ],
                    const SizedBox(height: 22),
                    campoTexto(
                      controller: nomeController,
                      label: 'Nome',
                      icon: Icons.person,
                      hint: 'Ex: João Silva',
                    ),
                    const SizedBox(height: 14),
                    campoTexto(
                      controller: loginController,
                      label: 'Login',
                      icon: Icons.account_circle,
                      hint: tipoMaster ? 'Ex: roberto' : 'Ex: joao_caixa',
                    ),
                    const SizedBox(height: 14),
                    campoTexto(
                      controller: senhaController,
                      label: 'Senha',
                      icon: Icons.lock,
                      hint: 'Mínimo 6 caracteres',
                      senha: true,
                    ),
                    const SizedBox(height: 14),
                    campoTexto(
                      controller: confirmarSenhaController,
                      label: 'Confirmar senha',
                      icon: Icons.lock_outline,
                      hint: 'Digite novamente a senha',
                      senha: true,
                    ),
                    if (!tipoMaster) ...[
                      const SizedBox(height: 22),
                      blocoPermissoes(),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: salvando ? null : salvarUsuario,
                        icon: const Icon(Icons.save),
                        label: const Text('Cadastrar usuário'),
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
                  Container(
                    color: Colors.black.withOpacity(0.08),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }
}

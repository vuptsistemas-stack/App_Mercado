import 'package:flutter/material.dart';

import '../../services/central_service.dart';
import '../../services/sessao_loja.dart';

class ClientesAppPage extends StatefulWidget {
  const ClientesAppPage({super.key});

  @override
  State<ClientesAppPage> createState() => _ClientesAppPageState();
}

class _ClientesAppPageState extends State<ClientesAppPage> {
  final CentralService centralService = CentralService();
  final TextEditingController buscaController = TextEditingController();

  bool carregando = true;
  String mensagemErro = '';
  String? clienteAlterandoId;
  String? clienteAlterandoCategoriasId;
  List<Map<String, dynamic>> clientes = [];

  Color get corPrimaria => SessaoLoja.corPrimaria;
  Color get corFundo => SessaoLoja.corFundo;

  @override
  void initState() {
    super.initState();
    buscaController.addListener(_atualizarBusca);
    carregarClientes();
  }

  @override
  void dispose() {
    buscaController.removeListener(_atualizarBusca);
    buscaController.dispose();
    super.dispose();
  }

  void _atualizarBusca() {
    if (mounted) setState(() {});
  }

  String texto(dynamic valor) => valor?.toString().trim() ?? '';

  bool booleano(dynamic valor) {
    if (valor is bool) return valor;
    if (valor is num) return valor == 1;
    return ['true', '1', 'sim', 's'].contains(texto(valor).toLowerCase());
  }

  List<String> categoriasDoCliente(dynamic valor) {
    final itens = valor is List
        ? valor
        : valor is String && valor.trim().isNotEmpty
        ? valor.split(',')
        : const <dynamic>[];
    final resultado = <String>[];
    final chaves = <String>{};

    for (final item in itens) {
      final categoria = texto(item);
      final chave = normalizar(categoria);

      if (categoria.isEmpty || chave.isEmpty || chaves.contains(chave)) {
        continue;
      }

      resultado.add(categoria);
      chaves.add(chave);
    }

    resultado.sort((a, b) => normalizar(a).compareTo(normalizar(b)));
    return resultado;
  }

  String normalizar(String valor) {
    return valor
        .toLowerCase()
        .replaceAll(RegExp('[áàâãä]'), 'a')
        .replaceAll(RegExp('[éèêë]'), 'e')
        .replaceAll(RegExp('[íìîï]'), 'i')
        .replaceAll(RegExp('[óòôõö]'), 'o')
        .replaceAll(RegExp('[úùûü]'), 'u')
        .replaceAll('ç', 'c');
  }

  List<Map<String, dynamic>> get clientesFiltrados {
    final busca = normalizar(buscaController.text.trim());

    if (busca.isEmpty) return clientes;

    return clientes.where((cliente) {
      final conteudo = normalizar(
        [
          texto(cliente['nome']),
          texto(cliente['email']),
          texto(cliente['telefone']),
          texto(cliente['cidade']),
        ].join(' '),
      );
      return conteudo.contains(busca);
    }).toList();
  }

  int get totalBloqueados =>
      clientes.where((cliente) => booleano(cliente['bloqueado'])).length;

  Future<void> carregarClientes() async {
    final mercadoId = SessaoLoja.mercadoId?.trim() ?? '';

    if (mercadoId.isEmpty) {
      setState(() {
        carregando = false;
        mensagemErro = 'Nenhuma loja selecionada.';
      });
      return;
    }

    setState(() {
      carregando = true;
      mensagemErro = '';
    });

    try {
      final resultado = await centralService.listarClientesApp(
        mercadoId: mercadoId,
      );

      if (!mounted) return;

      setState(() {
        clientes = resultado;
        carregando = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        carregando = false;
        mensagemErro = CentralService.mensagemErroUsuario(e);
      });
    }
  }

  Future<String?> solicitarMotivoBloqueio(String nome) async {
    final controller = TextEditingController();

    final motivo = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bloquear cliente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$nome não conseguirá entrar nem finalizar compras no app.'),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 180,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                hintText: 'Ex: Cadastro bloqueado pela loja',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            icon: const Icon(Icons.block),
            label: const Text('Bloquear'),
          ),
        ],
      ),
    );

    controller.dispose();
    return motivo;
  }

  Future<bool> confirmarDesbloqueio(String nome) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Liberar cliente'),
            content: Text('$nome poderá voltar a comprar no app Mercado.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.lock_open),
                label: const Text('Liberar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> alterarBloqueio(Map<String, dynamic> cliente) async {
    final clienteId = texto(cliente['id']);
    final nome = texto(cliente['nome']).isEmpty
        ? 'Este cliente'
        : texto(cliente['nome']);
    final estaBloqueado = booleano(cliente['bloqueado']);
    String motivo = '';

    if (estaBloqueado) {
      if (!await confirmarDesbloqueio(nome)) return;
    } else {
      final motivoInformado = await solicitarMotivoBloqueio(nome);
      if (motivoInformado == null) return;
      motivo = motivoInformado;
    }

    if (!mounted) return;

    setState(() => clienteAlterandoId = clienteId);

    try {
      final resposta = await centralService.alterarBloqueioClienteApp(
        mercadoId: SessaoLoja.mercadoId!,
        clienteId: clienteId,
        bloqueado: !estaBloqueado,
        motivo: motivo,
      );
      final atualizado = Map<String, dynamic>.from(
        resposta['cliente'] ?? <String, dynamic>{},
      );

      if (!mounted) return;

      setState(() {
        clientes = clientes
            .map((item) => texto(item['id']) == clienteId ? atualizado : item)
            .toList();
        clienteAlterandoId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            estaBloqueado
                ? 'Cliente liberado para comprar.'
                : 'Cliente bloqueado no app Mercado.',
          ),
          backgroundColor: estaBloqueado ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => clienteAlterandoId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(CentralService.mensagemErroUsuario(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> editarCategoriasBloqueadas(Map<String, dynamic> cliente) async {
    final clienteId = texto(cliente['id']);
    final nome = texto(cliente['nome']).isEmpty
        ? 'Cliente sem nome'
        : texto(cliente['nome']);
    final controller = TextEditingController();
    var categorias = categoriasDoCliente(cliente['categorias_bloqueadas']);

    final resultado = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, atualizarDialog) {
          void adicionarCategoria() {
            final categoria = controller.text.trim();
            final chave = normalizar(categoria);

            if (categoria.isEmpty || chave.isEmpty) return;

            if (categorias.any((item) => normalizar(item) == chave)) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text('Essa categoria já foi adicionada.'),
                ),
              );
              return;
            }

            atualizarDialog(() {
              categorias = [...categorias, categoria]
                ..sort((a, b) => normalizar(a).compareTo(normalizar(b)));
              controller.clear();
            });
          }

          return AlertDialog(
            title: const Text('Categorias restritas'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Somente $nome deixará de ver os produtos das categorias informadas.',
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => adicionarCategoria(),
                            decoration: const InputDecoration(
                              labelText: 'Nome da categoria',
                              hintText: 'Ex: Açougue',
                              prefixIcon: Icon(Icons.category_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: adicionarCategoria,
                          tooltip: 'Adicionar categoria',
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (categorias.isEmpty)
                      const Text(
                        'Nenhuma categoria restrita para este cliente.',
                        style: TextStyle(color: Colors.black54),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: categorias.map((categoria) {
                          return InputChip(
                            avatar: const Icon(
                              Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            label: Text(categoria),
                            onDeleted: () {
                              atualizarDialog(() {
                                categorias = categorias
                                    .where((item) => item != categoria)
                                    .toList();
                              });
                            },
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, categorias),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();

    if (resultado == null || !mounted) return;

    setState(() => clienteAlterandoCategoriasId = clienteId);

    try {
      final resposta = await centralService
          .salvarCategoriasBloqueadasClienteApp(
            mercadoId: SessaoLoja.mercadoId!,
            clienteId: clienteId,
            categorias: resultado,
          );
      final atualizado = Map<String, dynamic>.from(
        resposta['cliente'] ?? <String, dynamic>{},
      );

      if (!mounted) return;

      setState(() {
        clientes = clientes
            .map((item) => texto(item['id']) == clienteId ? atualizado : item)
            .toList();
        clienteAlterandoCategoriasId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Categorias restritas atualizadas para este cliente.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => clienteAlterandoCategoriasId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(CentralService.mensagemErroUsuario(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget resumo() {
    return Row(
      children: [
        Expanded(
          child: _contador(
            titulo: 'Clientes',
            valor: clientes.length,
            icone: Icons.people_alt_outlined,
            cor: corPrimaria,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _contador(
            titulo: 'Bloqueados',
            valor: totalBloqueados,
            icone: Icons.person_off_outlined,
            cor: Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _contador({
    required String titulo,
    required int valor,
    required IconData icone,
    required Color cor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(icone, color: cor),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                valor.toString(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(titulo, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ],
      ),
    );
  }

  Widget cardCliente(Map<String, dynamic> cliente) {
    final id = texto(cliente['id']);
    final nome = texto(cliente['nome']).isEmpty
        ? 'Cliente sem nome'
        : texto(cliente['nome']);
    final email = texto(cliente['email']);
    final telefone = texto(cliente['telefone']);
    final cidade = texto(cliente['cidade']);
    final bloqueado = booleano(cliente['bloqueado']);
    final alterando = clienteAlterandoId == id;
    final alterandoCategorias = clienteAlterandoCategoriasId == id;
    final motivo = texto(cliente['bloqueio_motivo']);
    final categorias = categoriasDoCliente(cliente['categorias_bloqueadas']);

    return Material(
      color: bloqueado ? const Color(0xFFFFF1F2) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: bloqueado
              ? Colors.red.withValues(alpha: 0.45)
              : Colors.black.withValues(alpha: 0.09),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: bloqueado
                      ? Colors.red.withValues(alpha: 0.12)
                      : corPrimaria.withValues(alpha: 0.10),
                  foregroundColor: bloqueado ? Colors.red : corPrimaria,
                  child: Icon(
                    bloqueado
                        ? Icons.person_off_outlined
                        : Icons.person_outline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nome,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black54),
                        ),
                    ],
                  ),
                ),
                if (alterando)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch.adaptive(
                    value: bloqueado,
                    activeThumbColor: Colors.red,
                    onChanged: (_) => alterarBloqueio(cliente),
                  ),
              ],
            ),
            if (telefone.isNotEmpty || cidade.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  if (telefone.isNotEmpty)
                    _detalhe(Icons.phone_outlined, telefone),
                  if (cidade.isNotEmpty)
                    _detalhe(Icons.location_on_outlined, cidade),
                ],
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: alterandoCategorias
                    ? null
                    : () => editarCategoriasBloqueadas(cliente),
                icon: alterandoCategorias
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.visibility_off_outlined),
                label: Text(
                  categorias.isEmpty
                      ? 'Restringir categorias'
                      : 'Categorias restritas (${categorias.length})',
                ),
              ),
            ),
            if (categorias.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: categorias
                    .map(
                      (categoria) => Chip(
                        avatar: const Icon(
                          Icons.visibility_off_outlined,
                          size: 16,
                        ),
                        label: Text(categoria),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ],
            if (bloqueado) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  motivo.isEmpty ? 'Cliente bloqueado pela loja.' : motivo,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detalhe(IconData icone, String valor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 16, color: Colors.black45),
        const SizedBox(width: 5),
        Text(valor, style: const TextStyle(color: Colors.black54)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = clientesFiltrados;

    return Scaffold(
      backgroundColor: corFundo,
      appBar: AppBar(
        title: const Text('Clientes do app'),
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: carregando ? null : carregarClientes,
            tooltip: 'Atualizar clientes',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: carregarClientes,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
          children: [
            resumo(),
            const SizedBox(height: 14),
            TextField(
              controller: buscaController,
              decoration: InputDecoration(
                hintText: 'Buscar por nome, e-mail ou telefone',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: buscaController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: buscaController.clear,
                        tooltip: 'Limpar busca',
                        icon: const Icon(Icons.close),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (carregando)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (mensagemErro.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                ),
                child: Text(
                  mensagemErro,
                  style: const TextStyle(color: Colors.red),
                ),
              )
            else if (filtrados.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: Text('Nenhum cliente encontrado.')),
              )
            else
              ...filtrados.map(
                (cliente) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: cardCliente(cliente),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

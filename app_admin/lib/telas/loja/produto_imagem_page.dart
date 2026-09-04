import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/central_service.dart';
import '../../services/sessao_loja.dart';

class ProdutoImagemPage extends StatefulWidget {
  final Map<String, dynamic> produto;

  const ProdutoImagemPage({super.key, required this.produto});

  @override
  State<ProdutoImagemPage> createState() => _ProdutoImagemPageState();
}

class _ProdutoImagemPageState extends State<ProdutoImagemPage> {
  final centralService = CentralService();
  final imagePicker = ImagePicker();

  late Map<String, dynamic> produto;

  String? imagemUrl;
  String? fonteImagem;
  bool carregando = false;
  bool enviando = false;
  bool salvandoUrl = false;
  bool alterandoPreco = false;

  Color get corPrimaria => SessaoLoja.corPrimaria;
  Color get corFundo => SessaoLoja.corFundo;
  bool get podeAlterarPreco =>
      SessaoLoja.alterarPrecoConsultaAtivo &&
      SessaoLoja.temApiConfigurada &&
      (!SessaoLoja.logadoNaLoja || SessaoLoja.temPermissao('alterar_preco'));

  @override
  void initState() {
    super.initState();
    produto = Map<String, dynamic>.from(widget.produto);
    imagemUrl = texto(
      produto['imagem_url'] ?? produto['imagem'] ?? produto['url_imagem'],
    );

    if (imagemUrl == null || imagemUrl!.isEmpty) {
      carregarImagem(silencioso: true);
    }
  }

  String texto(dynamic valor) {
    final convertido = valor?.toString().trim() ?? '';
    return convertido.toLowerCase() == 'null' ? '' : convertido;
  }

  String get nomeProduto {
    final nome = texto(
      produto['nome_produto'] ??
          produto['descricao'] ??
          produto['produto'] ??
          produto['nome'],
    );

    return nome.isEmpty ? 'Produto' : nome;
  }

  String get eanProduto {
    return texto(
      produto['ean_principal'] ??
          produto['ean'] ??
          produto['codigo_barras'] ??
          produto['codigo'],
    );
  }

  String get codigoBarrasProduto {
    return texto(
      produto['codigo_barras'] ??
          produto['ean_principal'] ??
          produto['ean'] ??
          produto['codigo'],
    );
  }

  double? numeroDecimal(dynamic valor) {
    var convertido = texto(
      valor,
    ).replaceAll('R\$', '').replaceAll(' ', '').trim();

    if (convertido.isEmpty) {
      return null;
    }

    if (convertido.contains(',')) {
      convertido = convertido.replaceAll('.', '').replaceAll(',', '.');
    }

    return double.tryParse(convertido);
  }

  double? get precoAtual {
    return numeroDecimal(
      produto['preco_venda'] ??
          produto['preco'] ??
          produto['valor_venda'] ??
          produto['preco_atual'],
    );
  }

  String moeda(double? valor) {
    if (valor == null) {
      return '-';
    }

    return 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String fonteLegivel(String? fonte) {
    switch (texto(fonte)) {
      case 'cache_base_loja':
      case 'manual_base_loja':
      case 'serpapi_base_loja':
        return 'Base da loja';
      case 'cache_central':
      case 'cache_central_zero_esquerda':
      case 'manual_central':
      case 'serpapi':
        return 'Central';
      case 'sem_serpapi_key':
        return 'Sem chave de busca';
      case 'nao_encontrada':
        return 'Nao encontrada';
      default:
        return fonte ?? 'Produto';
    }
  }

  void mostrarMensagem(String mensagem, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: erro ? Colors.red : corPrimaria,
      ),
    );
  }

  Future<void> carregarImagem({bool silencioso = false}) async {
    final mercadoId = SessaoLoja.mercadoId?.trim();

    if (mercadoId == null || mercadoId.isEmpty) {
      mostrarMensagem('Loja atual nao identificada.', erro: true);
      return;
    }

    if (eanProduto.isEmpty && nomeProduto.isEmpty) {
      mostrarMensagem(
        'Produto sem EAN ou nome para buscar imagem.',
        erro: true,
      );
      return;
    }

    setState(() => carregando = true);

    try {
      final resposta = await centralService.buscarImagemProdutoCentral(
        mercadoId: mercadoId,
        mercadoCodigo: SessaoLoja.mercadoCodigo,
        ean: eanProduto.isEmpty ? null : eanProduto,
        codigoBarras: codigoBarrasProduto.isEmpty ? null : codigoBarrasProduto,
        nomeProduto: nomeProduto,
      );

      final url = texto(
        resposta['imagem_url'] ??
            resposta['url'] ??
            resposta['image'] ??
            resposta['thumbnail'],
      );

      if (!mounted) return;

      setState(() {
        imagemUrl = url.isEmpty ? null : url;
        fonteImagem = texto(resposta['fonte']);
      });

      if (!silencioso) {
        mostrarMensagem(
          url.isEmpty
              ? 'Nenhuma imagem encontrada para este produto.'
              : 'Imagem carregada.',
          erro: url.isEmpty,
        );
      }
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(
        'Erro ao carregar imagem: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() => carregando = false);
      }
    }
  }

  Future<void> salvarImagemUrl(String url) async {
    final mercadoId = SessaoLoja.mercadoId?.trim();
    final urlLimpa = url.trim();

    if (mercadoId == null || mercadoId.isEmpty) {
      mostrarMensagem('Loja atual nao identificada.', erro: true);
      return;
    }

    if (!urlLimpa.startsWith('http://') && !urlLimpa.startsWith('https://')) {
      mostrarMensagem('Informe uma URL de imagem valida.', erro: true);
      return;
    }

    if (eanProduto.isEmpty) {
      mostrarMensagem('Produto sem EAN para salvar imagem.', erro: true);
      return;
    }

    setState(() => salvandoUrl = true);

    try {
      final resposta = await centralService.salvarImagemProdutoCentral(
        mercadoId: mercadoId,
        mercadoCodigo: SessaoLoja.mercadoCodigo,
        imagemUrl: urlLimpa,
        ean: eanProduto,
        codigoBarras: codigoBarrasProduto,
        nomeProduto: nomeProduto,
      );

      if (!mounted) return;

      setState(() {
        imagemUrl = texto(resposta['imagem_url']).isEmpty
            ? urlLimpa
            : texto(resposta['imagem_url']);
        fonteImagem = texto(resposta['fonte']);
      });

      mostrarMensagem('Imagem salva para este produto.');
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(
        'Erro ao salvar imagem: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() => salvandoUrl = false);
      }
    }
  }

  Future<void> selecionarEEnviarImagem() async {
    if (enviando || salvandoUrl) return;

    final mercadoId = SessaoLoja.mercadoId?.trim();

    if (mercadoId == null || mercadoId.isEmpty) {
      mostrarMensagem('Loja atual nao identificada.', erro: true);
      return;
    }

    if (eanProduto.isEmpty) {
      mostrarMensagem('Produto sem EAN para salvar imagem.', erro: true);
      return;
    }

    try {
      final imagem = await imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1400,
        imageQuality: 88,
      );

      if (imagem == null) return;

      setState(() => enviando = true);

      final resposta = await centralService.uploadImagemProdutoApp(
        mercadoId: mercadoId,
        mercadoCodigo: SessaoLoja.mercadoCodigo,
        imagemFile: File(imagem.path),
        ean: eanProduto,
        codigoBarras: codigoBarrasProduto,
        nomeProduto: nomeProduto,
      );

      final url = texto(resposta['imagem_url']);

      if (url.isEmpty) {
        mostrarMensagem(
          'Upload concluido, mas a URL nao retornou.',
          erro: true,
        );
        return;
      }

      await salvarImagemUrl(url);
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(
        'Erro ao enviar imagem: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() => enviando = false);
      }
    }
  }

  Future<void> informarUrlImagem() async {
    var urlDigitada = imagemUrl ?? '';

    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('URL da imagem'),
          content: TextFormField(
            initialValue: urlDigitada,
            autofocus: true,
            keyboardType: TextInputType.url,
            onChanged: (valor) => urlDigitada = valor,
            onFieldSubmitted: (valor) {
              FocusScope.of(dialogContext).unfocus();
              Navigator.pop(dialogContext, valor.trim());
            },
            decoration: const InputDecoration(
              labelText: 'Cole a URL da imagem',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.pop(dialogContext, urlDigitada.trim());
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    if (url == null || url.trim().isEmpty) return;

    await salvarImagemUrl(url);
  }

  Future<void> mostrarOpcoesEditar() async {
    final escolha = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (bottomContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Editar imagem do produto',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'A imagem sera salva no Central ou na base da loja conforme o tipo do EAN.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: Icon(Icons.upload_file, color: corPrimaria),
                  title: const Text('Fazer upload da imagem'),
                  onTap: () => Navigator.pop(bottomContext, 'upload'),
                ),
                ListTile(
                  leading: Icon(Icons.link, color: corPrimaria),
                  title: const Text('Informar URL da imagem'),
                  onTap: () => Navigator.pop(bottomContext, 'url'),
                ),
                ListTile(
                  leading: Icon(Icons.search, color: corPrimaria),
                  title: const Text('Buscar novamente'),
                  onTap: () => Navigator.pop(bottomContext, 'buscar'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || escolha == null) return;

    if (escolha == 'upload') {
      await selecionarEEnviarImagem();
    } else if (escolha == 'url') {
      await informarUrlImagem();
    } else if (escolha == 'buscar') {
      await carregarImagem();
    }
  }

  Future<void> alterarPrecoProduto() async {
    if (alterandoPreco) return;

    final mercadoId = SessaoLoja.mercadoId?.trim();

    if (mercadoId == null || mercadoId.isEmpty) {
      mostrarMensagem('Loja atual nao identificada.', erro: true);
      return;
    }

    if (!podeAlterarPreco) {
      mostrarMensagem(
        'Alteracao de preco nao liberada para esta loja.',
        erro: true,
      );
      return;
    }

    var precoDigitado =
        precoAtual?.toStringAsFixed(2).replaceAll('.', ',') ?? '';

    final novoPrecoTexto = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Alterar preco'),
          content: TextFormField(
            initialValue: precoDigitado,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (valor) => precoDigitado = valor,
            onFieldSubmitted: (valor) {
              FocusScope.of(dialogContext).unfocus();
              Navigator.pop(dialogContext, valor.trim());
            },
            decoration: const InputDecoration(
              labelText: 'Novo preco de venda',
              prefixIcon: Icon(Icons.attach_money),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.pop(dialogContext, precoDigitado.trim());
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    if (novoPrecoTexto == null || novoPrecoTexto.trim().isEmpty) return;

    final novoPreco = numeroDecimal(novoPrecoTexto);

    if (novoPreco == null || novoPreco <= 0) {
      mostrarMensagem('Informe um preco valido.', erro: true);
      return;
    }

    setState(() => alterandoPreco = true);

    try {
      await centralService.alterarPrecoProdutoApi(
        mercadoId: mercadoId,
        mercadoCodigo: SessaoLoja.mercadoCodigo,
        produto: {
          'produto_id': texto(produto['produto_id']),
          'ean': eanProduto,
          'codigo_barras': codigoBarrasProduto,
          'nome_produto': nomeProduto,
        },
        preco: novoPreco,
      );

      if (!mounted) return;

      final precoTexto = novoPreco.toStringAsFixed(2);

      setState(() {
        produto['preco_venda'] = precoTexto;
        produto['preco'] = precoTexto;
        produto['valor_venda'] = precoTexto;
        produto['preco_atual'] = precoTexto;
      });

      mostrarMensagem('Preco alterado na API da loja.');
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(
        'Erro ao alterar preco: ${CentralService.mensagemErroUsuario(e)}',
        erro: true,
      );
    } finally {
      if (mounted) {
        setState(() => alterandoPreco = false);
      }
    }
  }

  Widget painelProduto() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: corPrimaria.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nomeProduto,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF172033),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'EAN: ${eanProduto.isEmpty ? '-' : eanProduto}',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Text(
            'Preco atual: ${moeda(precoAtual)}',
            style: TextStyle(color: corPrimaria, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget painelImagem() {
    final url = imagemUrl?.trim() ?? '';

    return Container(
      width: double.infinity,
      height: 330,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: corPrimaria.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: carregando
          ? CircularProgressIndicator(color: corPrimaria)
          : url.isEmpty
          ? Icon(
              Icons.image_not_supported_outlined,
              size: 96,
              color: Colors.grey.shade300,
            )
          : InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.broken_image_outlined,
                    size: 96,
                    color: Colors.grey.shade300,
                  );
                },
              ),
            ),
    );
  }

  Widget statusImagem() {
    final fonte = fonteLegivel(fonteImagem);
    final temImagem = (imagemUrl ?? '').isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: temImagem
            ? corPrimaria.withValues(alpha: 0.07)
            : Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: temImagem
              ? corPrimaria.withValues(alpha: 0.22)
              : Colors.orange.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            temImagem ? Icons.check_circle_outline : Icons.info_outline,
            color: temImagem ? corPrimaria : Colors.orange.shade800,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              temImagem
                  ? 'Imagem carregada de: $fonte'
                  : 'Nenhuma imagem carregada para este produto.',
              style: TextStyle(
                color: temImagem ? corPrimaria : Colors.orange.shade900,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget botoesAcao() {
    final ocupado = carregando || enviando || salvandoUrl || alterandoPreco;
    final botaoEditarImagem = OutlinedButton.icon(
      onPressed: ocupado ? null : mostrarOpcoesEditar,
      icon: enviando || salvandoUrl
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: corPrimaria,
              ),
            )
          : const Icon(Icons.edit_outlined),
      label: Text(
        enviando || salvandoUrl ? 'Salvando...' : 'Editar imagem',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: corPrimaria,
        side: BorderSide(color: corPrimaria.withValues(alpha: 0.55)),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: ocupado ? null : () => carregarImagem(),
            icon: carregando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.image_search_outlined),
            label: Text(
              carregando ? 'Carregando...' : 'Carregar imagem',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: corPrimaria,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (podeAlterarPreco)
          Row(
            children: [
              Expanded(child: botaoEditarImagem),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: ocupado ? null : alterarPrecoProduto,
                  icon: alterandoPreco
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.price_change_outlined),
                  label: Text(
                    alterandoPreco ? 'Alterando...' : 'Alterar preco',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: corPrimaria,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          )
        else
          SizedBox(width: double.infinity, child: botaoEditarImagem),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: corFundo,
      appBar: AppBar(
        title: const Text(
          'Imagem do produto',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: corPrimaria,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            painelProduto(),
            const SizedBox(height: 12),
            painelImagem(),
            const SizedBox(height: 12),
            statusImagem(),
            const SizedBox(height: 14),
            botoesAcao(),
          ],
        ),
      ),
    );
  }
}

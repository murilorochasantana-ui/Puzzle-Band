import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/resumo.dart';
import '../services/app_scope.dart';
import '../services/documentos_android.dart';
import '../services/relatorio.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/relogio.dart';
import '../widgets/cabecalho.dart';
import '../widgets/secao.dart';

/// Abre o menu de compartilhar do Android com o arquivo (WhatsApp, e-mail,
/// Drive...). Os testes trocam por um falso.
typedef Compartilhar = Future<void> Function(File arquivo, String assunto);

const tipoXlsx = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

Future<void> compartilharNoAndroid(File arquivo, String assunto) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile(arquivo.path, mimeType: tipoXlsx)],
    subject: assunto,
    title: assunto,
  ));
}

/// Pasta dos relatorios gerados (cache do app; o proximo relatorio apaga o
/// anterior).
Future<Directory> pastaDosRelatorios() async =>
    Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}relatorios');

/// Aviso mostrado antes de compartilhar (texto pedido no projeto).
const avisoDeDadosDeSaude = 'Este arquivo contém dados de saúde da criança. Compartilhe só com quem cuida dela.';

/// Depois de salvar, sem app que abra planilhas no celular.
const semAppDePlanilhas = 'Para abrir o relatório, instale um app de planilhas, como o Planilhas Google ou o Excel.';

enum _Modo { umDia, periodo }

/// "Exportar relatorio" (Historico e Ajustes): escolhe um dia (padrao:
/// hoje) ou um periodo de ate 31 dias e gera o .xlsx
/// (services/relatorio.dart). Pronto, o tutor salva no celular (janela
/// "Salvar como" do Android) ou compartilha; o aviso de dados de saude vem
/// antes dos dois.
class ExportarRelatorioScreen extends StatefulWidget {
  const ExportarRelatorioScreen({
    super.key,
    this.compartilhar = compartilharNoAndroid,
    this.pasta = pastaDosRelatorios,
    this.documentos = const DocumentosAndroid(),
  });

  final Compartilhar compartilhar;
  final Future<Directory> Function() pasta;
  final DocumentosDoSistema documentos;

  static Future<void> abrir(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ExportarRelatorioScreen()));

  @override
  State<ExportarRelatorioScreen> createState() => _ExportarRelatorioScreenState();
}

class _ExportarRelatorioScreenState extends State<ExportarRelatorioScreen> {
  late final DateTime _hoje = diaDe(relogio());
  _Modo _modo = _Modo.umDia;
  late DateTime _dia = _hoje;
  late DateTime _de = DateTime(_hoje.year, _hoje.month, _hoje.day - 6);
  late DateTime _ate = _hoje;
  bool _gerando = false;
  bool _ocupado = false; // salvando ou compartilhando
  String? _erro;

  /// Relatorio gerado (no cache do app), pronto para salvar ou compartilhar.
  File? _arquivo;
  PeriodoDoRelatorio? _periodoDoArquivo;

  @override
  void dispose() {
    _descartarArquivo();
    super.dispose();
  }

  /// O arquivo nao fica parado no celular: sai ao trocar o periodo e ao sair
  /// da tela (o proximo relatorio tambem limpa a pasta).
  void _descartarArquivo() {
    final arquivo = _arquivo;
    _arquivo = null;
    _periodoDoArquivo = null;
    if (arquivo == null) return;
    try {
      if (arquivo.existsSync()) arquivo.deleteSync();
    } catch (_) {}
  }

  /// Mudou o dia ou o periodo: o relatorio pronto deixa de valer.
  void _mudar(VoidCallback mudanca) => setState(() {
        mudanca();
        _erro = null;
        _descartarArquivo();
      });

  /// Dias do calendario de [_de] a [_ate] (em UTC: dia com mudanca de
  /// horario continua contando 1).
  int get _diasDoPeriodo =>
      DateTime.utc(_ate.year, _ate.month, _ate.day).difference(DateTime.utc(_de.year, _de.month, _de.day)).inDays + 1;

  String? get _problema {
    if (_modo == _Modo.umDia) return null;
    if (_ate.isBefore(_de)) return 'O início precisa vir antes do fim.';
    if (_diasDoPeriodo > maxDiasDoRelatorio) return 'Escolha no máximo $maxDiasDoRelatorio dias ($_diasDoPeriodo escolhidos).';
    return null;
  }

  PeriodoDoRelatorio get _periodo => _modo == _Modo.umDia ? PeriodoDoRelatorio.dia(_dia) : PeriodoDoRelatorio(_de, _ate);

  Future<void> _gerar() async {
    final service = AppScope.read(context);
    setState(() {
      _gerando = true;
      _erro = null;
    });
    File? arquivo;
    try {
      final dados = await DadosDoRelatorio.doBanco(
        service.banco,
        periodo: _periodo,
        childId: service.config.childId,
        agora: relogio(),
      );
      arquivo = await gravarRelatorio(dados, await widget.pasta());
    } catch (e) {
      debugPrint('Falha ao gerar o relatorio: $e');
      if (mounted) setState(() => _erro = 'Não foi possível gerar o arquivo. Tente de novo.');
    }
    if (!mounted) return;
    setState(() {
      _gerando = false;
      if (arquivo != null) {
        _arquivo = arquivo;
        _periodoDoArquivo = _periodo;
      }
    });
  }

  /// O aviso de dados de saude, antes de salvar e antes de compartilhar.
  Future<bool> _confirmarAviso(String acao) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.health_and_safety_outlined),
        title: Text('Antes de ${acao.toLowerCase()}'),
        content: const Text(avisoDeDadosDeSaude),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(acao)),
        ],
      ),
    );
    return ok == true && mounted;
  }

  /// "Salvar no celular": aviso -> janela "Salvar como" do Android -> "Relatorio
  /// salvo" com "Abrir". Cancelar a janela nao mostra nada.
  Future<void> _salvar() async {
    final arquivo = _arquivo;
    if (arquivo == null || _ocupado) return;
    final confirmou = await _confirmarAviso('Salvar');
    if (!confirmou || !mounted) return;
    final mensageiro = ScaffoldMessenger.of(context);
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    String? uri;
    try {
      uri = await widget.documentos.salvarComo(arquivo, nome: arquivo.uri.pathSegments.last, tipo: tipoXlsx);
    } catch (e) {
      debugPrint('Falha ao salvar o relatorio: $e');
      if (mounted) setState(() => _erro = 'Não foi possível salvar o arquivo. Tente de novo.');
    }
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (uri == null) return; // cancelou a janela (ou ja havia uma aberta)
    final salvo = uri;
    mensageiro
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Relatório salvo'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(label: 'Abrir', onPressed: () => _abrirSalvo(mensageiro, salvo)),
      ));
  }

  Future<void> _abrirSalvo(ScaffoldMessengerState mensageiro, String uri) async {
    final abriu = await widget.documentos.abrir(uri, tipo: tipoXlsx);
    if (abriu) return;
    mensageiro
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(semAppDePlanilhas), duration: Duration(seconds: 8)));
  }

  /// "Compartilhar": aviso -> menu de compartilhar do Android.
  Future<void> _compartilhar() async {
    final arquivo = _arquivo;
    final periodo = _periodoDoArquivo;
    if (arquivo == null || periodo == null || _ocupado || !await _confirmarAviso('Compartilhar')) return;
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await widget.compartilhar(arquivo, 'Puzzle Band: relatório de ${_descricao(periodo)}');
    } catch (e) {
      debugPrint('Falha ao compartilhar o relatorio: $e');
      if (mounted) setState(() => _erro = 'Não foi possível abrir o menu de compartilhar.');
    }
    if (mounted) setState(() => _ocupado = false);
  }

  String _descricao(PeriodoDoRelatorio p) => p.umDia
      ? _rotuloDoDia(p.primeiro)
      : '${_rotuloDoDia(p.primeiro)} a ${_rotuloDoDia(p.ultimo)}';

  String _rotuloDoDia(DateTime d) => '${diaPorExtenso(d)} de ${d.year}';

  void _atalho(DateTime de, DateTime ate) => _mudar(() {
        _modo = _Modo.periodo;
        _de = de;
        _ate = ate;
      });

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final cores = CoresApp.of(context);
    final problema = _problema;
    final dias = _modo == _Modo.umDia ? 1 : _diasDoPeriodo;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const CabecalhoVoltar(titulo: 'Exportar relatório'),
            Expanded(
              child: CorpoTela(
                children: [
                  Text(
                    'Uma planilha do Excel (.xlsx) com as crises do dia e as médias dos sinais '
                    'antes, durante e depois de cada uma, para levar à consulta ou à escola.',
                    style: texto.bodyMedium!.copyWith(color: cores.tintaSuave),
                  ),
                  const SizedBox(height: Espaco.l),
                  SegmentedButton<_Modo>(
                    key: const ValueKey('modo-relatorio'),
                    segments: const [
                      ButtonSegment(value: _Modo.umDia, label: Text('Um dia'), icon: Icon(Icons.today_outlined)),
                      ButtonSegment(value: _Modo.periodo, label: Text('Período'), icon: Icon(Icons.date_range_outlined)),
                    ],
                    selected: {_modo},
                    onSelectionChanged: (s) => _mudar(() => _modo = s.single),
                  ),
                  const SizedBox(height: Espaco.m),
                  Secao(
                    padding: const EdgeInsets.symmetric(vertical: Espaco.s),
                    child: Column(
                      children: [
                        if (_modo == _Modo.umDia)
                          _SeletorDeDia(
                            chave: 'dia',
                            rotulo: 'Dia',
                            valor: _dia,
                            hoje: _hoje,
                            onMudar: (d) => _mudar(() => _dia = d),
                          )
                        else ...[
                          _SeletorDeDia(
                            chave: 'de',
                            rotulo: 'De',
                            valor: _de,
                            hoje: _hoje,
                            onMudar: (d) => _mudar(() => _de = d),
                          ),
                          const Divider(indent: Espaco.l, endIndent: Espaco.l),
                          _SeletorDeDia(
                            chave: 'ate',
                            rotulo: 'Até',
                            valor: _ate,
                            hoje: _hoje,
                            onMudar: (d) => _mudar(() => _ate = d),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: Espaco.s),
                  Wrap(
                    spacing: Espaco.s,
                    runSpacing: Espaco.s,
                    children: [
                      ActionChip(
                        label: const Text('Hoje'),
                        onPressed: () => _mudar(() {
                          _modo = _Modo.umDia;
                          _dia = _hoje;
                        }),
                      ),
                      ActionChip(
                        label: const Text('Ontem'),
                        onPressed: () => _mudar(() {
                          _modo = _Modo.umDia;
                          _dia = DateTime(_hoje.year, _hoje.month, _hoje.day - 1);
                        }),
                      ),
                      ActionChip(
                        label: const Text('Últimos 7 dias'),
                        onPressed: () => _atalho(DateTime(_hoje.year, _hoje.month, _hoje.day - 6), _hoje),
                      ),
                      ActionChip(
                        label: const Text('Últimos 31 dias'),
                        onPressed: () => _atalho(DateTime(_hoje.year, _hoje.month, _hoje.day - 30), _hoje),
                      ),
                    ],
                  ),
                  if (problema != null) ...[
                    const SizedBox(height: Espaco.s),
                    Semantics(
                      liveRegion: true,
                      child: Text(problema, style: texto.bodyMedium!.copyWith(color: Theme.of(context).colorScheme.error)),
                    ),
                  ],
                  const SizedBox(height: Espaco.l),
                  Secao(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Linha(icone: Icons.table_chart_outlined, texto: 'Três abas: Resumo do dia, Episódios e Por hora.'),
                        const SizedBox(height: Espaco.s),
                        _Linha(icone: Icons.schedule_outlined, texto: 'Horários no fuso deste celular.'),
                        const SizedBox(height: Espaco.s),
                        _Linha(
                          icone: Icons.lock_outline_rounded,
                          texto: 'O arquivo é gerado neste celular. Salve numa pasta (como Downloads) ou compartilhe.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Espaco.l),
                  if (_arquivo case final arquivo?)
                    _RelatorioPronto(
                      nome: arquivo.uri.pathSegments.last,
                      ocupado: _ocupado,
                      onSalvar: _salvar,
                      onCompartilhar: _compartilhar,
                    )
                  else
                    FilledButton.icon(
                      key: const ValueKey('gerar-relatorio'),
                      onPressed: _gerando || problema != null ? null : _gerar,
                      icon: _gerando
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : const Icon(Icons.table_chart_outlined),
                      label: Text(_gerando
                          ? 'Gerando…'
                          : dias == 1
                              ? 'Gerar relatório'
                              : 'Gerar relatório ($dias dias)'),
                    ),
                  if (_erro != null) ...[
                    const SizedBox(height: Espaco.s),
                    Semantics(
                      liveRegion: true,
                      child: Text(_erro!, style: texto.bodyMedium!.copyWith(color: Theme.of(context).colorScheme.error)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Relatorio pronto": o nome do arquivo e os dois botoes (salvar e
/// compartilhar; o aviso vem antes de cada um).
class _RelatorioPronto extends StatelessWidget {
  const _RelatorioPronto({required this.nome, required this.ocupado, required this.onSalvar, required this.onCompartilhar});

  final String nome;
  final bool ocupado;
  final VoidCallback onSalvar;
  final VoidCallback onCompartilhar;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final cores = CoresApp.of(context);
    return Secao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: cores.primaria),
                const SizedBox(width: Espaco.s),
                Expanded(child: Text('Relatório pronto', style: texto.titleMedium)),
              ],
            ),
          ),
          const SizedBox(height: Espaco.xs),
          Text(nome, style: texto.bodySmall!.copyWith(color: cores.tintaSuave)),
          const SizedBox(height: Espaco.m),
          FilledButton.icon(
            key: const ValueKey('salvar-relatorio'),
            onPressed: ocupado ? null : onSalvar,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Salvar no celular'),
          ),
          const SizedBox(height: Espaco.s),
          OutlinedButton.icon(
            key: const ValueKey('compartilhar-relatorio'),
            onPressed: ocupado ? null : onCompartilhar,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Compartilhar'),
          ),
        ],
      ),
    );
  }
}

/// Icone + frase curta.
class _Linha extends StatelessWidget {
  const _Linha({required this.icone, required this.texto});

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 20, color: CoresApp.of(context).tintaSuave),
        const SizedBox(width: Espaco.m),
        Expanded(child: Text(texto, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}

/// "Dia: Hoje, 25 de novembro de 2026" com setas para o dia anterior e o
/// seguinte (sem passar de hoje). Sem o seletor de data do sistema: ele viria
/// em ingles (o app nao carrega as traducoes do Flutter).
class _SeletorDeDia extends StatelessWidget {
  const _SeletorDeDia({required this.chave, required this.rotulo, required this.valor, required this.hoje, required this.onMudar});

  final String chave;
  final String rotulo;
  final DateTime valor;
  final DateTime hoje;
  final ValueChanged<DateTime> onMudar;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final ontem = DateTime(hoje.year, hoje.month, hoje.day - 1);
    final relativo = mesmoDia(valor, hoje)
        ? 'Hoje, '
        : mesmoDia(valor, ontem)
            ? 'Ontem, '
            : '${dataCurta(valor).split(',').first}, ';
    final legivel = '$relativo${diaPorExtenso(valor)} de ${valor.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Espaco.s),
      child: Row(
        children: [
          IconButton(
            key: ValueKey('$chave-anterior'),
            tooltip: 'Dia anterior',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => onMudar(DateTime(valor.year, valor.month, valor.day - 1)),
          ),
          Expanded(
            child: Semantics(
              label: '$rotulo: $legivel',
              excludeSemantics: true,
              child: Column(
                children: [
                  Text(rotulo, style: texto.labelMedium!.copyWith(color: CoresApp.of(context).tintaSuave)),
                  Text(legivel, key: ValueKey('$chave-valor'), style: texto.titleMedium, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
          IconButton(
            key: ValueKey('$chave-seguinte'),
            tooltip: 'Dia seguinte',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: mesmoDia(valor, hoje) || valor.isAfter(hoje)
                ? null
                : () => onMudar(DateTime(valor.year, valor.month, valor.day + 1)),
          ),
        ],
      ),
    );
  }
}

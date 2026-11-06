// Lembretes do cuidador (de um episodio ou do dia): a linha que mostra o
// lembrete e o editor (folha inferior). Ficam so neste celular
// (services/preferencias_locais.dart): nao vao para o MQTT nem para o site.

import 'package:flutter/material.dart';

import '../services/preferencias_locais.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/relogio.dart';

/// Icone + "Lembrete: texto" + o aviso, se ainda vai tocar.
class LinhaLembrete extends StatelessWidget {
  const LinhaLembrete({super.key, required this.lembrete, required this.agora, this.rotulo = 'Lembrete'});

  final Lembrete lembrete;
  final DateTime agora;
  final String rotulo;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final aviso = lembrete.avisoPendente(agora);
    final fraseAviso = aviso != null ? 'O celular avisa ${quandoEm(aviso, agora)}.' : null;
    return Semantics(
      container: true,
      label: '$rotulo: ${lembrete.texto}.${fraseAviso != null ? ' $fraseAviso' : ''}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.sticky_note_2_outlined, size: 20, color: cores.tintaSuave),
          ),
          const SizedBox(width: Espaco.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$rotulo: ${lembrete.texto}', style: texto.bodyMedium),
                if (fraseAviso != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.alarm_rounded, size: 16, color: cores.tintaSuave),
                      const SizedBox(width: Espaco.xs),
                      Expanded(child: Text(fraseAviso, style: texto.bodySmall)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Abre o editor do lembrete [chave] e, ao fechar, diz o que aconteceu.
Future<void> editarLembrete(
  BuildContext context, {
  required String chave,
  required String titulo,
  required String tituloDoAviso,
}) async {
  final mensageiro = ScaffoldMessenger.of(context);
  final preferencias = PreferenciasScope.read(context);
  final resultado = await showModalBottomSheet<ResultadoLembrete>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: Movimento.reduzido(context) ? AnimationStyle.noAnimation : null,
    builder: (_) => _EditorLembrete(chave: chave, titulo: titulo, tituloDoAviso: tituloDoAviso),
  );
  if (resultado == null) return;
  final aviso = preferencias.lembrete(chave)?.avisoPendente(relogio());
  final frase = switch (resultado) {
    ResultadoLembrete.salvo => 'Lembrete salvo neste celular.',
    ResultadoLembrete.salvoComAviso =>
      aviso != null ? 'Lembrete salvo. O celular avisa ${quandoEm(aviso, relogio())}.' : 'Lembrete salvo neste celular.',
    ResultadoLembrete.avisoFalhou =>
      'Lembrete salvo, mas este aparelho não conseguiu agendar o aviso. Confira se as notificações do app estão ligadas.',
    ResultadoLembrete.apagado => 'Lembrete apagado.',
  };
  mensageiro
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(frase)));
}

class _EditorLembrete extends StatefulWidget {
  const _EditorLembrete({required this.chave, required this.titulo, required this.tituloDoAviso});

  final String chave;
  final String titulo;
  final String tituloDoAviso;

  @override
  State<_EditorLembrete> createState() => _EditorLembreteState();
}

class _EditorLembreteState extends State<_EditorLembrete> {
  late final PreferenciasLocais _preferencias;
  late final Lembrete? _atual;
  late final TextEditingController _texto;
  DateTime? _avisarEm;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _preferencias = PreferenciasScope.read(context);
    _atual = _preferencias.lembrete(widget.chave);
    _texto = TextEditingController(text: _atual?.texto ?? '');
    _avisarEm = _atual?.avisoPendente(relogio());
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _escolherHorario() async {
    final agora = relogio();
    final inicial = _avisarEm ?? agora.add(const Duration(hours: 1));
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(inicial),
      helpText: 'Avisar às',
      cancelText: 'Cancelar',
      confirmText: 'Definir',
      hourLabelText: 'Hora',
      minuteLabelText: 'Minuto',
      errorInvalidText: 'Horário inválido',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (hora == null || !mounted) return;
    // Horario que ja passou hoje: avisa amanha.
    var quando = DateTime(agora.year, agora.month, agora.day, hora.hour, hora.minute);
    if (!quando.isAfter(agora)) quando = DateTime(agora.year, agora.month, agora.day + 1, hora.hour, hora.minute);
    setState(() => _avisarEm = quando);
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    final resultado = await _preferencias.salvarLembrete(
      widget.chave,
      _texto.text,
      avisarEm: _avisarEm,
      tituloDoAviso: widget.tituloDoAviso,
    );
    if (!mounted) return;
    Navigator.of(context).pop(_atual == null && resultado == ResultadoLembrete.apagado ? null : resultado);
  }

  Future<void> _apagar() async {
    setState(() => _salvando = true);
    await _preferencias.apagarLembrete(widget.chave);
    if (!mounted) return;
    Navigator.of(context).pop(ResultadoLembrete.apagado);
  }

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final aviso = _avisarEm;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Espaco.tela, 0, Espaco.tela, Espaco.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text(widget.titulo, style: texto.titleMedium)),
            const SizedBox(height: Espaco.xs),
            Text('Fica salvo só neste celular. Não vai para o painel (site).', style: texto.bodySmall),
            const SizedBox(height: Espaco.l),
            TextField(
              controller: _texto,
              autofocus: _atual == null,
              maxLength: PreferenciasLocais.maxLembrete,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Lembrete',
                hintText: 'Ex.: levar o abafador de ruído amanhã',
              ),
            ),
            const SizedBox(height: Espaco.xs),
            Row(
              children: [
                Icon(Icons.alarm_rounded, color: cores.tintaSuave),
                const SizedBox(width: Espaco.s),
                Expanded(
                  child: Text(
                    aviso != null ? 'O celular avisa ${quandoEm(aviso, relogio())}.' : 'Sem aviso no celular.',
                    style: texto.bodyMedium,
                  ),
                ),
                TextButton(
                  onPressed: _salvando ? null : _escolherHorario,
                  child: Text(aviso == null ? 'Escolher horário' : 'Mudar horário'),
                ),
                if (aviso != null)
                  IconButton(
                    onPressed: _salvando ? null : () => setState(() => _avisarEm = null),
                    tooltip: 'Tirar o aviso',
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            const SizedBox(height: Espaco.l),
            FilledButton.icon(
              onPressed: _salvando ? null : _salvar,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Salvar lembrete'),
            ),
            if (_atual != null) ...[
              const SizedBox(height: Espaco.s),
              OutlinedButton.icon(
                onPressed: _salvando ? null : _apagar,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Apagar lembrete'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

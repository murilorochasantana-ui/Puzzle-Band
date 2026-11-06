import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_scope.dart';
import '../services/preferencias_locais.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/relogio.dart';
import '../widgets/cabecalho.dart';
import '../widgets/cartao_episodio.dart';
import '../widgets/estado_vazio.dart';
import '../widgets/lembrete.dart';
import '../widgets/painel_do_dia.dart';
import '../widgets/secao.dart';

/// Detalhe de um episodio, aberto pelo painel do dia (ou pelo cartao "Nenhum
/// episódio agora") da tela Inicio: o mesmo cartao do Historico, com
/// "Confirmar gatilho" e "Descartar", e o lembrete do cuidador.
class EpisodioScreen extends StatelessWidget {
  const EpisodioScreen({super.key, required this.episodioId});

  final String episodioId;

  static Future<void> abrir(BuildContext context, String episodioId) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EpisodioScreen(episodioId: episodioId)));

  @override
  Widget build(BuildContext context) {
    final service = AppScope.of(context);
    final agora = relogio();
    Episodio? ep;
    for (final e in service.historico) {
      if (e.id == episodioId) ep = e;
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            CabecalhoVoltar(titulo: ep != null ? 'Episódio de ${quandoEm(ep.inicio, agora)}' : 'Episódio'),
            Expanded(
              child: CorpoTela(
                children: ep == null
                    ? const [
                        Secao(
                          child: EstadoVazio(
                            icone: Icons.history_rounded,
                            titulo: 'Episódio fora do histórico',
                            texto: 'O painel (site) não mandou mais este episódio. '
                                'Ele pode ter sido apagado em "Limpar histórico".',
                          ),
                        ),
                      ]
                    : [
                        Text(horarioDoEpisodio(ep), style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: Espaco.m),
                        CartaoEpisodio(key: ValueKey(ep.id), episodio: ep, agora: agora),
                        const SizedBox(height: Espaco.l),
                        _SecaoLembrete(ep: ep, agora: agora),
                      ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lembrete do episodio: mostra, adiciona, edita e apaga. So neste celular.
class _SecaoLembrete extends StatelessWidget {
  const _SecaoLembrete({required this.ep, required this.agora});

  final Episodio ep;
  final DateTime agora;

  @override
  Widget build(BuildContext context) {
    final preferencias = PreferenciasScope.of(context);
    final chave = PreferenciasLocais.chaveEpisodio(ep.id);
    final lembrete = preferencias.lembrete(chave);

    void editar() => editarLembrete(
          context,
          chave: chave,
          titulo: 'Lembrete deste episódio',
          tituloDoAviso: 'Lembrete do episódio das ${horaMinuto(ep.inicio)}',
        );

    Future<void> apagar() async {
      final mensageiro = ScaffoldMessenger.of(context);
      await preferencias.apagarLembrete(chave);
      mensageiro
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Lembrete apagado.')));
    }

    return Secao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TituloSecao('Lembrete', apoio: 'Fica salvo só neste celular. Não vai para o painel (site).'),
          const SizedBox(height: Espaco.m),
          if (lembrete == null)
            OutlinedButton.icon(
              onPressed: editar,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adicionar lembrete'),
            )
          else ...[
            LinhaLembrete(lembrete: lembrete, agora: agora),
            const SizedBox(height: Espaco.s),
            Wrap(
              spacing: Espaco.s,
              children: [
                TextButton.icon(
                  onPressed: editar,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar lembrete'),
                ),
                TextButton.icon(
                  onPressed: apagar,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Apagar lembrete'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

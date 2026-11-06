import 'package:flutter/material.dart';

import '../services/app_scope.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/relogio.dart';
import '../widgets/cabecalho.dart';
import '../widgets/cartao_episodio.dart';
import '../widgets/estado_vazio.dart';
import '../widgets/secao.dart';

/// Episodios recebidos do site (`puzzleband/<id>/historico`). O cuidador
/// confirma ou descarta o gatilho, com uma observacao curta, e o app publica
/// em `puzzleband/<id>/avaliacao` (widgets/cartao_episodio.dart). A ultima
/// copia fica salva para ver offline.
class HistoricoScreen extends StatelessWidget {
  const HistoricoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = AppScope.of(context);
    final episodios = service.historico;
    final agora = relogio();
    return EstruturaTela(
      children: [
        const TituloTela(
          'Histórico',
          apoio: 'Episódios detectados pelo painel. Confirme ou descarte o provável gatilho.',
        ),
        const SizedBox(height: Espaco.m),
        _FonteDosDados(service: service),
        const SizedBox(height: Espaco.l),
        if (episodios.isEmpty)
          const Secao(
            child: EstadoVazio(
              icone: Icons.history_rounded,
              titulo: 'Nenhum episódio ainda',
              texto: 'Quando o painel (site) detectar sinais de atenção ou de possível crise, '
                  'o episódio aparece aqui para você avaliar.',
            ),
          )
        else
          for (final ep in episodios) ...[
            CartaoEpisodio(key: ValueKey(ep.id), episodio: ep, agora: agora),
            const SizedBox(height: Espaco.m),
          ],
      ],
    );
  }
}

/// De onde vem a lista: ao vivo ou a copia salva no celular.
class _FonteDosDados extends StatelessWidget {
  const _FonteDosDados({required this.service});

  final MqttService service;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final aoVivo = service.historicoAoVivo;
    final recebido = service.historicoRecebidoEm;
    final String frase;
    if (aoVivo) {
      frase = 'Atualizado pelo painel${recebido != null ? ' às ${horaMinuto(recebido)}' : ''}.';
    } else if (recebido != null) {
      frase = 'Sem conexão: mostrando a última cópia salva, de ${diaHora(recebido)}.';
    } else {
      frase = 'Sem conexão e sem cópia salva ainda.';
    }
    return Row(
      children: [
        Icon(aoVivo ? Icons.sync_rounded : Icons.cloud_off_outlined,
            size: 20, color: aoVivo ? cores.primaria : cores.tinta),
        const SizedBox(width: Espaco.s),
        Expanded(
          child: Text(
            frase,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: aoVivo ? cores.tintaSuave : cores.tinta,
                  fontWeight: aoVivo ? FontWeight.w400 : FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

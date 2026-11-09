import 'package:flutter/material.dart';

import 'configurar_alertas_screen.dart';
import '../models/resumo.dart';
import '../services/app_scope.dart';
import '../services/preferencias_locais.dart';
import '../theme/app_theme.dart';
import '../utils/relogio.dart';
import '../widgets/cabecalho.dart';
import '../widgets/cartao_episodio_ativo.dart';
import '../widgets/cartao_sem_episodio.dart';
import '../widgets/connection_bar.dart';
import '../widgets/faixa_estado.dart';
import '../widgets/linha_probabilidade.dart';
import '../widgets/painel_do_dia.dart';
import 'episodio_screen.dart';

/// Inicio, na ordem do modelo do Figma (docs/figma/home.md): nome da
/// crianca, conexao, faixa de estado (nivel + BPM), cartao do episodio (ou
/// "Nenhum episódio agora" com o ultimo episodio), probabilidade e o painel
/// "Hoje" com os episodios do dia e os lembretes.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = AppScope.of(context);
    final preferencias = PreferenciasScope.of(context);
    final agora = relogio();
    // O historico ja vem do mais recente para o mais antigo.
    final hoje = [for (final e in service.historico) if (mesmoDia(e.inicio, agora)) e];
    final estado = service.estado;
    final aoVivo = situacaoDe(service) == SituacaoEstado.aoVivo && estado != null;
    final ativo = service.episodioAtivo;

    void abrirEpisodio(String id) => EpisodioScreen.abrir(context, id);

    return EstruturaTela(
      titulo: preferencias.nomeCrianca,
      children: [
        // Alertas com o app fechado desativados - Corrigir (some quando ok)
        const AvisoMonitoramento(),
        ConnectionBar(service: service),
        const SizedBox(height: Espaco.m),
        FaixaEstado(service: service),
        if (aoVivo) ...[
          const SizedBox(height: Espaco.bloco),
          if (ativo != null)
            CartaoEpisodioAtivo(
              key: const ValueKey('episodio-ativo'),
              service: service,
              ativo: ativo,
              estado: estado,
              onCiente: (id) => _confirmarCiente(context, id),
            )
          else
            CartaoSemEpisodio(
              ultimo: service.historico.isEmpty ? null : service.historico.first,
              agora: agora,
              onAbrir: abrirEpisodio,
            ),
          const SizedBox(height: Espaco.bloco),
          LinhaProbabilidade(estado: estado),
          const SizedBox(height: Espaco.m),
        ] else
          const SizedBox(height: Espaco.bloco),
        PainelDoDia(episodios: hoje, agora: agora, onAbrirEpisodio: abrirEpisodio),
      ],
    );
  }

  static bool _confirmarCiente(BuildContext context, String episodioId) {
    final enviado = AppScope.read(context).enviarCiente(episodioId);
    if (!enviado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem conexão com o servidor: o aviso não foi enviado. Tente de novo em instantes.')),
      );
    }
    return enviado;
  }
}

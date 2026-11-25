import 'dart:math';

import 'package:flutter/material.dart';

import '../models/resumo.dart';
import '../services/app_scope.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/relogio.dart';
import '../widgets/cabecalho.dart';
import '../widgets/calendario_crises.dart';
import '../widgets/cartao_episodio_resumido.dart';
import '../widgets/estado_vazio.dart';
import '../widgets/secao.dart';
import 'exportar_relatorio_screen.dart';

/// Episodios recebidos da pulseira (`puzzleband/<id>/historico`) e guardados
/// no banco local (todos, nao so os 50 que a pulseira publica), separados por
/// dia, com o calendario do mes no topo. O calendario conta pela avaliacao
/// do cuidador (widgets/calendario_crises.dart) e le o mes mostrado do
/// banco; tocar num dia filtra a lista (consulta do dia). A lista carrega
/// 50 episodios por vez, mais ao chegar ao fim. Cada cartao e resumido e
/// expande no lugar para confirmar ou descartar o gatilho
/// (widgets/cartao_episodio_resumido.dart). Tudo continua visivel offline.
class HistoricoScreen extends StatefulWidget {
  const HistoricoScreen({super.key});

  @override
  State<HistoricoScreen> createState() => _HistoricoScreenState();
}

class _HistoricoScreenState extends State<HistoricoScreen> {
  late DateTime _mes = DateTime(relogio().year, relogio().month);
  bool _calendarioAberto = true;
  DateTime? _escolhido;
  String? _expandido;
  final _chaveBotoes = GlobalKey();

  void _escolherDia(DateTime dia) {
    setState(() => _escolhido = _escolhido != null && mesmoDia(_escolhido!, dia) ? null : dia);
  }

  void _alternar(String id) => setState(() => _expandido = _expandido == id ? null : id);

  /// Selo "Possível crise · a confirmar": abre o cartao e rola ate os botoes.
  void _abrirNosBotoes(String id) {
    setState(() => _expandido = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contexto = _chaveBotoes.currentContext;
      final botoes = contexto?.findRenderObject();
      if (contexto == null || botoes is! RenderBox || !mounted) return;
      // Rola o minimo para os botoes aparecerem inteiros. A conta e feita a
      // mao: dentro de SliverMainAxisGroup com cabecalho fixo, o
      // ensureVisible do Flutter erra pela altura do cabecalho.
      final rolagem = Scrollable.of(contexto);
      final janela = rolagem.context.findRenderObject()! as RenderBox;
      final fundoDosBotoes = botoes.localToGlobal(Offset(0, botoes.size.height)).dy;
      final fundoDaJanela = janela.localToGlobal(Offset(0, janela.size.height)).dy - Espaco.l;
      final posicao = rolagem.position;
      if (fundoDosBotoes <= fundoDaJanela) return;
      final destino = min(posicao.pixels + fundoDosBotoes - fundoDaJanela, posicao.maxScrollExtent);
      final duracao = Movimento.de(context, Movimento.medio);
      if (duracao == Duration.zero) {
        posicao.jumpTo(destino);
      } else {
        posicao.animateTo(destino, duration: duracao, curve: Movimento.curva);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = AppScope.of(context);
    final agora = relogio();
    final historico = service.historicoLocal;
    final contagens = historico.contagensDoMes(_mes);
    var primeiroMes = DateTime(agora.year, agora.month);
    final primeiro = historico.primeiroInicio;
    if (primeiro != null && DateTime(primeiro.year, primeiro.month).isBefore(primeiroMes)) {
      primeiroMes = DateTime(primeiro.year, primeiro.month);
    }
    final escolhido = _escolhido;
    final grupos = episodiosPorDia(escolhido == null ? historico.recentes : historico.doDia(escolhido));
    final carregarMais = escolhido == null && historico.temMais;

    final topo = <Widget>[
      const TituloTela(
        'Histórico',
        apoio: 'Episódios detectados pela pulseira, por dia. Toque num episódio para confirmar ou descartar.',
      ),
      const SizedBox(height: Espaco.m),
      _FonteDosDados(service: service),
      const SizedBox(height: Espaco.m),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey('historico-exportar-relatorio'),
          onPressed: () => ExportarRelatorioScreen.abrir(context),
          icon: const Icon(Icons.table_chart_outlined),
          label: const Text('Exportar relatório'),
        ),
      ),
      const SizedBox(height: Espaco.l),
      if (!historico.vazio) ...[
        CalendarioCrises(
          mes: _mes,
          contagens: contagens,
          hoje: agora,
          escolhido: escolhido,
          aberto: _calendarioAberto,
          primeiroMes: primeiroMes,
          onMes: (mes) => setState(() => _mes = mes),
          onDia: _escolherDia,
          onAlternar: () => setState(() => _calendarioAberto = !_calendarioAberto),
        ),
        const SizedBox(height: Espaco.m),
      ],
      if (escolhido != null) ...[
        _Filtro(dia: escolhido, onLimpar: () => setState(() => _escolhido = null)),
        const SizedBox(height: Espaco.s),
      ],
      if (historico.vazio)
        const Secao(
          child: EstadoVazio(
            icone: Icons.history_rounded,
            titulo: 'Nenhum episódio ainda',
            texto: 'Quando a pulseira detectar sinais de atenção ou de possível crise, '
                'o episódio aparece aqui para você avaliar.',
          ),
        )
      else if (grupos.isEmpty)
        Secao(
          child: EstadoVazio(
            icone: Icons.event_available_rounded,
            titulo: 'Nenhum episódio em ${diaPorExtenso(escolhido!)}',
            texto: 'Escolha outro dia no calendário ou toque em "Ver todos".',
          ),
        ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Cabecalho(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, restricoes) {
                  // Margem da tela e largura maxima do conteudo (como CorpoTela)
                  final lateral = max(Espaco.tela, (restricoes.maxWidth - Espaco.larguraMaxima) / 2);
                  return CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(lateral, Espaco.s, lateral, Espaco.xxl),
                        sliver: SliverMainAxisGroup(
                          slivers: [
                            SliverList.list(children: topo),
                            for (final (dia, doDia) in grupos)
                              SliverMainAxisGroup(
                                slivers: [
                                  PinnedHeaderSliver(child: _CabecalhoDia(dia: dia, total: doDia.length, agora: agora)),
                                  SliverList.builder(
                                    itemCount: doDia.length,
                                    itemBuilder: (context, i) {
                                      final ep = doDia[i];
                                      final aberto = _expandido == ep.id;
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: Espaco.s),
                                        child: CartaoEpisodioResumido(
                                          key: ValueKey(ep.id),
                                          episodio: ep,
                                          expandido: aberto,
                                          chaveBotoes: aberto ? _chaveBotoes : null,
                                          onAlternar: () => _alternar(ep.id),
                                          onConfirmar: () => _abrirNosBotoes(ep.id),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            if (carregarMais)
                              SliverToBoxAdapter(
                                child: _MaisAntigos(key: ValueKey(historico.recentes.length), onVisivel: historico.carregarMais),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cabecalho de um dia na lista ("Hoje", "Ontem", "Seg, 3 de nov."), fixo
/// no topo enquanto os episodios do dia passam.
class _CabecalhoDia extends StatelessWidget {
  const _CabecalhoDia({required this.dia, required this.total, required this.agora});

  final DateTime dia;
  final int total;
  final DateTime agora;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final texto = Theme.of(context).textTheme;
    final hoje = diaDe(agora);
    final diferenca = (hoje.difference(dia).inHours / 24).round(); // round: dias de 23/25 h
    final rotulo = switch (diferenca) {
      0 => 'Hoje',
      1 => 'Ontem',
      _ => dataCurta(dia, agora: agora),
    };
    return Container(
      color: cores.fundo,
      padding: const EdgeInsets.fromLTRB(Espaco.xs, Espaco.m, Espaco.xs, Espaco.s),
      child: Semantics(
        header: true,
        label: '$rotulo${diferenca > 1 ? '' : ', ${diaPorExtenso(dia)}'}: ${contarEpisodios(total)}',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(rotulo, style: texto.titleMedium)),
            const SizedBox(width: Espaco.s),
            Text(contarEpisodios(total), style: texto.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Fim da lista com episodios mais antigos no banco: ao aparecer na tela
/// (rolou ate aqui), pede a proxima pagina.
class _MaisAntigos extends StatefulWidget {
  const _MaisAntigos({super.key, required this.onVisivel});

  final VoidCallback onVisivel;

  @override
  State<_MaisAntigos> createState() => _MaisAntigosState();
}

class _MaisAntigosState extends State<_MaisAntigos> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onVisivel();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espaco.m),
      child: Text(
        'Carregando episódios mais antigos…',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

/// "Mostrando só 3 de novembro." + "Ver todos".
class _Filtro extends StatelessWidget {
  const _Filtro({required this.dia, required this.onLimpar});

  final DateTime dia;
  final VoidCallback onLimpar;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    return Container(
      padding: const EdgeInsets.only(left: Espaco.m),
      decoration: BoxDecoration(color: cores.primariaSuave, borderRadius: BorderRadius.circular(Raio.controle)),
      child: Row(
        children: [
          Icon(Icons.filter_alt_outlined, size: 20, color: cores.sobrePrimariaSuave),
          const SizedBox(width: Espaco.s),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Mostrando só ${diaPorExtenso(dia)}.',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: cores.sobrePrimariaSuave),
              ),
            ),
          ),
          TextButton(
            onPressed: onLimpar,
            style: TextButton.styleFrom(foregroundColor: cores.sobrePrimariaSuave),
            child: const Text('Ver todos'),
          ),
        ],
      ),
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
      frase = 'Atualizado pela pulseira${recebido != null ? ' às ${horaMinuto(recebido)}' : ''}.';
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

import 'dart:math';

import 'package:flutter/material.dart';

import '../models/resumo.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'secao.dart';

const _semana = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

/// Frase do dia para o leitor de tela: "3 de novembro: 4 crises
/// confirmadas" / "5 de novembro: 2 possíveis crises aguardando
/// confirmação" / "4 de novembro: nenhuma crise".
String falaDoDia(DateTime dia, ContagemDia c, {required bool hoje}) {
  final partes = [
    if (c.confirmadas > 0) contarConfirmadas(c.confirmadas),
    if (c.pendentes > 0) contarPendentes(c.pendentes),
  ];
  final resumo = partes.isEmpty ? 'nenhuma crise' : partes.join(' e ');
  return '${diaPorExtenso(dia)}${hoje ? ', hoje' : ''}: $resumo';
}

/// Calendario do mes no topo do Historico, pela AVALIACAO DO CUIDADOR:
///   - fundo amarelo: 1 a 5 crises confirmadas; vermelho: mais de 5;
///   - numero pequeno no dia: quantas crises foram confirmadas;
///   - bolinha azul: so possiveis crises aguardando confirmacao;
///   - descartados nao aparecem.
/// Semana comecando no domingo. Recolhivel; tocar num dia filtra a lista.
class CalendarioCrises extends StatelessWidget {
  const CalendarioCrises({
    super.key,
    required this.mes,
    required this.contagens,
    required this.hoje,
    required this.escolhido,
    required this.aberto,
    required this.primeiroMes,
    required this.onMes,
    required this.onDia,
    required this.onAlternar,
  });

  /// Primeiro dia do mes mostrado.
  final DateTime mes;
  final Map<DateTime, ContagemDia> contagens;
  final DateTime hoje;
  final DateTime? escolhido;
  final bool aberto;

  /// Mes mais antigo com episodio (limite do "Mês anterior").
  final DateTime primeiroMes;
  final ValueChanged<DateTime> onMes;
  final ValueChanged<DateTime> onDia;
  final VoidCallback onAlternar;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final mesAtual = DateTime(hoje.year, hoje.month);
    final podeVoltar = mes.isAfter(DateTime(primeiroMes.year, primeiroMes.month));
    final podeAvancar = mes.isBefore(mesAtual);
    final doMes = contagemNoMes(contagens, mes.year, mes.month);

    return Secao(
      padding: const EdgeInsets.fromLTRB(Calendario.margem, Espaco.xs, Calendario.margem, Espaco.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: podeVoltar ? () => onMes(DateTime(mes.year, mes.month - 1)) : null,
                tooltip: 'Mês anterior',
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text(mesEAno(mes), textAlign: TextAlign.center, style: texto.titleMedium),
                ),
              ),
              IconButton(
                onPressed: podeAvancar ? () => onMes(DateTime(mes.year, mes.month + 1)) : null,
                tooltip: 'Próximo mês',
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              Semantics(
                expanded: aberto,
                child: IconButton(
                  onPressed: onAlternar,
                  tooltip: aberto ? 'Recolher calendário' : 'Mostrar calendário',
                  icon: Icon(aberto ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                ),
              ),
            ],
          ),
          TamanhoAnimado(
            child: aberto
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: Espaco.xs),
                      _Grade(mes: mes, contagens: contagens, hoje: hoje, escolhido: escolhido, onDia: onDia),
                      const SizedBox(height: Espaco.m),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: Espaco.m),
                        child: _Legenda(),
                      ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(Espaco.m, Espaco.xs, Espaco.m, 0),
                    child: Text(_resumoDoMes(doMes), style: texto.bodySmall),
                  ),
          ),
        ],
      ),
    );
  }

  String _resumoDoMes(ContagemDia c) {
    final mesNome = nomeDoMes(mes.month);
    if (c.total == 0) return 'Nenhuma crise em $mesNome.';
    final partes = [
      if (c.confirmadas > 0) contarConfirmadas(c.confirmadas),
      if (c.pendentes > 0) '${c.pendentes} aguardando sua confirmação',
    ];
    final frase = partes.join(' e ');
    return 'Em $mesNome: $frase.';
  }
}

class _Grade extends StatelessWidget {
  const _Grade({
    required this.mes,
    required this.contagens,
    required this.hoje,
    required this.escolhido,
    required this.onDia,
  });

  final DateTime mes;
  final Map<DateTime, ContagemDia> contagens;
  final DateTime hoje;
  final DateTime? escolhido;
  final ValueChanged<DateTime> onDia;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final escala = MediaQuery.textScalerOf(context);
    final diasNoMes = DateTime(mes.year, mes.month + 1, 0).day;
    final deslocamento = DateTime(mes.year, mes.month).weekday % 7; // domingo = 0
    final semanas = ((deslocamento + diasNoMes) / 7).ceil();
    // Numero do dia + marcador da contagem, com folga para a fonte ampliada
    final altura = max(Calendario.dia, escala.scale(36) + Espaco.m);

    return Column(
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              for (final d in _semana)
                Expanded(child: Text(d, textAlign: TextAlign.center, style: texto.labelSmall)),
            ],
          ),
        ),
        const SizedBox(height: Espaco.xs),
        for (var s = 0; s < semanas; s++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: SizedBox(
                    height: altura,
                    child: () {
                      final n = s * 7 + c - deslocamento + 1;
                      if (n < 1 || n > diasNoMes) return const SizedBox.shrink();
                      final dia = DateTime(mes.year, mes.month, n);
                      return DiaDoCalendario(
                        key: ValueKey('dia-${dia.year}-${dia.month}-${dia.day}'),
                        dia: dia,
                        contagem: contagens[dia] ?? const ContagemDia(),
                        hoje: mesmoDia(dia, hoje),
                        escolhido: escolhido != null && mesmoDia(dia, escolhido!),
                        onTap: () => onDia(dia),
                      );
                    }(),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Um dia do calendario. A cor vem so das crises confirmadas
/// ([corDoDia]); a bolinha azul, de um dia so com pendentes.
class DiaDoCalendario extends StatelessWidget {
  const DiaDoCalendario({
    super.key,
    required this.dia,
    required this.contagem,
    required this.hoje,
    required this.escolhido,
    required this.onTap,
  });

  final DateTime dia;
  final ContagemDia contagem;
  final bool hoje;
  final bool escolhido;
  final VoidCallback onTap;

  CorDoDia get cor => corDoDia(contagem.confirmadas);

  bool get bolinha => contagem.somentePendentes;

  @override
  Widget build(BuildContext context) {
    final cores = CoresApp.of(context);
    final dados = CoresDados.of(context);
    final texto = Theme.of(context).textTheme;
    final ParCor? par = switch (cor) {
      CorDoDia.nenhuma => null,
      CorDoDia.amarelo => dados.diaAmarelo,
      CorDoDia.vermelho => dados.diaVermelho,
    };
    final tinta = par?.texto ?? cores.tinta;
    final raio = BorderRadius.circular(Raio.controle);
    final Border? borda = escolhido
        ? Border.all(color: cores.primaria, width: Calendario.contornoEscolhido)
        : hoje
            ? Border.all(color: cores.tinta, width: Calendario.contornoHoje)
            : null;
    final estiloNumero = texto.titleSmall!.copyWith(
      color: tinta,
      fontWeight: hoje || par != null ? FontWeight.w700 : FontWeight.w500,
      fontFeatures: Tipografia.tabular,
    );

    return Semantics(
      container: true,
      button: true,
      selected: escolhido,
      label: falaDoDia(dia, contagem, hoje: hoje),
      hint: 'Toque para ver só os episódios deste dia',
      excludeSemantics: true,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: raio,
            child: Ink(
              decoration: BoxDecoration(color: par?.fundo, borderRadius: raio, border: borda),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${dia.day}', style: estiloNumero),
                        if (bolinha) ...[
                          const SizedBox(width: 3),
                          Container(
                            key: const ValueKey('bolinha-azul'),
                            width: Calendario.bolinha,
                            height: Calendario.bolinha,
                            decoration: BoxDecoration(color: dados.pendente, shape: BoxShape.circle),
                          ),
                        ],
                      ],
                    ),
                    if (contagem.confirmadas > 0) _Contagem(n: contagem.confirmadas, par: par!),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quantidade de crises confirmadas: numero pequeno numa pilula invertida
/// (texto na cor do fundo do dia), para nao se confundir com a data.
class _Contagem extends StatelessWidget {
  const _Contagem({required this.n, required this.par});

  final int n;
  final ParCor par;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('contagem-confirmadas'),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: ShapeDecoration(color: par.texto, shape: const StadiumBorder()),
      child: Text(
        '$n',
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: par.fundo,
              fontWeight: FontWeight.w700,
              height: 1.2,
              fontFeatures: Tipografia.tabular,
            ),
      ),
    );
  }
}

class _Legenda extends StatelessWidget {
  const _Legenda();

  @override
  Widget build(BuildContext context) {
    final dados = CoresDados.of(context);
    final texto = Theme.of(context).textTheme;

    Widget amostra(Color cor) => Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(4)),
        );

    Widget item(Widget marca, String frase) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 24, height: 20, child: Center(child: marca)),
            const SizedBox(width: Espaco.s),
            Expanded(child: Text(frase, style: texto.bodySmall)),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        item(amostra(dados.diaAmarelo.fundo), 'Amarelo: 1 a 5 crises confirmadas'),
        const SizedBox(height: Espaco.xs),
        item(amostra(dados.diaVermelho.fundo), 'Vermelho: mais de 5'),
        const SizedBox(height: Espaco.xs),
        item(
          Container(
            width: Calendario.bolinha,
            height: Calendario.bolinha,
            decoration: BoxDecoration(color: dados.pendente, shape: BoxShape.circle),
          ),
          'Bolinha azul: possível crise aguardando sua confirmação',
        ),
        const SizedBox(height: Espaco.xs),
        item(
          ExcludeSemantics(child: _Contagem(n: 3, par: dados.diaAmarelo)),
          'Número no dia: quantas crises você confirmou',
        ),
      ],
    );
  }
}

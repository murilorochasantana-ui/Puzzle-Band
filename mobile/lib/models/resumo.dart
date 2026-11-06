// Resumos calculados a partir do historico recebido do site (funcoes puras,
// testadas em test/models_test.dart).
//
// Calendario e grafico de 7 dias contam pela AVALIACAO DO CUIDADOR, nao
// pelo nivel do modelo:
//   - crise = episodio confirmado (`avaliacao_cuidador = confirmado`);
//   - possivel crise aguardando confirmacao = episodio pendente;
//   - descartado nao conta em nada.

import 'models.dart';

DateTime diaDe(DateTime d) => DateTime(d.year, d.month, d.day);

bool mesmoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

int episodiosNoDia(List<Episodio> episodios, DateTime dia) =>
    episodios.where((e) => mesmoDia(e.inicio, dia)).length;

int episodiosNoMes(List<Episodio> episodios, DateTime agora) =>
    episodios.where((e) => e.inicio.year == agora.year && e.inicio.month == agora.month).length;

const _diasDaSemana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

String rotuloDiaDaSemana(DateTime d) => _diasDaSemana[d.weekday - 1];

/// Crises de um dia pela avaliacao do cuidador.
class ContagemDia {
  const ContagemDia({this.confirmadas = 0, this.pendentes = 0, this.duracaoS = 0});

  /// Episodios confirmados pelo cuidador (as "crises").
  final int confirmadas;

  /// Episodios ainda pendentes (possiveis crises aguardando confirmacao).
  final int pendentes;

  /// Duracao somada dos episodios encerrados (confirmados e pendentes).
  final double duracaoS;

  int get total => confirmadas + pendentes;

  /// Bolinha azul do calendario: so possiveis crises, nenhuma confirmada.
  bool get somentePendentes => confirmadas == 0 && pendentes > 0;

  ContagemDia _mais(Episodio e) {
    final segundos = !e.emAndamento && e.duracaoS != null && e.duracaoS!.isFinite ? e.duracaoS! : 0.0;
    return ContagemDia(
      confirmadas: confirmadas + (e.avaliacao == Avaliacao.confirmado ? 1 : 0),
      pendentes: pendentes + (e.avaliacao == Avaliacao.pendente ? 1 : 0),
      duracaoS: duracaoS + segundos,
    );
  }
}

/// Contagem por dia (chave: o dia, sem hora). Descartados nao entram:
/// um dia so com descartados nao aparece no mapa.
Map<DateTime, ContagemDia> contagemPorDia(List<Episodio> episodios) {
  final dias = <DateTime, ContagemDia>{};
  for (final e in episodios) {
    if (e.avaliacao == Avaliacao.descartado) continue;
    final dia = diaDe(e.inicio);
    dias[dia] = (dias[dia] ?? const ContagemDia())._mais(e);
  }
  return dias;
}

/// Cor de fundo de um dia do calendario, so pelas crises confirmadas.
enum CorDoDia { nenhuma, amarelo, vermelho }

/// 0 -> sem cor; 1 a 5 -> amarelo; mais de 5 -> vermelho.
CorDoDia corDoDia(int confirmadas) => switch (confirmadas) {
      <= 0 => CorDoDia.nenhuma,
      <= 5 => CorDoDia.amarelo,
      _ => CorDoDia.vermelho,
    };

/// Soma das contagens de um mes.
ContagemDia contagemNoMes(Map<DateTime, ContagemDia> dias, int ano, int mes) {
  var confirmadas = 0;
  var pendentes = 0;
  var duracao = 0.0;
  for (final MapEntry(key: dia, value: c) in dias.entries) {
    if (dia.year != ano || dia.month != mes) continue;
    confirmadas += c.confirmadas;
    pendentes += c.pendentes;
    duracao += c.duracaoS;
  }
  return ContagemDia(confirmadas: confirmadas, pendentes: pendentes, duracaoS: duracao);
}

class DiaResumo {
  const DiaResumo({required this.dia, required this.rotulo, required this.contagem});

  final DateTime dia;
  final String rotulo;
  final ContagemDia contagem;
}

/// Os ultimos 7 dias (o mais antigo primeiro, termina hoje), com as crises
/// confirmadas e as aguardando confirmacao de cada dia.
List<DiaResumo> ultimos7Dias(List<Episodio> episodios, DateTime agora) {
  final hoje = diaDe(agora);
  final contagens = contagemPorDia(episodios);
  return List.generate(7, (i) {
    final dia = DateTime(hoje.year, hoje.month, hoje.day - (6 - i));
    return DiaResumo(dia: dia, rotulo: rotuloDiaDaSemana(dia), contagem: contagens[dia] ?? const ContagemDia());
  });
}

/// Episodios agrupados por dia, do dia mais recente para o mais antigo (e,
/// dentro do dia, do mais recente para o mais antigo). Todos entram,
/// inclusive os descartados.
List<(DateTime, List<Episodio>)> episodiosPorDia(List<Episodio> episodios) {
  final ordenados = [...episodios]..sort((a, b) => b.inicio.compareTo(a.inicio));
  final grupos = <(DateTime, List<Episodio>)>[];
  for (final e in ordenados) {
    final dia = diaDe(e.inicio);
    if (grupos.isEmpty || grupos.last.$1 != dia) grupos.add((dia, <Episodio>[]));
    grupos.last.$2.add(e);
  }
  return grupos;
}

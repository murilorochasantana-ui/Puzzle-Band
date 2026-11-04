// Resumos calculados a partir do historico recebido do site (funcoes puras,
// testadas em test/models_test.dart).

import 'models.dart';

DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

bool mesmoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

int episodiosNoDia(List<Episodio> episodios, DateTime dia) =>
    episodios.where((e) => mesmoDia(e.inicio, dia)).length;

int episodiosNoMes(List<Episodio> episodios, DateTime agora) =>
    episodios.where((e) => e.inicio.year == agora.year && e.inicio.month == agora.month).length;

const _diasDaSemana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

String rotuloDiaDaSemana(DateTime d) => _diasDaSemana[d.weekday - 1];

class DiaResumo {
  const DiaResumo({required this.dia, required this.rotulo, required this.total, this.nivelMaximo});

  final DateTime dia;
  final String rotulo;
  final int total;
  final NivelRisco? nivelMaximo; // null = nenhum episodio
}

/// Os ultimos 7 dias (o mais antigo primeiro, termina hoje): numero de
/// episodios e o nivel mais alto atingido em cada dia.
List<DiaResumo> ultimos7Dias(List<Episodio> episodios, DateTime agora) {
  final hoje = _dia(agora);
  return List.generate(7, (i) {
    final dia = DateTime(hoje.year, hoje.month, hoje.day - (6 - i));
    final doDia = episodios.where((e) => mesmoDia(e.inicio, dia));
    NivelRisco? maximo;
    for (final e in doDia) {
      if (maximo == null || e.nivelMaximo.rank > maximo.rank) maximo = e.nivelMaximo;
    }
    return DiaResumo(dia: dia, rotulo: rotuloDiaDaSemana(dia), total: doDia.length, nivelMaximo: maximo);
  });
}

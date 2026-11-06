String _dois(int n) => n.toString().padLeft(2, '0');

/// HH:MM
String horaMinuto(DateTime d) => '${_dois(d.hour)}:${_dois(d.minute)}';

/// HH:MM:SS
String horaMinutoSegundo(DateTime d) => '${horaMinuto(d)}:${_dois(d.second)}';

/// dd/MM HH:MM
String diaHora(DateTime d) => '${_dois(d.day)}/${_dois(d.month)} ${horaMinuto(d)}';

/// "1 min 5 s" / "42 s" (mesmo formato do site)
String duracao(double? segundos) {
  if (segundos == null || !segundos.isFinite) return '—';
  final total = segundos.round();
  final min = total ~/ 60;
  final seg = total % 60;
  return min > 0 ? '$min min $seg s' : '$seg s';
}

String rotuloFonte(String? fonte) => switch (fonte) {
      'manual' => 'Simulador manual',
      'pulseira' => 'Pulseira',
      _ => 'Fonte desconhecida',
    };

/// "Hoje, 14:32" / "Ontem, 09:10" / "03/11, 18:05"
String diaRelativo(DateTime d, DateTime agora) {
  final hoje = DateTime(agora.year, agora.month, agora.day);
  final dia = DateTime(d.year, d.month, d.day);
  final diferenca = (hoje.difference(dia).inHours / 24).round(); // round: dias de 23/25 h
  final prefixo = switch (diferenca) {
    0 => 'Hoje',
    1 => 'Ontem',
    _ => '${_dois(d.day)}/${_dois(d.month)}',
  };
  return '$prefixo, ${horaMinuto(d)}';
}

const _meses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

/// "novembro"
String nomeDoMes(int mes) => _meses[mes - 1];

/// "1 episódio" / "3 episódios" / "nenhum episódio"
String contarEpisodios(int n) => switch (n) {
      0 => 'nenhum episódio',
      1 => '1 episódio',
      _ => '$n episódios',
    };

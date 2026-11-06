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

/// "hoje às 14:32" / "ontem às 09:10" / "amanhã às 08:00" / "em 03/11 às 18:05"
String quandoEm(DateTime d, DateTime agora) {
  final hoje = DateTime(agora.year, agora.month, agora.day);
  final dia = DateTime(d.year, d.month, d.day);
  final diferenca = (dia.difference(hoje).inHours / 24).round(); // round: dias de 23/25 h
  final prefixo = switch (diferenca) {
    0 => 'hoje',
    -1 => 'ontem',
    1 => 'amanhã',
    _ => 'em ${_dois(d.day)}/${_dois(d.month)}',
  };
  return '$prefixo às ${horaMinuto(d)}';
}

const _mesesCurtos = ['jan.', 'fev.', 'mar.', 'abr.', 'maio', 'jun.', 'jul.', 'ago.', 'set.', 'out.', 'nov.', 'dez.'];
const _semana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

/// "Seg, 3 de nov." (com o ano quando nao e o ano de [agora])
String dataCurta(DateTime d, {DateTime? agora}) {
  final ano = agora != null && agora.year != d.year ? ' de ${d.year}' : '';
  return '${_semana[d.weekday - 1]}, ${d.day} de ${_mesesCurtos[d.month - 1]}$ano';
}

/// "3 de novembro"
String diaPorExtenso(DateTime d) => '${d.day} de ${nomeDoMes(d.month)}';

/// "Novembro de 2026"
String mesEAno(DateTime d) {
  final mes = nomeDoMes(d.month);
  return '${mes[0].toUpperCase()}${mes.substring(1)} de ${d.year}';
}

/// Numero com virgula decimal: 9.42 -> "9,4" (1 casa); 128.0 -> "128".
String numeroBr(double valor, int casas) => valor.toStringAsFixed(casas).replaceAll('.', ',');

/// "1 crise confirmada" / "4 crises confirmadas" / "nenhuma crise confirmada"
String contarConfirmadas(int n) => switch (n) {
      0 => 'nenhuma crise confirmada',
      1 => '1 crise confirmada',
      _ => '$n crises confirmadas',
    };

/// "1 possível crise aguardando confirmação" / "2 possíveis crises ..."
String contarPendentes(int n) => switch (n) {
      0 => 'nenhuma possível crise aguardando confirmação',
      1 => '1 possível crise aguardando confirmação',
      _ => '$n possíveis crises aguardando confirmação',
    };

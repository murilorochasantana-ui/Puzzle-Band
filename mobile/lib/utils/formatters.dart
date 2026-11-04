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

import 'package:flutter/material.dart';

import '../widgets/estado_vazio.dart';

/// Localizacao (GPS): fora da navegacao por enquanto - "em breve".
class GpsScreen extends StatelessWidget {
  const GpsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: EstadoVazio(
            icone: Icons.location_off_outlined,
            titulo: 'Localização (GPS): em breve',
            texto: 'A pulseira ainda não envia a localização.',
          ),
        ),
      ),
    );
  }
}

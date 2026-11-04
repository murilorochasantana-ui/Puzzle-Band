import 'package:flutter/material.dart';

/// Localizacao (GPS): fora da navegacao por enquanto - "em breve".
class GpsScreen extends StatelessWidget {
  const GpsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off_outlined, size: 40, color: Color(0xFFBDBDBD)),
              SizedBox(height: 10),
              Text(
                'Localização (GPS): em breve',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF666666)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

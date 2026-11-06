import 'package:flutter/material.dart';

import '../models/resumo.dart';
import '../services/app_scope.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/relogio.dart';
import '../widgets/cabecalho.dart';
import '../widgets/connection_bar.dart';
import '../widgets/faixa_estado.dart';

/// Inicio: a faixa de estado e o centro da tela (entendida em menos de 2 s).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = AppScope.of(context);
    final texto = Theme.of(context).textTheme;
    final detalhe = _detalheDoEstado(service);
    final hoje = episodiosNoDia(service.historico, relogio());
    return EstruturaTela(
      children: [
        ConnectionBar(service: service),
        const SizedBox(height: Espaco.l),
        FaixaEstado(service: service, onCiente: (id) => _confirmarCiente(context, id)),
        if (detalhe != null) ...[
          const SizedBox(height: Espaco.m),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Espaco.xs),
            child: Text(detalhe, style: texto.bodySmall),
          ),
        ],
        const SizedBox(height: Espaco.xl),
        Semantics(
          container: true,
          label: 'Hoje: ${contarEpisodios(hoje)}',
          excludeSemantics: true,
          child: Row(
            children: [
              Icon(Icons.today_outlined, color: CoresApp.of(context).tintaSuave),
              const SizedBox(width: Espaco.s),
              Expanded(child: Text('Hoje: ${contarEpisodios(hoje)}', style: texto.titleSmall)),
            ],
          ),
        ),
      ],
    );
  }

  /// Probabilidade e fonte do dado (so com estado ao vivo).
  static String? _detalheDoEstado(MqttService service) {
    final estado = service.estado;
    if (!service.estadoAoVivo || estado == null) return null;
    final prob = estado.probabilidade;
    final probabilidade =
        prob != null ? 'Probabilidade estimada: ${(prob * 100).round()}%.' : 'Analisando os primeiros 30 s.';
    return '$probabilidade Fonte: ${rotuloFonte(estado.fonte).toLowerCase()}.';
  }

  static void _confirmarCiente(BuildContext context, String episodioId) {
    final enviado = AppScope.read(context).enviarCiente(episodioId);
    if (!enviado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sem conexão com o servidor: o aviso não foi enviado. Tente de novo em instantes.')),
      );
    }
  }
}

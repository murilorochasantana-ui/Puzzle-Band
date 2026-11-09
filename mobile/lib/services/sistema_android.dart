// O que a tela "Configurar alertas" pede ao Android. Uma interface, para os
// testes usarem um sistema falso (test/apoio/sistema_falso.dart).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'monitor_segundo_plano.dart';
import 'notification_service.dart';

abstract class SistemaAndroid {
  /// POST_NOTIFICATIONS concedida (ou, antes do Android 13, notificacoes do
  /// app ligadas).
  Future<bool> notificacoesPermitidas();

  /// Abre a janela do sistema de POST_NOTIFICATIONS; se o Android nao a
  /// mostra mais (duas recusas), abre os ajustes de notificacao do app.
  Future<void> pedirNotificacoes();

  /// O app esta fora da otimizacao de bateria ("Sem restricoes").
  Future<bool> semRestricaoDeBateria();

  /// Abre ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS.
  Future<void> pedirSemRestricaoDeBateria();

  /// Build.MANUFACTURER (ex.: "samsung").
  Future<String> fabricante();

  /// Abre ACTION_APPLICATION_DETAILS_SETTINGS (detalhes do app).
  Future<void> abrirDetalhesDoApp();

  /// Acesso ao "Nao perturbe" concedido (passo opcional).
  Future<bool> naoPerturbeLiberado();

  /// Abre ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS.
  Future<void> abrirAcessoNaoPerturbe();

  /// Cria os canais de alerta que ignoram o "Nao perturbe" (com o acesso).
  Future<void> prepararCanaisDeAlerta();

  Future<bool> servicoRodando();
  Future<bool> iniciarServico(String nomeCrianca);
  Future<void> pararServico();
  Future<void> atualizarNomeNoServico(String nomeCrianca);

  /// "Monitoramento pausado": desarmar o vigia (opcao desligada) ou avisar.
  Future<void> cancelarAvisoDePausa();
}

class SistemaAndroidReal implements SistemaAndroid {
  SistemaAndroidReal({required this.notificacoes, MonitorSegundoPlano? monitor})
      : monitor = monitor ?? MonitorSegundoPlano();

  final NotificationService notificacoes;
  final MonitorSegundoPlano monitor;

  static const _canal = MethodChannel('br.unimar.puzzleband/sistema');

  Future<T?> _chamar<T>(String metodo) async {
    try {
      return await _canal.invokeMethod<T>(metodo);
    } catch (e) {
      debugPrint('Canal do sistema ($metodo): $e');
      return null;
    }
  }

  @override
  Future<bool> notificacoesPermitidas() async => await notificacoes.permitidas() ?? false;

  @override
  Future<void> pedirNotificacoes() async {
    final ok = await notificacoes.pedirPermissao();
    if (!ok && !await notificacoesPermitidas()) await _chamar<bool>('abrirAjustesDeNotificacao');
  }

  @override
  Future<bool> semRestricaoDeBateria() async => await _chamar<bool>('semRestricaoDeBateria') ?? false;

  @override
  Future<void> pedirSemRestricaoDeBateria() => _chamar<bool>('pedirSemRestricaoDeBateria');

  @override
  Future<String> fabricante() async => await _chamar<String>('fabricante') ?? '';

  @override
  Future<void> abrirDetalhesDoApp() => _chamar<bool>('abrirDetalhesDoApp');

  @override
  Future<bool> naoPerturbeLiberado() => notificacoes.naoPerturbeLiberado();

  @override
  Future<void> abrirAcessoNaoPerturbe() => _chamar<bool>('abrirAcessoNaoPerturbe');

  @override
  Future<void> prepararCanaisDeAlerta() => notificacoes.prepararCanaisDeAlerta();

  @override
  Future<bool> servicoRodando() async {
    try {
      return await monitor.rodando();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> iniciarServico(String nomeCrianca) => monitor.iniciar(nomeCrianca);

  @override
  Future<void> pararServico() => monitor.parar();

  @override
  Future<void> atualizarNomeNoServico(String nomeCrianca) => monitor.atualizarNome(nomeCrianca);

  @override
  Future<void> cancelarAvisoDePausa() => notificacoes.cancelarVigia();
}

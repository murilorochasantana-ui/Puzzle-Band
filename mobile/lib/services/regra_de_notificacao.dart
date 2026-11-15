// Regra das notificacoes de alerta, a MESMA para o app aberto e para o
// servico em primeiro plano (docs/app.md, "Notificacoes"):
//
//   - no maximo uma por episodio; se o nivel SOBE (atencao -> possivel
//     crise), a mesma notificacao e substituida e toca de novo; no mesmo
//     nivel ou descendo, nada;
//   - alerta com mais de 10 minutos nao notifica;
//   - canal com ou sem som conforme a opcao "Alertas sonoros";
//   - par de canais que ignora o "Nao perturbe" se o acesso estiver
//     concedido. A SUBIDA de nivel usa o par da notificacao original do
//     episodio, mesmo que o acesso tenha mudado no meio: assim continua sendo
//     a mesma notificacao (o par usado fica gravado junto do episodio).
//
// O app e o servico rodam em motores Dart separados (o servico tem o
// proprio isolate), cada um com a sua conexao ao banco local (banco.dart). A
// lista de episodios ja notificados fica na tabela `episodios_notificados`:
// decidir e gravar e um so comando atomico (registrarNotificacao), entao um
// lado sempre ve o que o outro acabou de notificar, e o mesmo alerta
// processado pelos dois ao mesmo tempo so notifica uma vez. A opcao "Alertas
// sonoros" continua no shared_preferences e e relida do disco a cada alerta.
//
// Quem notifica: com o servico rodando, so ele; sem o servico, o app aberto
// (quemNotifica). Os dois nunca notificam o mesmo alerta.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'banco.dart';
import 'notification_service.dart';

enum QuemNotifica { app, servico }

/// Com o servico em primeiro plano rodando, so ele notifica (e publica a
/// presenca do app); senao, o app aberto.
QuemNotifica quemNotifica({required bool servicoRodando}) =>
    servicoRodando ? QuemNotifica.servico : QuemNotifica.app;

/// "Alertas sonoros", relida do disco (o outro lado pode ter mudado).
Future<bool> Function() alertasSonorosDoDisco(SharedPreferences prefs) => () async {
      try {
        await prefs.reload();
      } catch (_) {}
      return prefs.getBool(RegistroDeNotificacoes.chaveAlertasSonoros) ?? true;
    };

/// O que mostrar (null = nao notificar).
class DecisaoDeNotificacao {
  const DecisaoDeNotificacao({
    required this.id,
    required this.titulo,
    required this.texto,
    required this.comSom,
    required this.atualizacao,
    required this.payload,
    this.ignoraNaoPerturbe = false,
  });

  final int id;
  final String titulo;
  final String texto;
  final bool comSom;

  /// Mesmo episodio, nivel subiu: substitui a notificacao (e toca de novo).
  final bool atualizacao;
  final String? payload;

  /// Usar o par de canais que ignora o "Nao perturbe".
  final bool ignoraNaoPerturbe;
}

class RegistroDeNotificacoes {
  RegistroDeNotificacoes({required this.banco, required this.alertasSonoros});

  final BancoPuzzleBand banco;

  /// Le a opcao "Alertas sonoros" (alertasSonorosDoDisco).
  final Future<bool> Function() alertasSonoros;

  static const chaveAlertasSonoros = 'alertas_sonoros';
  static const alertaMaxAtraso = Duration(minutes: 10);

  /// Decide e, se for notificar, grava o episodio como notificado (antes de
  /// devolver). `naoPerturbeLiberado`: o acesso ao "Nao perturbe" agora
  /// (vale para a primeira notificacao do episodio; a subida repete o par
  /// gravado).
  Future<DecisaoDeNotificacao?> decidir(Alerta alerta, {DateTime? agora, bool naoPerturbeLiberado = false}) async {
    if (!alerta.nivel.isAlerta) return null;
    final ts = alerta.timestamp;
    final instante = agora ?? DateTime.now();
    if (ts != null && instante.difference(ts) > alertaMaxAtraso) return null;

    final chave = alerta.episodioId ?? 'sem_id_${(ts ?? instante).millisecondsSinceEpoch}';
    Notificacao? registro;
    try {
      registro = await banco.registrarNotificacao(
        chave,
        alerta.nivel,
        ignoraNaoPerturbe: naoPerturbeLiberado,
        agora: instante,
      );
      if (registro == null) return null;
    } catch (e) {
      // Banco indisponivel: notifica assim mesmo. Uma notificacao repetida e
      // melhor que um alerta de crise perdido.
      debugPrint('Falha ao registrar a notificacao no banco: $e');
    }

    final critico = alerta.nivel == NivelRisco.altoRisco;
    final textoGatilho = alerta.gatilho?.texto ?? '';
    return DecisaoDeNotificacao(
      id: idDeNotificacao(chave),
      titulo: critico ? 'Possível crise' : 'Atenção',
      texto: textoGatilho.isNotEmpty
          ? textoGatilho
          : 'O modelo identificou sinais de ${critico ? 'possível crise' : 'atenção'}. Verifique o ambiente da criança.',
      comSom: await alertasSonoros(),
      atualizacao: registro?.subida ?? false,
      payload: alerta.episodioId,
      ignoraNaoPerturbe: registro?.ignoraNaoPerturbe ?? naoPerturbeLiberado,
    );
  }
}

/// Decide e mostra. Usado pelo app aberto e pelo servico.
Future<bool> notificarAlerta(Alerta alerta, RegistroDeNotificacoes registro, NotificationService notificacoes) async {
  final d = await registro.decidir(alerta, naoPerturbeLiberado: await notificacoes.naoPerturbeLiberado());
  if (d == null) return false;
  await notificacoes.mostrarAlerta(
    id: d.id,
    titulo: d.titulo,
    texto: d.texto,
    comSom: d.comSom,
    atualizacao: d.atualizacao,
    payload: d.payload,
    ignoraNaoPerturbe: d.ignoraNaoPerturbe,
  );
  return true;
}

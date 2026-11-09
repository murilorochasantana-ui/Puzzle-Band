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
// O app e o servico rodam em isolates separados (o servico tem o proprio
// motor Dart), cada um com a sua copia em memoria do shared_preferences.
// Por isso a lista de episodios ja notificados (e a opcao de som) e relida
// do disco ANTES de cada decisao e gravada logo DEPOIS: assim um lado ve o
// que o outro acabou de notificar.
//
// Quem notifica: com o servico rodando, so ele; sem o servico, o app aberto
// (quemNotifica). Os dois nunca notificam o mesmo alerta.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'notification_service.dart';

enum QuemNotifica { app, servico }

/// Com o servico em primeiro plano rodando, so ele notifica (e publica a
/// presenca do app); senao, o app aberto.
QuemNotifica quemNotifica({required bool servicoRodando}) =>
    servicoRodando ? QuemNotifica.servico : QuemNotifica.app;

/// O pedaco do shared_preferences que app e servico dividem. `recarregar`
/// le de novo do disco (a copia em memoria de cada isolate pode estar velha).
abstract class EstadoCompartilhado {
  Future<void> recarregar();
  String? lerTexto(String chave);
  bool? lerBooleano(String chave);
  Future<void> gravarTexto(String chave, String valor);
}

class EstadoNasPreferencias implements EstadoCompartilhado {
  EstadoNasPreferencias(this.prefs);

  final SharedPreferences prefs;

  @override
  Future<void> recarregar() => prefs.reload();

  @override
  String? lerTexto(String chave) => prefs.getString(chave);

  @override
  bool? lerBooleano(String chave) => prefs.getBool(chave);

  @override
  Future<void> gravarTexto(String chave, String valor) => prefs.setString(chave, valor);
}

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
  RegistroDeNotificacoes(this.estado);

  final EstadoCompartilhado estado;

  static const chaveNotificados = 'episodios_notificados';
  static const chaveAlertasSonoros = 'alertas_sonoros';
  static const alertaMaxAtraso = Duration(minutes: 10);
  static const maxNotificados = 100;

  /// Decide e, se for notificar, grava o episodio como notificado (antes de
  /// devolver). Le o estado do disco primeiro. `naoPerturbeLiberado`: o
  /// acesso ao "Nao perturbe" agora (vale para a primeira notificacao do
  /// episodio; a subida repete o par gravado).
  Future<DecisaoDeNotificacao?> decidir(Alerta alerta, {DateTime? agora, bool naoPerturbeLiberado = false}) async {
    if (!alerta.nivel.isAlerta) return null;
    final ts = alerta.timestamp;
    final instante = agora ?? DateTime.now();
    if (ts != null && instante.difference(ts) > alertaMaxAtraso) return null;

    await estado.recarregar();
    final notificados = _ler();
    final chave = alerta.episodioId ?? 'sem_id_${(ts ?? instante).millisecondsSinceEpoch}';
    final anterior = notificados[chave];
    if (anterior != null && alerta.nivel.rank <= anterior.nivel.rank) return null;
    final ignora = anterior?.ignoraNaoPerturbe ?? naoPerturbeLiberado;

    notificados.remove(chave);
    notificados[chave] = (nivel: alerta.nivel, ignoraNaoPerturbe: ignora);
    while (notificados.length > maxNotificados) {
      notificados.remove(notificados.keys.first);
    }
    await estado.gravarTexto(
      chaveNotificados,
      jsonEncode([
        for (final e in notificados.entries)
          [e.key, e.value.nivel.codigo, if (e.value.ignoraNaoPerturbe) 'ignora_nao_perturbe'],
      ]),
    );

    final critico = alerta.nivel == NivelRisco.altoRisco;
    final textoGatilho = alerta.gatilho?.texto ?? '';
    return DecisaoDeNotificacao(
      id: idDeNotificacao(chave),
      titulo: critico ? 'Possível crise' : 'Atenção',
      texto: textoGatilho.isNotEmpty
          ? textoGatilho
          : 'O modelo identificou sinais de ${critico ? 'possível crise' : 'atenção'}. Verifique o ambiente da criança.',
      comSom: estado.lerBooleano(chaveAlertasSonoros) ?? true,
      atualizacao: anterior != null,
      payload: alerta.episodioId,
      ignoraNaoPerturbe: ignora,
    );
  }

  /// Episodio -> nivel ja notificado e o par de canais usado. Formato antigo
  /// ([id, nivel]) = par normal.
  Map<String, ({NivelRisco nivel, bool ignoraNaoPerturbe})> _ler() {
    final mapa = <String, ({NivelRisco nivel, bool ignoraNaoPerturbe})>{}; // ordem de insercao
    try {
      final lista = jsonDecode(estado.lerTexto(chaveNotificados) ?? '[]');
      if (lista is List) {
        for (final item in lista) {
          if (item is List && item.length >= 2 && item[0] is String) {
            final nivel = NivelRisco.fromCodigo(item[1]);
            if (nivel != null) {
              mapa[item[0] as String] = (nivel: nivel, ignoraNaoPerturbe: item.length > 2 && item[2] == 'ignora_nao_perturbe');
            }
          }
        }
      }
    } catch (_) {
      // lista corrompida: recomeca vazia
    }
    return mapa;
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

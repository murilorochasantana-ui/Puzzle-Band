// Importacao unica do que o app guardava no shared_preferences antes do banco
// local (docs/app.md, "Armazenamento"): a copia do historico (`historico_v1`),
// os lembretes (`lembretes_v1`) e os episodios ja notificados
// (`episodios_notificados`).
//
//   1. rele o shared_preferences do disco (o outro motor Dart pode ter
//      importado e apagado as chaves);
//   2. sem nenhuma das chaves: nada a fazer;
//   3. importa tudo numa transacao. So preenche o que falta: o que ja esta no
//      banco (gravado pela outra conexao) nao e sobrescrito;
//   4. so DEPOIS do commit apaga as chaves antigas.
//
// Se o app cair entre o commit e a remocao, a proxima abertura importa de
// novo, sem duplicar nada. Um JSON corrompido e pulado item a item. Quem
// abrir o banco primeiro (as telas ou o servico) importa.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lembrete.dart';
import '../models/models.dart';
import 'banco.dart';

const chaveHistoricoAntigo = 'historico_v1';
const chaveLembretesAntigos = 'lembretes_v1';
const chaveNotificadosAntigos = 'episodios_notificados';
const chavesAntigas = [chaveHistoricoAntigo, chaveLembretesAntigos, chaveNotificadosAntigos];

/// Quantos itens entraram (para os testes e o log).
typedef ResultadoDaImportacao = ({int episodios, int lembretes, int notificados});

/// Importa uma vez; devolve null se nao havia nada a importar.
Future<ResultadoDaImportacao?> importarDoSharedPreferences(BancoPuzzleBand banco, SharedPreferences prefs) async {
  try {
    await prefs.reload();
  } catch (_) {}
  final historico = prefs.getString(chaveHistoricoAntigo);
  final lembretes = prefs.getString(chaveLembretesAntigos);
  final notificados = prefs.getString(chaveNotificadosAntigos);
  if (historico == null && lembretes == null && notificados == null) return null;

  final agora = DateTime.now();
  final episodiosAntigos = historico == null ? const <Episodio>[] : (parseHistorico(historico) ?? const <Episodio>[]);
  final recebido = historico == null ? null : decodeObject(historico)?['recebido_em'];
  final recebidoEm = (recebido is String ? DateTime.tryParse(recebido) : null) ?? agora;
  final lembretesAntigos = _lembretes(lembretes);
  final notificadosAntigos = _notificados(notificados);

  await banco.transaction(() async {
    for (final e in episodiosAntigos) {
      await banco.importarEpisodio(e, recebidoEm);
    }
    for (final MapEntry(:key, :value) in lembretesAntigos.entries) {
      await banco.importarLembrete(key, value);
    }
    // A lista antiga estava na ordem em que notificou (mais antigo primeiro)
    // e nao tinha horario: horarios em sequencia, terminando agora.
    for (final (i, n) in notificadosAntigos.indexed) {
      await banco.importarNotificado(
        n.chave,
        n.nivel,
        ignoraNaoPerturbe: n.ignoraNaoPerturbe,
        em: agora.subtract(Duration(microseconds: notificadosAntigos.length - i)),
      );
    }
  });

  for (final chave in chavesAntigas) {
    await prefs.remove(chave);
  }
  final r = (episodios: episodiosAntigos.length, lembretes: lembretesAntigos.length, notificados: notificadosAntigos.length);
  debugPrint('Puzzle Band: importado do shared_preferences para o banco: $r');
  return r;
}

Map<String, Lembrete> _lembretes(String? texto) {
  final lembretes = <String, Lembrete>{};
  if (texto == null) return lembretes;
  try {
    final dados = jsonDecode(texto);
    if (dados is Map<String, dynamic>) {
      for (final MapEntry(:key, :value) in dados.entries) {
        final lembrete = Lembrete.fromJson(value);
        if (lembrete != null) lembretes[key] = lembrete;
      }
    }
  } catch (_) {
    // corrompido: nada a importar daqui
  }
  return lembretes;
}

List<({String chave, NivelRisco nivel, bool ignoraNaoPerturbe})> _notificados(String? texto) {
  final lista = <({String chave, NivelRisco nivel, bool ignoraNaoPerturbe})>[];
  if (texto == null) return lista;
  try {
    final dados = jsonDecode(texto);
    if (dados is List) {
      for (final item in dados) {
        // [id, nivel] (formato antigo = par normal) ou [id, nivel, 'ignora_nao_perturbe']
        if (item is List && item.length >= 2 && item[0] is String) {
          final nivel = NivelRisco.fromCodigo(item[1]);
          if (nivel != null) {
            lista.add((
              chave: item[0] as String,
              nivel: nivel,
              ignoraNaoPerturbe: item.length > 2 && item[2] == 'ignora_nao_perturbe',
            ));
          }
        }
      }
    }
  } catch (_) {
    // corrompido: nada a importar daqui
  }
  return lista;
}

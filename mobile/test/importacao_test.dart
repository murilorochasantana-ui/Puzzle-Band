// Importacao unica do shared_preferences para o banco local
// (lib/services/importacao_antiga.dart), com dados de exemplo no formato que
// o app gravava antes do banco: historico_v1, lembretes_v1 e
// episodios_notificados (inclusive o formato antigo [id, nivel]).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzleband/models/models.dart';
import 'package:puzzleband/services/banco.dart';
import 'package:puzzleband/services/importacao_antiga.dart';
import 'package:puzzleband/services/preferencias_locais.dart';
import 'package:puzzleband/services/regra_de_notificacao.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apoio/servico_falso.dart' show AvisoFalso;

// --- Dados de exemplo (como o app antigo gravava) ---------------------------

final historicoAntigo = jsonEncode({
  'recebido_em': '2026-11-10T18:00:00.000Z',
  'episodios': [
    {
      'id': 'ep_confirmado_site',
      'crianca': 'C01',
      'fonte': 'pulseira',
      'inicio': '2026-11-10T14:00:00.000Z',
      'fim': '2026-11-10T14:02:00.000Z',
      'duracao_s': 120,
      'encerramento': 'normalizou',
      'nivel_maximo': 'alto_risco',
      'probabilidade_maxima': 0.88,
      'gatilho': {'tipo': 'ruido', 'texto': 'Provável gatilho: ruído'},
      'avaliacao_cuidador': 'confirmado',
      'observacao': 'recreio',
      'avaliacao_origem': 'site',
      'avaliacao_em': '2026-11-10T15:00:00.000Z',
      'visto_pelo_cuidador_em': '2026-11-10T14:00:30.000Z',
    },
    {
      // avaliado no app e talvez ainda nao aplicado pela pulseira
      'id': 'ep_descartado_app',
      'inicio': '2026-11-09T09:00:00.000Z',
      'nivel_maximo': 'atencao',
      'encerramento': 'normalizou',
      'duracao_s': 40,
      'gatilho': null,
      'avaliacao_cuidador': 'descartado',
      'observacao': 'exercício',
      'avaliacao_origem': 'app',
      'avaliacao_em': '2026-11-09T10:00:00.123456Z',
    },
    {'id': 'ep_pendente', 'inicio': '2026-11-08T20:00:00.000Z', 'nivel_maximo': 'atencao'},
    {'id': 'quebrado_sem_inicio', 'nivel_maximo': 'atencao'},
  ],
});

final lembretesAntigos = jsonEncode({
  'dia:2026-11-10': {'texto': 'Levar o abafador', 'salvo_em': '2026-11-10T08:00:00.000Z'},
  'episodio:ep_confirmado_site': {
    'texto': 'Falar com a professora',
    'salvo_em': '2026-11-10T16:00:00.000Z',
    'avisar_em': '2026-11-20T10:00:00.000Z',
  },
  // lembrete de um episodio que ja tinha saido da lista: nao se perde
  'episodio:ep_que_saiu': {'texto': 'Anotar', 'salvo_em': '2026-11-01T08:00:00.000Z'},
  'dia:invalido': {'texto': ''},
});

final notificadosAntigos = jsonEncode([
  ['ep_pendente', 'atencao'], // formato antigo = par normal
  ['ep_confirmado_site', 'alto_risco', 'ignora_nao_perturbe'],
  ['quebrado'],
]);

Map<String, Object> exemplo() => {
      chaveHistoricoAntigo: historicoAntigo,
      chaveLembretesAntigos: lembretesAntigos,
      chaveNotificadosAntigos: notificadosAntigos,
      // configuracoes simples: ficam no shared_preferences
      'nome_crianca': 'Ana',
      'aparencia': 'escuro',
      'alertas_sonoros': false,
      'reset_aplicado_id': 'r7',
    };

void main() {
  late BancoPuzzleBand banco;

  setUp(() => banco = BancoPuzzleBand.emMemoria());
  tearDown(() => banco.close());

  Future<SharedPreferences> prefsCom(Map<String, Object> valores) async {
    SharedPreferences.setMockInitialValues(valores);
    return SharedPreferences.getInstance();
  }

  test('importa tudo, sem perder nada, e so entao apaga as chaves antigas', () async {
    final prefs = await prefsCom(exemplo());
    final r = await importarDoSharedPreferences(banco, prefs);
    expect(r, (episodios: 3, lembretes: 3, notificados: 2));

    // episodios: todos os campos
    final episodios = {for (final e in await banco.recentes(10)) e.id: e};
    expect(episodios.keys, ['ep_confirmado_site', 'ep_descartado_app', 'ep_pendente']);
    final original = parseHistorico(historicoAntigo)!.first;
    expect(episodios['ep_confirmado_site']!.toJson(), original.toJson());
    expect(episodios['ep_descartado_app']!.avaliacao, Avaliacao.descartado);
    expect(episodios['ep_descartado_app']!.observacao, 'exercício');
    expect(episodios['ep_pendente']!.avaliacao, Avaliacao.pendente);
    expect((await banco.resumo()).recebidoEm!.toUtc(), DateTime.utc(2026, 11, 10, 18));

    // avaliacao feita no app entra tambem como local (pendente de confirmacao)
    final linha = await (banco.select(banco.episodios)..where((t) => t.id.equals('ep_descartado_app'))).getSingle();
    expect(linha.avaliacaoLocal, 'descartado');
    expect(linha.avaliacaoLocalEm, DateTime.utc(2026, 11, 9, 10, 0, 0, 123, 456).microsecondsSinceEpoch);

    // lembretes (inclusive o de um episodio que ja saiu da lista)
    final lembretes = await banco.lembretesSalvos();
    expect(lembretes.keys, containsAll(['dia:2026-11-10', 'episodio:ep_confirmado_site', 'episodio:ep_que_saiu']));
    expect(lembretes['episodio:ep_confirmado_site']!.avisarEm!.toUtc(), DateTime.utc(2026, 11, 20, 10));

    // notificados, com o par de canais; a ordem antiga e mantida
    final notificados = await banco.notificados();
    expect(notificados.keys, ['ep_pendente', 'ep_confirmado_site']);
    expect(notificados['ep_pendente']!.ignoraNaoPerturbe, isFalse);
    expect(notificados['ep_confirmado_site']!.ignoraNaoPerturbe, isTrue);
    expect(notificados['ep_confirmado_site']!.nivel, NivelRisco.altoRisco);

    // chaves antigas apagadas; as configuracoes simples continuam
    for (final chave in chavesAntigas) {
      expect(prefs.containsKey(chave), isFalse, reason: chave);
    }
    expect(prefs.getString('nome_crianca'), 'Ana');
    expect(prefs.getString('aparencia'), 'escuro');
    expect(prefs.getBool('alertas_sonoros'), isFalse);
    expect(prefs.getString('reset_aplicado_id'), 'r7');
  });

  test('uma vez so: a segunda abertura nao tem nada a importar', () async {
    final prefs = await prefsCom(exemplo());
    expect(await importarDoSharedPreferences(banco, prefs), isNotNull);
    expect(await importarDoSharedPreferences(banco, prefs), isNull);
    expect((await banco.resumo()).total, 3);
  });

  test('caiu entre o commit e a remocao das chaves: importa de novo sem duplicar nem sobrescrever o novo', () async {
    final prefs = await prefsCom(exemplo());
    await importarDoSharedPreferences(banco, prefs);
    // depois da importacao, chegou uma lista nova da pulseira e o tutor editou um lembrete
    final novo = Episodio.fromJson({
      ...parseHistorico(historicoAntigo)!.first.toJson(),
      'observacao': 'atualizado pela pulseira',
    })!;
    await banco.gravarDaPulseira([novo], DateTime.now());
    await banco.gravarLembrete(
      'dia:2026-11-10',
      Lembrete(texto: 'Levar o abafador e a garrafa', salvoEm: DateTime.now()),
    );
    // as chaves "voltam" (o app caiu antes de apaga-las)
    for (final MapEntry(:key, :value) in exemplo().entries) {
      if (chavesAntigas.contains(key)) await prefs.setString(key, value as String);
    }
    await importarDoSharedPreferences(banco, prefs);
    expect((await banco.resumo()).total, 3, reason: 'sem duplicar');
    expect((await banco.episodio('ep_confirmado_site'))!.observacao, 'atualizado pela pulseira');
    expect((await banco.lembretesSalvos())['dia:2026-11-10']!.texto, 'Levar o abafador e a garrafa');
    expect((await banco.notificados()).length, 2);
  });

  test('JSON corrompido: pula o que nao da para ler, importa o resto e apaga as chaves', () async {
    final prefs = await prefsCom({
      chaveHistoricoAntigo: '{"episodios": [quebrado',
      chaveLembretesAntigos: lembretesAntigos,
      chaveNotificadosAntigos: 'nao e json',
    });
    final r = await importarDoSharedPreferences(banco, prefs);
    expect(r, (episodios: 0, lembretes: 3, notificados: 0));
    expect(prefs.getKeys().intersection(chavesAntigas.toSet()), isEmpty);
  });

  test('sem nada a importar (instalacao nova): nao mexe no banco nem nas preferencias', () async {
    final prefs = await prefsCom({'nome_crianca': 'Ana'});
    expect(await importarDoSharedPreferences(banco, prefs), isNull);
    expect(prefs.getString('nome_crianca'), 'Ana');
    expect((await banco.resumo()).total, 0);
  });

  test('depois da importacao: o app le os lembretes do banco e nao repete a notificacao ja feita', () async {
    final prefs = await prefsCom(exemplo());
    await importarDoSharedPreferences(banco, prefs);
    final preferencias = PreferenciasLocais(prefs: prefs, banco: banco, nomePadrao: 'C01', aviso: AvisoFalso());
    await preferencias.carregar();
    expect(preferencias.lembrete('episodio:ep_confirmado_site')?.texto, 'Falar com a professora');
    expect(preferencias.nomeCrianca, 'Ana');

    final registro = RegistroDeNotificacoes(banco: banco, alertasSonoros: alertasSonorosDoDisco(prefs));
    Alerta alerta(String id, String nivel) => Alerta.tryParse(jsonEncode({
          'episodio_id': id,
          'nivel': nivel,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }))!;
    expect(await registro.decidir(alerta('ep_confirmado_site', 'alto_risco')), isNull, reason: 'ja notificado');
    final subida = await registro.decidir(alerta('ep_pendente', 'alto_risco'), naoPerturbeLiberado: true);
    expect(subida!.atualizacao, isTrue);
    expect(subida.ignoraNaoPerturbe, isFalse, reason: 'formato antigo = par normal');
    expect(subida.comSom, isFalse, reason: 'alertas_sonoros continua no shared_preferences');
  });
}

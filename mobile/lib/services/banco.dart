// Banco SQLite local do app (drift + sqlite3 embutido no APK, a mesma versao
// do SQLite no celular e no `flutter test`). Ver docs/app.md, "Armazenamento".
//
// O que fica aqui: o historico de episodios (acumulado alem dos 50 que a
// pulseira publica), os lembretes e os episodios ja notificados. As
// configuracoes simples (tema, alertas sonoros, monitorar com o app fechado,
// passos da configuracao, nome da crianca) continuam no shared_preferences.
//
// Duas conexoes no mesmo arquivo: a das telas e a do servico em primeiro
// plano (outro motor Dart, monitor_segundo_plano.dart). Modo WAL e
// busy_timeout: as leituras nao bloqueiam a escrita e duas escritas esperam
// a vez. Quem grava o que:
//   - episodios vindos da pulseira: as duas conexoes (upsert pelo id,
//     idempotente: gravar duas vezes a mesma lista nao duplica nada);
//   - avaliacao local, lembretes, reset e retencao: so as telas;
//   - episodios notificados: so quem notifica (quemNotifica), num unico
//     comando atomico (registrarNotificacao).
//
// Horarios em microssegundos desde 1970 (UTC). O `avaliacao_em` que o app
// envia volta da pulseira sem mudanca (simulator/borda.js guarda o timestamp
// da mensagem), com a mesma precisao: a confirmacao compara o valor exato.

// O CHECK de uma coluna do drift cita a propria coluna (`nivel.isIn(...)`):
// o lint ve isso como getter recursivo, mas o drift so le a definicao.
// ignore_for_file: recursive_getters

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' show Database, SqliteException;

import '../models/lembrete.dart';
import '../models/models.dart';

part 'banco.g.dart';

/// Valores aceitos nos CHECK do esquema (publicos: a exportacao do esquema os le).
const niveisValidos = ['baixo_risco', 'atencao', 'alto_risco'];
const avaliacoesValidas = ['pendente', 'confirmado', 'descartado'];
const paresDeCanais = ['normal', 'ignora_nao_perturbe'];

// ---------------------------------------------------------------------------
// Tabelas
// ---------------------------------------------------------------------------

/// Um episodio por linha (id do episodio da pulseira como chave). O indice em
/// `inicio` atende as consultas por dia, mes e 7 dias (faixas de horario).
@DataClassName('LinhaEpisodio')
@TableIndex.sql('CREATE INDEX IF NOT EXISTS idx_episodios_inicio ON episodios (inicio)')
class Episodios extends Table {
  TextColumn get id => text()();
  TextColumn get crianca => text().nullable()();
  TextColumn get fonte => text().nullable()();
  IntColumn get inicio => integer()();
  IntColumn get fim => integer().nullable()();
  RealColumn get duracaoS => real().nullable()();
  TextColumn get encerramento => text().nullable()();
  TextColumn get nivelMaximo => text().check(nivelMaximo.isIn(niveisValidos))();
  RealColumn get probabilidadeMaxima => real().nullable()();
  TextColumn get gatilhoTipo => text().nullable()();
  TextColumn get gatilhoTexto => text().nullable()();

  // Avaliacao do cuidador como a pulseira devolveu na ultima lista.
  TextColumn get avaliacao => text().withDefault(const Constant('pendente')).check(avaliacao.isIn(avaliacoesValidas))();
  TextColumn get observacao => text().withDefault(const Constant(''))();
  TextColumn get avaliacaoOrigem => text().nullable()();
  IntColumn get avaliacaoEm => integer().nullable()();
  IntColumn get vistoEm => integer().nullable()();

  /// Ultima vez que o episodio veio da pulseira.
  IntColumn get recebidoEm => integer()();

  /// Estava na ultima lista da pulseira (os 50 mais recentes).
  BoolColumn get naPulseira => boolean().withDefault(const Constant(true))();

  // Avaliacao feita neste app, pendente de confirmacao: vale ate a pulseira
  // devolver o mesmo avaliacao_em (aplicou) ou um mais novo (outra avaliacao
  // depois desta). Uma lista retida antiga nao a desfaz.
  TextColumn get avaliacaoLocal => text().nullable().check(avaliacaoLocal.isIn(avaliacoesValidas))();
  TextColumn get observacaoLocal => text().nullable()();
  IntColumn get avaliacaoLocalEm => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Lembretes do cuidador. A chave e a mesma de antes: `episodio:<id>` ou
/// `dia:AAAA-MM-DD` (PreferenciasLocais.chaveEpisodio / chaveDia).
@DataClassName('LinhaLembrete')
@TableIndex.sql('CREATE INDEX IF NOT EXISTS idx_lembretes_salvo_em ON lembretes (salvo_em)')
class Lembretes extends Table {
  TextColumn get chave => text()();
  TextColumn get texto => text().check(texto.length.isSmallerOrEqualValue(120))();
  IntColumn get salvoEm => integer()();
  IntColumn get avisarEm => integer().nullable()();

  @override
  Set<Column> get primaryKey => {chave};
}

/// Episodios ja notificados: o nivel mais alto notificado e o par de canais
/// da primeira notificacao (a subida repete o par: docs/app.md, "Nao perturbe").
@DataClassName('LinhaNotificado')
@TableIndex.sql('CREATE INDEX IF NOT EXISTS idx_notificados_em ON episodios_notificados (notificado_em)')
class EpisodiosNotificados extends Table {
  TextColumn get episodioId => text()();
  TextColumn get nivel => text().check(nivel.isIn(niveisValidos))();
  TextColumn get parDeCanais => text().check(parDeCanais.isIn(paresDeCanais))();
  IntColumn get notificadoEm => integer()();

  /// Quantas vezes notificou (1 = so a primeira; mais = houve subida).
  IntColumn get vezes => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {episodioId};
}

// ---------------------------------------------------------------------------
// Conexao
// ---------------------------------------------------------------------------

/// Pragmas de cada conexao, logo depois de abrir (roda no isolate do banco).
///   - busy_timeout: espera ate 5 s pela outra conexao em vez de falhar;
///   - WAL: leitura e escrita ao mesmo tempo (app e servico);
///   - synchronous NORMAL: seguro com WAL, menos escritas no disco;
///   - secure_delete: o que e apagado (reset, retencao) e sobrescrito no
///     arquivo, nao fica legivel nas paginas livres (LGPD).
///
/// A troca para WAL precisa do arquivo so para si e o SQLite nao espera o
/// busy_timeout nela: se app e servico abrem o arquivo novo ao mesmo tempo, a
/// segunda recebe "database is locked". Por isso tenta de novo algumas vezes
/// (o WAL fica gravado no arquivo: depois da primeira vez nao ha disputa).
/// Achado pelo teste de concorrencia (test/banco_test.dart).
void configurarConexao(Database banco) {
  banco.execute('PRAGMA busy_timeout = 5000');
  for (var tentativa = 1;; tentativa++) {
    try {
      banco.execute('PRAGMA journal_mode = WAL');
      break;
    } on SqliteException catch (e) {
      if (e.resultCode != 5 || tentativa >= 50) rethrow; // 5 = SQLITE_BUSY
      sleep(const Duration(milliseconds: 20));
    }
  }
  banco.execute('PRAGMA synchronous = NORMAL');
  banco.execute('PRAGMA secure_delete = ON');
}

int _us(DateTime d) => d.microsecondsSinceEpoch;

int? _usOuNulo(DateTime? d) => d?.microsecondsSinceEpoch;

DateTime? _data(int? us) => us == null ? null : DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true).toLocal();

/// Nivel -> numero, em SQL (para comparar "subiu de nivel").
String _rank(String coluna) => "(CASE $coluna WHEN 'alto_risco' THEN 2 WHEN 'atencao' THEN 1 ELSE 0 END)";

/// O que o registro devolve quando e para notificar.
typedef Notificacao = ({bool subida, bool ignoraNaoPerturbe});

@DriftDatabase(tables: [Episodios, Lembretes, EpisodiosNotificados])
class BancoPuzzleBand extends _$BancoPuzzleBand {
  BancoPuzzleBand(super.e);

  /// Banco so na memoria (testes).
  factory BancoPuzzleBand.emMemoria() => BancoPuzzleBand(NativeDatabase.memory(setup: configurarConexao));

  /// Banco num arquivo. `emSegundoPlano`: as consultas rodam num isolate
  /// proprio (o padrao no app, para nao travar a tela).
  factory BancoPuzzleBand.noArquivo(File arquivo, {bool emSegundoPlano = true}) => BancoPuzzleBand(
        emSegundoPlano
            ? NativeDatabase.createInBackground(arquivo, setup: configurarConexao)
            : NativeDatabase(arquivo, setup: configurarConexao),
      );

  static const nomeDoArquivo = 'puzzleband.db';

  /// Versao do esquema. Cada mudanca sobe 1 e ganha um passo em onUpgrade,
  /// com o esquema salvo em drift_schemas/ e teste em test/drift/.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        // CREATE ... IF NOT EXISTS: se app e servico abrirem o arquivo novo ao
        // mesmo tempo, a segunda criacao nao falha.
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, de, para) async {
          // v1 e a primeira versao. Proximas: um passo por versao, dentro de
          // uma transacao, conferindo o que ja existe (a outra conexao pode ter
          // migrado antes).
        },
      );

  // -------------------------------------------------------------------------
  // Retencao
  // -------------------------------------------------------------------------

  /// Episodios com mais de 1 ano saem (docs/app.md, "Retencao").
  static const retencao = Duration(days: 365);

  /// E no maximo estes episodios (os mais recentes ficam).
  static const maxEpisodios = 5000;

  /// Notificados guardados (os mais recentes).
  static const maxNotificados = 100;

  static DateTime limiteDaRetencao(DateTime agora) => agora.subtract(retencao);

  /// Apaga os episodios fora da retencao e os lembretes deles. Devolve
  /// quantos episodios sairam. Roda ao abrir o app.
  Future<int> aplicarRetencao(DateTime agora) => transaction(() async {
        final linhas = await customSelect(
          'SELECT id FROM episodios WHERE inicio < ? OR id NOT IN '
          '(SELECT id FROM episodios ORDER BY inicio DESC, id DESC LIMIT ?)',
          variables: [Variable.withInt(_us(limiteDaRetencao(agora))), Variable.withInt(maxEpisodios)],
        ).get();
        final ids = [for (final l in linhas) l.read<String>('id')];
        for (var i = 0; i < ids.length; i += 500) {
          final parte = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
          await (delete(lembretes)..where((t) => t.chave.isIn([for (final id in parte) 'episodio:$id']))).go();
          await (delete(episodios)..where((t) => t.id.isIn(parte))).go();
        }
        return ids.length;
      });

  // -------------------------------------------------------------------------
  // Episodios
  // -------------------------------------------------------------------------

  static const _colunasDaPulseira = 'id, crianca, fonte, inicio, fim, duracao_s, encerramento, nivel_maximo, '
      'probabilidade_maxima, gatilho_tipo, gatilho_texto, avaliacao, observacao, avaliacao_origem, '
      'avaliacao_em, visto_em, recebido_em';

  // A pulseira devolveu o mesmo avaliacao_em da avaliacao local (aplicou) ou
  // um mais novo (alguem avaliou depois): a avaliacao local esta confirmada.
  static const _confirmou =
      'excluded.avaliacao_em IS NOT NULL AND episodios.avaliacao_local_em IS NOT NULL '
      'AND excluded.avaliacao_em >= episodios.avaliacao_local_em';

  static const _upsertDaPulseira = 'INSERT INTO episodios ($_colunasDaPulseira, na_pulseira) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1) '
      'ON CONFLICT (id) DO UPDATE SET '
      'crianca = excluded.crianca, fonte = excluded.fonte, inicio = excluded.inicio, fim = excluded.fim, '
      'duracao_s = excluded.duracao_s, encerramento = excluded.encerramento, '
      'nivel_maximo = excluded.nivel_maximo, probabilidade_maxima = excluded.probabilidade_maxima, '
      'gatilho_tipo = excluded.gatilho_tipo, gatilho_texto = excluded.gatilho_texto, '
      'avaliacao = excluded.avaliacao, observacao = excluded.observacao, '
      'avaliacao_origem = excluded.avaliacao_origem, avaliacao_em = excluded.avaliacao_em, '
      'visto_em = excluded.visto_em, recebido_em = excluded.recebido_em, na_pulseira = 1, '
      'avaliacao_local = CASE WHEN $_confirmou THEN NULL ELSE episodios.avaliacao_local END, '
      'observacao_local = CASE WHEN $_confirmou THEN NULL ELSE episodios.observacao_local END, '
      'avaliacao_local_em = CASE WHEN $_confirmou THEN NULL ELSE episodios.avaliacao_local_em END';

  List<Object?> _valores(Episodio e, DateTime recebidoEm) => [
        e.id,
        e.crianca,
        e.fonte,
        _us(e.inicio),
        _usOuNulo(e.fim),
        e.duracaoS,
        e.encerramento,
        e.nivelMaximo.codigo,
        e.probabilidadeMaxima,
        e.gatilho?.tipo,
        e.gatilho?.texto,
        e.avaliacao.codigo,
        e.observacao,
        e.avaliacaoOrigem,
        _usOuNulo(e.avaliacaoEm),
        _usOuNulo(e.vistoEm),
        _us(recebidoEm),
      ];

  /// Lista recebida da pulseira (retida ou atualizacao): upsert de cada
  /// episodio pelo id, numa transacao. Quem nao veio na lista CONTINUA no
  /// banco, so deixa de estar "na pulseira". Uma lista vazia nao apaga nada
  /// (para limpar: npm run resetar ou "Apagar os dados"). Episodios fora da
  /// retencao nao entram.
  Future<void> gravarDaPulseira(List<Episodio> lista, DateTime recebidoEm) => transaction(() async {
        final limite = limiteDaRetencao(recebidoEm);
        final ids = <String>[];
        for (final e in lista) {
          if (e.inicio.isBefore(limite)) continue;
          await customStatement(_upsertDaPulseira, _valores(e, recebidoEm));
          ids.add(e.id);
        }
        if (ids.isEmpty) {
          await customStatement('UPDATE episodios SET na_pulseira = 0 WHERE na_pulseira = 1');
        } else {
          final marcas = List.filled(ids.length, '?').join(', ');
          await customStatement('UPDATE episodios SET na_pulseira = 0 WHERE na_pulseira = 1 AND id NOT IN ($marcas)', ids);
        }
        notifyUpdates({const TableUpdate('episodios')});
      });

  /// Importacao da copia antiga (shared_preferences): so preenche o que
  /// falta, nunca sobrescreve um episodio que ja esta no banco (que e tao novo
  /// quanto a copia ou mais). Uma avaliacao feita no app que estava na copia
  /// entra tambem como avaliacao local (pendente de confirmacao).
  Future<void> importarEpisodio(Episodio e, DateTime recebidoEm) async {
    final local = e.avaliacaoOrigem == 'app' && e.avaliacaoEm != null && e.avaliacao != Avaliacao.pendente;
    await customStatement(
      'INSERT OR IGNORE INTO episodios ($_colunasDaPulseira, na_pulseira, avaliacao_local, observacao_local, '
      'avaliacao_local_em) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)',
      [
        ..._valores(e, recebidoEm),
        local ? e.avaliacao.codigo : null,
        local ? e.observacao : null,
        local ? _us(e.avaliacaoEm!) : null,
      ],
    );
  }

  /// Avaliacao feita neste app (pendente de confirmacao pela pulseira). Num
  /// episodio que ja saiu da lista da pulseira, ela fica so aqui.
  Future<void> avaliarLocal(String id, Avaliacao avaliacao, String observacao, DateTime em) =>
      (update(episodios)..where((t) => t.id.equals(id))).write(EpisodiosCompanion(
        avaliacaoLocal: Value(avaliacao.codigo),
        observacaoLocal: Value(observacao),
        avaliacaoLocalEm: Value(_us(em)),
      ));

  Episodio _episodio(LinhaEpisodio l) {
    final local = l.avaliacaoLocal;
    final textoGatilho = l.gatilhoTexto ?? '';
    return Episodio(
      id: l.id,
      crianca: l.crianca,
      fonte: l.fonte,
      inicio: _data(l.inicio)!,
      fim: _data(l.fim),
      duracaoS: l.duracaoS,
      encerramento: l.encerramento,
      nivelMaximo: NivelRisco.fromCodigo(l.nivelMaximo) ?? NivelRisco.atencao,
      probabilidadeMaxima: l.probabilidadeMaxima,
      gatilho: l.gatilhoTipo == null && textoGatilho.isEmpty ? null : Gatilho(tipo: l.gatilhoTipo, texto: textoGatilho),
      avaliacao: Avaliacao.fromCodigo(local ?? l.avaliacao),
      observacao: local != null ? (l.observacaoLocal ?? '') : l.observacao,
      avaliacaoOrigem: local != null ? 'app' : l.avaliacaoOrigem,
      avaliacaoEm: _data(local != null ? l.avaliacaoLocalEm : l.avaliacaoEm),
      vistoEm: _data(l.vistoEm),
      naPulseira: l.naPulseira,
    );
  }

  List<OrderingTerm Function($EpisodiosTable)> get _maisRecentePrimeiro =>
      [(t) => OrderingTerm.desc(t.inicio), (t) => OrderingTerm.desc(t.id)];

  /// Episodios com inicio em [de, ate), do mais recente para o mais antigo.
  Future<List<Episodio>> episodiosEntre(DateTime de, DateTime ate) async {
    final q = select(episodios)
      ..where((t) => t.inicio.isBiggerOrEqualValue(_us(de)) & t.inicio.isSmallerThanValue(_us(ate)))
      ..orderBy(_maisRecentePrimeiro);
    return [for (final l in await q.get()) _episodio(l)];
  }

  /// Episodios com inicio a partir de [de] (mais recente primeiro).
  Future<List<Episodio>> episodiosDesde(DateTime de) async {
    final q = select(episodios)
      ..where((t) => t.inicio.isBiggerOrEqualValue(_us(de)))
      ..orderBy(_maisRecentePrimeiro);
    return [for (final l in await q.get()) _episodio(l)];
  }

  /// Os [limite] episodios mais recentes.
  Future<List<Episodio>> recentes(int limite) async {
    final q = select(episodios)
      ..orderBy(_maisRecentePrimeiro)
      ..limit(limite);
    return [for (final l in await q.get()) _episodio(l)];
  }

  Future<Episodio?> episodio(String id) async {
    final l = await (select(episodios)..where((t) => t.id.equals(id))).getSingleOrNull();
    return l == null ? null : _episodio(l);
  }

  /// Total de episodios, o inicio do mais antigo e o ultimo recebimento da
  /// pulseira, numa consulta.
  Future<({int total, DateTime? primeiro, DateTime? recebidoEm})> resumo() async {
    final l = await customSelect(
      'SELECT COUNT(*) AS total, MIN(inicio) AS primeiro, MAX(recebido_em) AS recebido FROM episodios',
      readsFrom: {episodios},
    ).getSingle();
    return (
      total: l.read<int>('total'),
      primeiro: _data(l.readNullable<int>('primeiro')),
      recebidoEm: _data(l.readNullable<int>('recebido')),
    );
  }

  /// Reset: apaga os episodios e os notificados (os lembretes saem por
  /// apagarLembretes, chamado por PreferenciasLocais).
  Future<void> apagarHistorico() async {
    await transaction(() async {
      await delete(episodios).go();
      await delete(episodiosNotificados).go();
    });
    await _limparWal();
  }

  /// Leva o que estava no -wal para o arquivo principal e zera o -wal (com o
  /// secure_delete, o que foi apagado nao fica legivel). Se a outra conexao
  /// estiver lendo, o SQLite faz o que der; nao e erro.
  Future<void> _limparWal() async {
    try {
      await customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Lembretes
  // -------------------------------------------------------------------------

  Future<Map<String, Lembrete>> lembretesSalvos() async => {
        for (final l in await select(lembretes).get())
          l.chave: Lembrete(
            texto: l.texto,
            salvoEm: _data(l.salvoEm)!,
            avisarEm: _data(l.avisarEm),
          ),
      };

  LembretesCompanion _linhaDoLembrete(String chave, Lembrete l) => LembretesCompanion.insert(
        chave: chave,
        texto: l.texto.length > 120 ? l.texto.substring(0, 120) : l.texto,
        salvoEm: _us(l.salvoEm),
        avisarEm: Value(_usOuNulo(l.avisarEm)),
      );

  Future<void> gravarLembrete(String chave, Lembrete l) =>
      into(lembretes).insertOnConflictUpdate(_linhaDoLembrete(chave, l));

  /// Importacao: so entra se a chave ainda nao existe.
  Future<void> importarLembrete(String chave, Lembrete l) =>
      into(lembretes).insert(_linhaDoLembrete(chave, l), mode: InsertMode.insertOrIgnore);

  Future<void> apagarLembretes(Iterable<String> chaves) async {
    final lista = chaves.toList();
    if (lista.isEmpty) return;
    await (delete(lembretes)..where((t) => t.chave.isIn(lista))).go();
  }

  Future<void> apagarTodosOsLembretes() async {
    await delete(lembretes).go();
    await _limparWal();
  }

  // -------------------------------------------------------------------------
  // Episodios notificados
  // -------------------------------------------------------------------------

  /// Registra a notificacao do episodio [chave] no [nivel], se for a primeira
  /// ou se o nivel subiu; senao devolve null (nao notificar). E um so comando
  /// (INSERT ... ON CONFLICT DO UPDATE ... WHERE ... RETURNING), atomico entre
  /// as duas conexoes: se app e servico decidirem o mesmo alerta ao mesmo
  /// tempo, so um recebe a linha de volta. A subida devolve o par de canais
  /// gravado na primeira notificacao.
  Future<Notificacao?> registrarNotificacao(
    String chave,
    NivelRisco nivel, {
    required bool ignoraNaoPerturbe,
    required DateTime agora,
  }) async {
    final linhas = await customWriteReturning(
      'INSERT INTO episodios_notificados (episodio_id, nivel, par_de_canais, notificado_em, vezes) '
      'VALUES (?, ?, ?, ?, 1) '
      'ON CONFLICT (episodio_id) DO UPDATE SET nivel = excluded.nivel, notificado_em = excluded.notificado_em, '
      'vezes = episodios_notificados.vezes + 1 '
      'WHERE ${_rank('excluded.nivel')} > ${_rank('episodios_notificados.nivel')} '
      'RETURNING par_de_canais, vezes',
      variables: [
        Variable.withString(chave),
        Variable.withString(nivel.codigo),
        Variable.withString(ignoraNaoPerturbe ? 'ignora_nao_perturbe' : 'normal'),
        Variable.withInt(_us(agora)),
      ],
      updates: {episodiosNotificados},
    );
    if (linhas.isEmpty) return null;
    await customStatement(
      'DELETE FROM episodios_notificados WHERE episodio_id NOT IN '
      '(SELECT episodio_id FROM episodios_notificados ORDER BY notificado_em DESC LIMIT $maxNotificados)',
    );
    final l = linhas.single;
    return (subida: l.read<int>('vezes') > 1, ignoraNaoPerturbe: l.read<String>('par_de_canais') == 'ignora_nao_perturbe');
  }

  /// Importacao: so entra se o episodio ainda nao foi registrado.
  Future<void> importarNotificado(String chave, NivelRisco nivel, {required bool ignoraNaoPerturbe, required DateTime em}) =>
      into(episodiosNotificados).insert(
        EpisodiosNotificadosCompanion.insert(
          episodioId: chave,
          nivel: nivel.codigo,
          parDeCanais: ignoraNaoPerturbe ? 'ignora_nao_perturbe' : 'normal',
          notificadoEm: _us(em),
        ),
        mode: InsertMode.insertOrIgnore,
      );

  /// Episodio -> nivel notificado (testes e diagnostico).
  Future<Map<String, ({NivelRisco nivel, bool ignoraNaoPerturbe})>> notificados() async => {
        for (final l in await (select(episodiosNotificados)..orderBy([(t) => OrderingTerm.asc(t.notificadoEm)])).get())
          l.episodioId: (
            nivel: NivelRisco.fromCodigo(l.nivel) ?? NivelRisco.atencao,
            ignoraNaoPerturbe: l.parDeCanais == 'ignora_nao_perturbe',
          ),
      };
}

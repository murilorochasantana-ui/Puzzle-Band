// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'banco.dart';

// ignore_for_file: type=lint
class $EpisodiosTable extends Episodios
    with TableInfo<$EpisodiosTable, LinhaEpisodio> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EpisodiosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _criancaMeta = const VerificationMeta(
    'crianca',
  );
  @override
  late final GeneratedColumn<String> crianca = GeneratedColumn<String>(
    'crianca',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fonteMeta = const VerificationMeta('fonte');
  @override
  late final GeneratedColumn<String> fonte = GeneratedColumn<String>(
    'fonte',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _inicioMeta = const VerificationMeta('inicio');
  @override
  late final GeneratedColumn<int> inicio = GeneratedColumn<int>(
    'inicio',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fimMeta = const VerificationMeta('fim');
  @override
  late final GeneratedColumn<int> fim = GeneratedColumn<int>(
    'fim',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _duracaoSMeta = const VerificationMeta(
    'duracaoS',
  );
  @override
  late final GeneratedColumn<double> duracaoS = GeneratedColumn<double>(
    'duracao_s',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _encerramentoMeta = const VerificationMeta(
    'encerramento',
  );
  @override
  late final GeneratedColumn<String> encerramento = GeneratedColumn<String>(
    'encerramento',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nivelMaximoMeta = const VerificationMeta(
    'nivelMaximo',
  );
  @override
  late final GeneratedColumn<String> nivelMaximo = GeneratedColumn<String>(
    'nivel_maximo',
    aliasedName,
    false,
    check: () => nivelMaximo.isIn(niveisValidos),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _probabilidadeMaximaMeta =
      const VerificationMeta('probabilidadeMaxima');
  @override
  late final GeneratedColumn<double> probabilidadeMaxima =
      GeneratedColumn<double>(
        'probabilidade_maxima',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _gatilhoTipoMeta = const VerificationMeta(
    'gatilhoTipo',
  );
  @override
  late final GeneratedColumn<String> gatilhoTipo = GeneratedColumn<String>(
    'gatilho_tipo',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gatilhoTextoMeta = const VerificationMeta(
    'gatilhoTexto',
  );
  @override
  late final GeneratedColumn<String> gatilhoTexto = GeneratedColumn<String>(
    'gatilho_texto',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avaliacaoMeta = const VerificationMeta(
    'avaliacao',
  );
  @override
  late final GeneratedColumn<String> avaliacao = GeneratedColumn<String>(
    'avaliacao',
    aliasedName,
    false,
    check: () => avaliacao.isIn(avaliacoesValidas),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pendente'),
  );
  static const VerificationMeta _observacaoMeta = const VerificationMeta(
    'observacao',
  );
  @override
  late final GeneratedColumn<String> observacao = GeneratedColumn<String>(
    'observacao',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _avaliacaoOrigemMeta = const VerificationMeta(
    'avaliacaoOrigem',
  );
  @override
  late final GeneratedColumn<String> avaliacaoOrigem = GeneratedColumn<String>(
    'avaliacao_origem',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avaliacaoEmMeta = const VerificationMeta(
    'avaliacaoEm',
  );
  @override
  late final GeneratedColumn<int> avaliacaoEm = GeneratedColumn<int>(
    'avaliacao_em',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vistoEmMeta = const VerificationMeta(
    'vistoEm',
  );
  @override
  late final GeneratedColumn<int> vistoEm = GeneratedColumn<int>(
    'visto_em',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recebidoEmMeta = const VerificationMeta(
    'recebidoEm',
  );
  @override
  late final GeneratedColumn<int> recebidoEm = GeneratedColumn<int>(
    'recebido_em',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _naPulseiraMeta = const VerificationMeta(
    'naPulseira',
  );
  @override
  late final GeneratedColumn<bool> naPulseira = GeneratedColumn<bool>(
    'na_pulseira',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("na_pulseira" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _avaliacaoLocalMeta = const VerificationMeta(
    'avaliacaoLocal',
  );
  @override
  late final GeneratedColumn<String> avaliacaoLocal = GeneratedColumn<String>(
    'avaliacao_local',
    aliasedName,
    true,
    check: () => avaliacaoLocal.isIn(avaliacoesValidas),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _observacaoLocalMeta = const VerificationMeta(
    'observacaoLocal',
  );
  @override
  late final GeneratedColumn<String> observacaoLocal = GeneratedColumn<String>(
    'observacao_local',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avaliacaoLocalEmMeta = const VerificationMeta(
    'avaliacaoLocalEm',
  );
  @override
  late final GeneratedColumn<int> avaliacaoLocalEm = GeneratedColumn<int>(
    'avaliacao_local_em',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    crianca,
    fonte,
    inicio,
    fim,
    duracaoS,
    encerramento,
    nivelMaximo,
    probabilidadeMaxima,
    gatilhoTipo,
    gatilhoTexto,
    avaliacao,
    observacao,
    avaliacaoOrigem,
    avaliacaoEm,
    vistoEm,
    recebidoEm,
    naPulseira,
    avaliacaoLocal,
    observacaoLocal,
    avaliacaoLocalEm,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'episodios';
  @override
  VerificationContext validateIntegrity(
    Insertable<LinhaEpisodio> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('crianca')) {
      context.handle(
        _criancaMeta,
        crianca.isAcceptableOrUnknown(data['crianca']!, _criancaMeta),
      );
    }
    if (data.containsKey('fonte')) {
      context.handle(
        _fonteMeta,
        fonte.isAcceptableOrUnknown(data['fonte']!, _fonteMeta),
      );
    }
    if (data.containsKey('inicio')) {
      context.handle(
        _inicioMeta,
        inicio.isAcceptableOrUnknown(data['inicio']!, _inicioMeta),
      );
    } else if (isInserting) {
      context.missing(_inicioMeta);
    }
    if (data.containsKey('fim')) {
      context.handle(
        _fimMeta,
        fim.isAcceptableOrUnknown(data['fim']!, _fimMeta),
      );
    }
    if (data.containsKey('duracao_s')) {
      context.handle(
        _duracaoSMeta,
        duracaoS.isAcceptableOrUnknown(data['duracao_s']!, _duracaoSMeta),
      );
    }
    if (data.containsKey('encerramento')) {
      context.handle(
        _encerramentoMeta,
        encerramento.isAcceptableOrUnknown(
          data['encerramento']!,
          _encerramentoMeta,
        ),
      );
    }
    if (data.containsKey('nivel_maximo')) {
      context.handle(
        _nivelMaximoMeta,
        nivelMaximo.isAcceptableOrUnknown(
          data['nivel_maximo']!,
          _nivelMaximoMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nivelMaximoMeta);
    }
    if (data.containsKey('probabilidade_maxima')) {
      context.handle(
        _probabilidadeMaximaMeta,
        probabilidadeMaxima.isAcceptableOrUnknown(
          data['probabilidade_maxima']!,
          _probabilidadeMaximaMeta,
        ),
      );
    }
    if (data.containsKey('gatilho_tipo')) {
      context.handle(
        _gatilhoTipoMeta,
        gatilhoTipo.isAcceptableOrUnknown(
          data['gatilho_tipo']!,
          _gatilhoTipoMeta,
        ),
      );
    }
    if (data.containsKey('gatilho_texto')) {
      context.handle(
        _gatilhoTextoMeta,
        gatilhoTexto.isAcceptableOrUnknown(
          data['gatilho_texto']!,
          _gatilhoTextoMeta,
        ),
      );
    }
    if (data.containsKey('avaliacao')) {
      context.handle(
        _avaliacaoMeta,
        avaliacao.isAcceptableOrUnknown(data['avaliacao']!, _avaliacaoMeta),
      );
    }
    if (data.containsKey('observacao')) {
      context.handle(
        _observacaoMeta,
        observacao.isAcceptableOrUnknown(data['observacao']!, _observacaoMeta),
      );
    }
    if (data.containsKey('avaliacao_origem')) {
      context.handle(
        _avaliacaoOrigemMeta,
        avaliacaoOrigem.isAcceptableOrUnknown(
          data['avaliacao_origem']!,
          _avaliacaoOrigemMeta,
        ),
      );
    }
    if (data.containsKey('avaliacao_em')) {
      context.handle(
        _avaliacaoEmMeta,
        avaliacaoEm.isAcceptableOrUnknown(
          data['avaliacao_em']!,
          _avaliacaoEmMeta,
        ),
      );
    }
    if (data.containsKey('visto_em')) {
      context.handle(
        _vistoEmMeta,
        vistoEm.isAcceptableOrUnknown(data['visto_em']!, _vistoEmMeta),
      );
    }
    if (data.containsKey('recebido_em')) {
      context.handle(
        _recebidoEmMeta,
        recebidoEm.isAcceptableOrUnknown(data['recebido_em']!, _recebidoEmMeta),
      );
    } else if (isInserting) {
      context.missing(_recebidoEmMeta);
    }
    if (data.containsKey('na_pulseira')) {
      context.handle(
        _naPulseiraMeta,
        naPulseira.isAcceptableOrUnknown(data['na_pulseira']!, _naPulseiraMeta),
      );
    }
    if (data.containsKey('avaliacao_local')) {
      context.handle(
        _avaliacaoLocalMeta,
        avaliacaoLocal.isAcceptableOrUnknown(
          data['avaliacao_local']!,
          _avaliacaoLocalMeta,
        ),
      );
    }
    if (data.containsKey('observacao_local')) {
      context.handle(
        _observacaoLocalMeta,
        observacaoLocal.isAcceptableOrUnknown(
          data['observacao_local']!,
          _observacaoLocalMeta,
        ),
      );
    }
    if (data.containsKey('avaliacao_local_em')) {
      context.handle(
        _avaliacaoLocalEmMeta,
        avaliacaoLocalEm.isAcceptableOrUnknown(
          data['avaliacao_local_em']!,
          _avaliacaoLocalEmMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LinhaEpisodio map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LinhaEpisodio(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      crianca: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}crianca'],
      ),
      fonte: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fonte'],
      ),
      inicio:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}inicio'],
          )!,
      fim: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fim'],
      ),
      duracaoS: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}duracao_s'],
      ),
      encerramento: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encerramento'],
      ),
      nivelMaximo:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}nivel_maximo'],
          )!,
      probabilidadeMaxima: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}probabilidade_maxima'],
      ),
      gatilhoTipo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gatilho_tipo'],
      ),
      gatilhoTexto: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gatilho_texto'],
      ),
      avaliacao:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}avaliacao'],
          )!,
      observacao:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}observacao'],
          )!,
      avaliacaoOrigem: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avaliacao_origem'],
      ),
      avaliacaoEm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}avaliacao_em'],
      ),
      vistoEm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}visto_em'],
      ),
      recebidoEm:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}recebido_em'],
          )!,
      naPulseira:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}na_pulseira'],
          )!,
      avaliacaoLocal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avaliacao_local'],
      ),
      observacaoLocal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}observacao_local'],
      ),
      avaliacaoLocalEm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}avaliacao_local_em'],
      ),
    );
  }

  @override
  $EpisodiosTable createAlias(String alias) {
    return $EpisodiosTable(attachedDatabase, alias);
  }
}

class LinhaEpisodio extends DataClass implements Insertable<LinhaEpisodio> {
  final String id;
  final String? crianca;
  final String? fonte;
  final int inicio;
  final int? fim;
  final double? duracaoS;
  final String? encerramento;
  final String nivelMaximo;
  final double? probabilidadeMaxima;
  final String? gatilhoTipo;
  final String? gatilhoTexto;
  final String avaliacao;
  final String observacao;
  final String? avaliacaoOrigem;
  final int? avaliacaoEm;
  final int? vistoEm;

  /// Ultima vez que o episodio veio da pulseira.
  final int recebidoEm;

  /// Estava na ultima lista da pulseira (os 50 mais recentes).
  final bool naPulseira;
  final String? avaliacaoLocal;
  final String? observacaoLocal;
  final int? avaliacaoLocalEm;
  const LinhaEpisodio({
    required this.id,
    this.crianca,
    this.fonte,
    required this.inicio,
    this.fim,
    this.duracaoS,
    this.encerramento,
    required this.nivelMaximo,
    this.probabilidadeMaxima,
    this.gatilhoTipo,
    this.gatilhoTexto,
    required this.avaliacao,
    required this.observacao,
    this.avaliacaoOrigem,
    this.avaliacaoEm,
    this.vistoEm,
    required this.recebidoEm,
    required this.naPulseira,
    this.avaliacaoLocal,
    this.observacaoLocal,
    this.avaliacaoLocalEm,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || crianca != null) {
      map['crianca'] = Variable<String>(crianca);
    }
    if (!nullToAbsent || fonte != null) {
      map['fonte'] = Variable<String>(fonte);
    }
    map['inicio'] = Variable<int>(inicio);
    if (!nullToAbsent || fim != null) {
      map['fim'] = Variable<int>(fim);
    }
    if (!nullToAbsent || duracaoS != null) {
      map['duracao_s'] = Variable<double>(duracaoS);
    }
    if (!nullToAbsent || encerramento != null) {
      map['encerramento'] = Variable<String>(encerramento);
    }
    map['nivel_maximo'] = Variable<String>(nivelMaximo);
    if (!nullToAbsent || probabilidadeMaxima != null) {
      map['probabilidade_maxima'] = Variable<double>(probabilidadeMaxima);
    }
    if (!nullToAbsent || gatilhoTipo != null) {
      map['gatilho_tipo'] = Variable<String>(gatilhoTipo);
    }
    if (!nullToAbsent || gatilhoTexto != null) {
      map['gatilho_texto'] = Variable<String>(gatilhoTexto);
    }
    map['avaliacao'] = Variable<String>(avaliacao);
    map['observacao'] = Variable<String>(observacao);
    if (!nullToAbsent || avaliacaoOrigem != null) {
      map['avaliacao_origem'] = Variable<String>(avaliacaoOrigem);
    }
    if (!nullToAbsent || avaliacaoEm != null) {
      map['avaliacao_em'] = Variable<int>(avaliacaoEm);
    }
    if (!nullToAbsent || vistoEm != null) {
      map['visto_em'] = Variable<int>(vistoEm);
    }
    map['recebido_em'] = Variable<int>(recebidoEm);
    map['na_pulseira'] = Variable<bool>(naPulseira);
    if (!nullToAbsent || avaliacaoLocal != null) {
      map['avaliacao_local'] = Variable<String>(avaliacaoLocal);
    }
    if (!nullToAbsent || observacaoLocal != null) {
      map['observacao_local'] = Variable<String>(observacaoLocal);
    }
    if (!nullToAbsent || avaliacaoLocalEm != null) {
      map['avaliacao_local_em'] = Variable<int>(avaliacaoLocalEm);
    }
    return map;
  }

  EpisodiosCompanion toCompanion(bool nullToAbsent) {
    return EpisodiosCompanion(
      id: Value(id),
      crianca:
          crianca == null && nullToAbsent
              ? const Value.absent()
              : Value(crianca),
      fonte:
          fonte == null && nullToAbsent ? const Value.absent() : Value(fonte),
      inicio: Value(inicio),
      fim: fim == null && nullToAbsent ? const Value.absent() : Value(fim),
      duracaoS:
          duracaoS == null && nullToAbsent
              ? const Value.absent()
              : Value(duracaoS),
      encerramento:
          encerramento == null && nullToAbsent
              ? const Value.absent()
              : Value(encerramento),
      nivelMaximo: Value(nivelMaximo),
      probabilidadeMaxima:
          probabilidadeMaxima == null && nullToAbsent
              ? const Value.absent()
              : Value(probabilidadeMaxima),
      gatilhoTipo:
          gatilhoTipo == null && nullToAbsent
              ? const Value.absent()
              : Value(gatilhoTipo),
      gatilhoTexto:
          gatilhoTexto == null && nullToAbsent
              ? const Value.absent()
              : Value(gatilhoTexto),
      avaliacao: Value(avaliacao),
      observacao: Value(observacao),
      avaliacaoOrigem:
          avaliacaoOrigem == null && nullToAbsent
              ? const Value.absent()
              : Value(avaliacaoOrigem),
      avaliacaoEm:
          avaliacaoEm == null && nullToAbsent
              ? const Value.absent()
              : Value(avaliacaoEm),
      vistoEm:
          vistoEm == null && nullToAbsent
              ? const Value.absent()
              : Value(vistoEm),
      recebidoEm: Value(recebidoEm),
      naPulseira: Value(naPulseira),
      avaliacaoLocal:
          avaliacaoLocal == null && nullToAbsent
              ? const Value.absent()
              : Value(avaliacaoLocal),
      observacaoLocal:
          observacaoLocal == null && nullToAbsent
              ? const Value.absent()
              : Value(observacaoLocal),
      avaliacaoLocalEm:
          avaliacaoLocalEm == null && nullToAbsent
              ? const Value.absent()
              : Value(avaliacaoLocalEm),
    );
  }

  factory LinhaEpisodio.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LinhaEpisodio(
      id: serializer.fromJson<String>(json['id']),
      crianca: serializer.fromJson<String?>(json['crianca']),
      fonte: serializer.fromJson<String?>(json['fonte']),
      inicio: serializer.fromJson<int>(json['inicio']),
      fim: serializer.fromJson<int?>(json['fim']),
      duracaoS: serializer.fromJson<double?>(json['duracaoS']),
      encerramento: serializer.fromJson<String?>(json['encerramento']),
      nivelMaximo: serializer.fromJson<String>(json['nivelMaximo']),
      probabilidadeMaxima: serializer.fromJson<double?>(
        json['probabilidadeMaxima'],
      ),
      gatilhoTipo: serializer.fromJson<String?>(json['gatilhoTipo']),
      gatilhoTexto: serializer.fromJson<String?>(json['gatilhoTexto']),
      avaliacao: serializer.fromJson<String>(json['avaliacao']),
      observacao: serializer.fromJson<String>(json['observacao']),
      avaliacaoOrigem: serializer.fromJson<String?>(json['avaliacaoOrigem']),
      avaliacaoEm: serializer.fromJson<int?>(json['avaliacaoEm']),
      vistoEm: serializer.fromJson<int?>(json['vistoEm']),
      recebidoEm: serializer.fromJson<int>(json['recebidoEm']),
      naPulseira: serializer.fromJson<bool>(json['naPulseira']),
      avaliacaoLocal: serializer.fromJson<String?>(json['avaliacaoLocal']),
      observacaoLocal: serializer.fromJson<String?>(json['observacaoLocal']),
      avaliacaoLocalEm: serializer.fromJson<int?>(json['avaliacaoLocalEm']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'crianca': serializer.toJson<String?>(crianca),
      'fonte': serializer.toJson<String?>(fonte),
      'inicio': serializer.toJson<int>(inicio),
      'fim': serializer.toJson<int?>(fim),
      'duracaoS': serializer.toJson<double?>(duracaoS),
      'encerramento': serializer.toJson<String?>(encerramento),
      'nivelMaximo': serializer.toJson<String>(nivelMaximo),
      'probabilidadeMaxima': serializer.toJson<double?>(probabilidadeMaxima),
      'gatilhoTipo': serializer.toJson<String?>(gatilhoTipo),
      'gatilhoTexto': serializer.toJson<String?>(gatilhoTexto),
      'avaliacao': serializer.toJson<String>(avaliacao),
      'observacao': serializer.toJson<String>(observacao),
      'avaliacaoOrigem': serializer.toJson<String?>(avaliacaoOrigem),
      'avaliacaoEm': serializer.toJson<int?>(avaliacaoEm),
      'vistoEm': serializer.toJson<int?>(vistoEm),
      'recebidoEm': serializer.toJson<int>(recebidoEm),
      'naPulseira': serializer.toJson<bool>(naPulseira),
      'avaliacaoLocal': serializer.toJson<String?>(avaliacaoLocal),
      'observacaoLocal': serializer.toJson<String?>(observacaoLocal),
      'avaliacaoLocalEm': serializer.toJson<int?>(avaliacaoLocalEm),
    };
  }

  LinhaEpisodio copyWith({
    String? id,
    Value<String?> crianca = const Value.absent(),
    Value<String?> fonte = const Value.absent(),
    int? inicio,
    Value<int?> fim = const Value.absent(),
    Value<double?> duracaoS = const Value.absent(),
    Value<String?> encerramento = const Value.absent(),
    String? nivelMaximo,
    Value<double?> probabilidadeMaxima = const Value.absent(),
    Value<String?> gatilhoTipo = const Value.absent(),
    Value<String?> gatilhoTexto = const Value.absent(),
    String? avaliacao,
    String? observacao,
    Value<String?> avaliacaoOrigem = const Value.absent(),
    Value<int?> avaliacaoEm = const Value.absent(),
    Value<int?> vistoEm = const Value.absent(),
    int? recebidoEm,
    bool? naPulseira,
    Value<String?> avaliacaoLocal = const Value.absent(),
    Value<String?> observacaoLocal = const Value.absent(),
    Value<int?> avaliacaoLocalEm = const Value.absent(),
  }) => LinhaEpisodio(
    id: id ?? this.id,
    crianca: crianca.present ? crianca.value : this.crianca,
    fonte: fonte.present ? fonte.value : this.fonte,
    inicio: inicio ?? this.inicio,
    fim: fim.present ? fim.value : this.fim,
    duracaoS: duracaoS.present ? duracaoS.value : this.duracaoS,
    encerramento: encerramento.present ? encerramento.value : this.encerramento,
    nivelMaximo: nivelMaximo ?? this.nivelMaximo,
    probabilidadeMaxima:
        probabilidadeMaxima.present
            ? probabilidadeMaxima.value
            : this.probabilidadeMaxima,
    gatilhoTipo: gatilhoTipo.present ? gatilhoTipo.value : this.gatilhoTipo,
    gatilhoTexto: gatilhoTexto.present ? gatilhoTexto.value : this.gatilhoTexto,
    avaliacao: avaliacao ?? this.avaliacao,
    observacao: observacao ?? this.observacao,
    avaliacaoOrigem:
        avaliacaoOrigem.present ? avaliacaoOrigem.value : this.avaliacaoOrigem,
    avaliacaoEm: avaliacaoEm.present ? avaliacaoEm.value : this.avaliacaoEm,
    vistoEm: vistoEm.present ? vistoEm.value : this.vistoEm,
    recebidoEm: recebidoEm ?? this.recebidoEm,
    naPulseira: naPulseira ?? this.naPulseira,
    avaliacaoLocal:
        avaliacaoLocal.present ? avaliacaoLocal.value : this.avaliacaoLocal,
    observacaoLocal:
        observacaoLocal.present ? observacaoLocal.value : this.observacaoLocal,
    avaliacaoLocalEm:
        avaliacaoLocalEm.present
            ? avaliacaoLocalEm.value
            : this.avaliacaoLocalEm,
  );
  LinhaEpisodio copyWithCompanion(EpisodiosCompanion data) {
    return LinhaEpisodio(
      id: data.id.present ? data.id.value : this.id,
      crianca: data.crianca.present ? data.crianca.value : this.crianca,
      fonte: data.fonte.present ? data.fonte.value : this.fonte,
      inicio: data.inicio.present ? data.inicio.value : this.inicio,
      fim: data.fim.present ? data.fim.value : this.fim,
      duracaoS: data.duracaoS.present ? data.duracaoS.value : this.duracaoS,
      encerramento:
          data.encerramento.present
              ? data.encerramento.value
              : this.encerramento,
      nivelMaximo:
          data.nivelMaximo.present ? data.nivelMaximo.value : this.nivelMaximo,
      probabilidadeMaxima:
          data.probabilidadeMaxima.present
              ? data.probabilidadeMaxima.value
              : this.probabilidadeMaxima,
      gatilhoTipo:
          data.gatilhoTipo.present ? data.gatilhoTipo.value : this.gatilhoTipo,
      gatilhoTexto:
          data.gatilhoTexto.present
              ? data.gatilhoTexto.value
              : this.gatilhoTexto,
      avaliacao: data.avaliacao.present ? data.avaliacao.value : this.avaliacao,
      observacao:
          data.observacao.present ? data.observacao.value : this.observacao,
      avaliacaoOrigem:
          data.avaliacaoOrigem.present
              ? data.avaliacaoOrigem.value
              : this.avaliacaoOrigem,
      avaliacaoEm:
          data.avaliacaoEm.present ? data.avaliacaoEm.value : this.avaliacaoEm,
      vistoEm: data.vistoEm.present ? data.vistoEm.value : this.vistoEm,
      recebidoEm:
          data.recebidoEm.present ? data.recebidoEm.value : this.recebidoEm,
      naPulseira:
          data.naPulseira.present ? data.naPulseira.value : this.naPulseira,
      avaliacaoLocal:
          data.avaliacaoLocal.present
              ? data.avaliacaoLocal.value
              : this.avaliacaoLocal,
      observacaoLocal:
          data.observacaoLocal.present
              ? data.observacaoLocal.value
              : this.observacaoLocal,
      avaliacaoLocalEm:
          data.avaliacaoLocalEm.present
              ? data.avaliacaoLocalEm.value
              : this.avaliacaoLocalEm,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LinhaEpisodio(')
          ..write('id: $id, ')
          ..write('crianca: $crianca, ')
          ..write('fonte: $fonte, ')
          ..write('inicio: $inicio, ')
          ..write('fim: $fim, ')
          ..write('duracaoS: $duracaoS, ')
          ..write('encerramento: $encerramento, ')
          ..write('nivelMaximo: $nivelMaximo, ')
          ..write('probabilidadeMaxima: $probabilidadeMaxima, ')
          ..write('gatilhoTipo: $gatilhoTipo, ')
          ..write('gatilhoTexto: $gatilhoTexto, ')
          ..write('avaliacao: $avaliacao, ')
          ..write('observacao: $observacao, ')
          ..write('avaliacaoOrigem: $avaliacaoOrigem, ')
          ..write('avaliacaoEm: $avaliacaoEm, ')
          ..write('vistoEm: $vistoEm, ')
          ..write('recebidoEm: $recebidoEm, ')
          ..write('naPulseira: $naPulseira, ')
          ..write('avaliacaoLocal: $avaliacaoLocal, ')
          ..write('observacaoLocal: $observacaoLocal, ')
          ..write('avaliacaoLocalEm: $avaliacaoLocalEm')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    crianca,
    fonte,
    inicio,
    fim,
    duracaoS,
    encerramento,
    nivelMaximo,
    probabilidadeMaxima,
    gatilhoTipo,
    gatilhoTexto,
    avaliacao,
    observacao,
    avaliacaoOrigem,
    avaliacaoEm,
    vistoEm,
    recebidoEm,
    naPulseira,
    avaliacaoLocal,
    observacaoLocal,
    avaliacaoLocalEm,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LinhaEpisodio &&
          other.id == this.id &&
          other.crianca == this.crianca &&
          other.fonte == this.fonte &&
          other.inicio == this.inicio &&
          other.fim == this.fim &&
          other.duracaoS == this.duracaoS &&
          other.encerramento == this.encerramento &&
          other.nivelMaximo == this.nivelMaximo &&
          other.probabilidadeMaxima == this.probabilidadeMaxima &&
          other.gatilhoTipo == this.gatilhoTipo &&
          other.gatilhoTexto == this.gatilhoTexto &&
          other.avaliacao == this.avaliacao &&
          other.observacao == this.observacao &&
          other.avaliacaoOrigem == this.avaliacaoOrigem &&
          other.avaliacaoEm == this.avaliacaoEm &&
          other.vistoEm == this.vistoEm &&
          other.recebidoEm == this.recebidoEm &&
          other.naPulseira == this.naPulseira &&
          other.avaliacaoLocal == this.avaliacaoLocal &&
          other.observacaoLocal == this.observacaoLocal &&
          other.avaliacaoLocalEm == this.avaliacaoLocalEm);
}

class EpisodiosCompanion extends UpdateCompanion<LinhaEpisodio> {
  final Value<String> id;
  final Value<String?> crianca;
  final Value<String?> fonte;
  final Value<int> inicio;
  final Value<int?> fim;
  final Value<double?> duracaoS;
  final Value<String?> encerramento;
  final Value<String> nivelMaximo;
  final Value<double?> probabilidadeMaxima;
  final Value<String?> gatilhoTipo;
  final Value<String?> gatilhoTexto;
  final Value<String> avaliacao;
  final Value<String> observacao;
  final Value<String?> avaliacaoOrigem;
  final Value<int?> avaliacaoEm;
  final Value<int?> vistoEm;
  final Value<int> recebidoEm;
  final Value<bool> naPulseira;
  final Value<String?> avaliacaoLocal;
  final Value<String?> observacaoLocal;
  final Value<int?> avaliacaoLocalEm;
  final Value<int> rowid;
  const EpisodiosCompanion({
    this.id = const Value.absent(),
    this.crianca = const Value.absent(),
    this.fonte = const Value.absent(),
    this.inicio = const Value.absent(),
    this.fim = const Value.absent(),
    this.duracaoS = const Value.absent(),
    this.encerramento = const Value.absent(),
    this.nivelMaximo = const Value.absent(),
    this.probabilidadeMaxima = const Value.absent(),
    this.gatilhoTipo = const Value.absent(),
    this.gatilhoTexto = const Value.absent(),
    this.avaliacao = const Value.absent(),
    this.observacao = const Value.absent(),
    this.avaliacaoOrigem = const Value.absent(),
    this.avaliacaoEm = const Value.absent(),
    this.vistoEm = const Value.absent(),
    this.recebidoEm = const Value.absent(),
    this.naPulseira = const Value.absent(),
    this.avaliacaoLocal = const Value.absent(),
    this.observacaoLocal = const Value.absent(),
    this.avaliacaoLocalEm = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EpisodiosCompanion.insert({
    required String id,
    this.crianca = const Value.absent(),
    this.fonte = const Value.absent(),
    required int inicio,
    this.fim = const Value.absent(),
    this.duracaoS = const Value.absent(),
    this.encerramento = const Value.absent(),
    required String nivelMaximo,
    this.probabilidadeMaxima = const Value.absent(),
    this.gatilhoTipo = const Value.absent(),
    this.gatilhoTexto = const Value.absent(),
    this.avaliacao = const Value.absent(),
    this.observacao = const Value.absent(),
    this.avaliacaoOrigem = const Value.absent(),
    this.avaliacaoEm = const Value.absent(),
    this.vistoEm = const Value.absent(),
    required int recebidoEm,
    this.naPulseira = const Value.absent(),
    this.avaliacaoLocal = const Value.absent(),
    this.observacaoLocal = const Value.absent(),
    this.avaliacaoLocalEm = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       inicio = Value(inicio),
       nivelMaximo = Value(nivelMaximo),
       recebidoEm = Value(recebidoEm);
  static Insertable<LinhaEpisodio> custom({
    Expression<String>? id,
    Expression<String>? crianca,
    Expression<String>? fonte,
    Expression<int>? inicio,
    Expression<int>? fim,
    Expression<double>? duracaoS,
    Expression<String>? encerramento,
    Expression<String>? nivelMaximo,
    Expression<double>? probabilidadeMaxima,
    Expression<String>? gatilhoTipo,
    Expression<String>? gatilhoTexto,
    Expression<String>? avaliacao,
    Expression<String>? observacao,
    Expression<String>? avaliacaoOrigem,
    Expression<int>? avaliacaoEm,
    Expression<int>? vistoEm,
    Expression<int>? recebidoEm,
    Expression<bool>? naPulseira,
    Expression<String>? avaliacaoLocal,
    Expression<String>? observacaoLocal,
    Expression<int>? avaliacaoLocalEm,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (crianca != null) 'crianca': crianca,
      if (fonte != null) 'fonte': fonte,
      if (inicio != null) 'inicio': inicio,
      if (fim != null) 'fim': fim,
      if (duracaoS != null) 'duracao_s': duracaoS,
      if (encerramento != null) 'encerramento': encerramento,
      if (nivelMaximo != null) 'nivel_maximo': nivelMaximo,
      if (probabilidadeMaxima != null)
        'probabilidade_maxima': probabilidadeMaxima,
      if (gatilhoTipo != null) 'gatilho_tipo': gatilhoTipo,
      if (gatilhoTexto != null) 'gatilho_texto': gatilhoTexto,
      if (avaliacao != null) 'avaliacao': avaliacao,
      if (observacao != null) 'observacao': observacao,
      if (avaliacaoOrigem != null) 'avaliacao_origem': avaliacaoOrigem,
      if (avaliacaoEm != null) 'avaliacao_em': avaliacaoEm,
      if (vistoEm != null) 'visto_em': vistoEm,
      if (recebidoEm != null) 'recebido_em': recebidoEm,
      if (naPulseira != null) 'na_pulseira': naPulseira,
      if (avaliacaoLocal != null) 'avaliacao_local': avaliacaoLocal,
      if (observacaoLocal != null) 'observacao_local': observacaoLocal,
      if (avaliacaoLocalEm != null) 'avaliacao_local_em': avaliacaoLocalEm,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EpisodiosCompanion copyWith({
    Value<String>? id,
    Value<String?>? crianca,
    Value<String?>? fonte,
    Value<int>? inicio,
    Value<int?>? fim,
    Value<double?>? duracaoS,
    Value<String?>? encerramento,
    Value<String>? nivelMaximo,
    Value<double?>? probabilidadeMaxima,
    Value<String?>? gatilhoTipo,
    Value<String?>? gatilhoTexto,
    Value<String>? avaliacao,
    Value<String>? observacao,
    Value<String?>? avaliacaoOrigem,
    Value<int?>? avaliacaoEm,
    Value<int?>? vistoEm,
    Value<int>? recebidoEm,
    Value<bool>? naPulseira,
    Value<String?>? avaliacaoLocal,
    Value<String?>? observacaoLocal,
    Value<int?>? avaliacaoLocalEm,
    Value<int>? rowid,
  }) {
    return EpisodiosCompanion(
      id: id ?? this.id,
      crianca: crianca ?? this.crianca,
      fonte: fonte ?? this.fonte,
      inicio: inicio ?? this.inicio,
      fim: fim ?? this.fim,
      duracaoS: duracaoS ?? this.duracaoS,
      encerramento: encerramento ?? this.encerramento,
      nivelMaximo: nivelMaximo ?? this.nivelMaximo,
      probabilidadeMaxima: probabilidadeMaxima ?? this.probabilidadeMaxima,
      gatilhoTipo: gatilhoTipo ?? this.gatilhoTipo,
      gatilhoTexto: gatilhoTexto ?? this.gatilhoTexto,
      avaliacao: avaliacao ?? this.avaliacao,
      observacao: observacao ?? this.observacao,
      avaliacaoOrigem: avaliacaoOrigem ?? this.avaliacaoOrigem,
      avaliacaoEm: avaliacaoEm ?? this.avaliacaoEm,
      vistoEm: vistoEm ?? this.vistoEm,
      recebidoEm: recebidoEm ?? this.recebidoEm,
      naPulseira: naPulseira ?? this.naPulseira,
      avaliacaoLocal: avaliacaoLocal ?? this.avaliacaoLocal,
      observacaoLocal: observacaoLocal ?? this.observacaoLocal,
      avaliacaoLocalEm: avaliacaoLocalEm ?? this.avaliacaoLocalEm,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (crianca.present) {
      map['crianca'] = Variable<String>(crianca.value);
    }
    if (fonte.present) {
      map['fonte'] = Variable<String>(fonte.value);
    }
    if (inicio.present) {
      map['inicio'] = Variable<int>(inicio.value);
    }
    if (fim.present) {
      map['fim'] = Variable<int>(fim.value);
    }
    if (duracaoS.present) {
      map['duracao_s'] = Variable<double>(duracaoS.value);
    }
    if (encerramento.present) {
      map['encerramento'] = Variable<String>(encerramento.value);
    }
    if (nivelMaximo.present) {
      map['nivel_maximo'] = Variable<String>(nivelMaximo.value);
    }
    if (probabilidadeMaxima.present) {
      map['probabilidade_maxima'] = Variable<double>(probabilidadeMaxima.value);
    }
    if (gatilhoTipo.present) {
      map['gatilho_tipo'] = Variable<String>(gatilhoTipo.value);
    }
    if (gatilhoTexto.present) {
      map['gatilho_texto'] = Variable<String>(gatilhoTexto.value);
    }
    if (avaliacao.present) {
      map['avaliacao'] = Variable<String>(avaliacao.value);
    }
    if (observacao.present) {
      map['observacao'] = Variable<String>(observacao.value);
    }
    if (avaliacaoOrigem.present) {
      map['avaliacao_origem'] = Variable<String>(avaliacaoOrigem.value);
    }
    if (avaliacaoEm.present) {
      map['avaliacao_em'] = Variable<int>(avaliacaoEm.value);
    }
    if (vistoEm.present) {
      map['visto_em'] = Variable<int>(vistoEm.value);
    }
    if (recebidoEm.present) {
      map['recebido_em'] = Variable<int>(recebidoEm.value);
    }
    if (naPulseira.present) {
      map['na_pulseira'] = Variable<bool>(naPulseira.value);
    }
    if (avaliacaoLocal.present) {
      map['avaliacao_local'] = Variable<String>(avaliacaoLocal.value);
    }
    if (observacaoLocal.present) {
      map['observacao_local'] = Variable<String>(observacaoLocal.value);
    }
    if (avaliacaoLocalEm.present) {
      map['avaliacao_local_em'] = Variable<int>(avaliacaoLocalEm.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EpisodiosCompanion(')
          ..write('id: $id, ')
          ..write('crianca: $crianca, ')
          ..write('fonte: $fonte, ')
          ..write('inicio: $inicio, ')
          ..write('fim: $fim, ')
          ..write('duracaoS: $duracaoS, ')
          ..write('encerramento: $encerramento, ')
          ..write('nivelMaximo: $nivelMaximo, ')
          ..write('probabilidadeMaxima: $probabilidadeMaxima, ')
          ..write('gatilhoTipo: $gatilhoTipo, ')
          ..write('gatilhoTexto: $gatilhoTexto, ')
          ..write('avaliacao: $avaliacao, ')
          ..write('observacao: $observacao, ')
          ..write('avaliacaoOrigem: $avaliacaoOrigem, ')
          ..write('avaliacaoEm: $avaliacaoEm, ')
          ..write('vistoEm: $vistoEm, ')
          ..write('recebidoEm: $recebidoEm, ')
          ..write('naPulseira: $naPulseira, ')
          ..write('avaliacaoLocal: $avaliacaoLocal, ')
          ..write('observacaoLocal: $observacaoLocal, ')
          ..write('avaliacaoLocalEm: $avaliacaoLocalEm, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LembretesTable extends Lembretes
    with TableInfo<$LembretesTable, LinhaLembrete> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LembretesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _chaveMeta = const VerificationMeta('chave');
  @override
  late final GeneratedColumn<String> chave = GeneratedColumn<String>(
    'chave',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _textoMeta = const VerificationMeta('texto');
  @override
  late final GeneratedColumn<String> texto = GeneratedColumn<String>(
    'texto',
    aliasedName,
    false,
    check: () => ComparableExpr(texto.length).isSmallerOrEqualValue(120),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _salvoEmMeta = const VerificationMeta(
    'salvoEm',
  );
  @override
  late final GeneratedColumn<int> salvoEm = GeneratedColumn<int>(
    'salvo_em',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _avisarEmMeta = const VerificationMeta(
    'avisarEm',
  );
  @override
  late final GeneratedColumn<int> avisarEm = GeneratedColumn<int>(
    'avisar_em',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [chave, texto, salvoEm, avisarEm];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lembretes';
  @override
  VerificationContext validateIntegrity(
    Insertable<LinhaLembrete> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('chave')) {
      context.handle(
        _chaveMeta,
        chave.isAcceptableOrUnknown(data['chave']!, _chaveMeta),
      );
    } else if (isInserting) {
      context.missing(_chaveMeta);
    }
    if (data.containsKey('texto')) {
      context.handle(
        _textoMeta,
        texto.isAcceptableOrUnknown(data['texto']!, _textoMeta),
      );
    } else if (isInserting) {
      context.missing(_textoMeta);
    }
    if (data.containsKey('salvo_em')) {
      context.handle(
        _salvoEmMeta,
        salvoEm.isAcceptableOrUnknown(data['salvo_em']!, _salvoEmMeta),
      );
    } else if (isInserting) {
      context.missing(_salvoEmMeta);
    }
    if (data.containsKey('avisar_em')) {
      context.handle(
        _avisarEmMeta,
        avisarEm.isAcceptableOrUnknown(data['avisar_em']!, _avisarEmMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {chave};
  @override
  LinhaLembrete map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LinhaLembrete(
      chave:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}chave'],
          )!,
      texto:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}texto'],
          )!,
      salvoEm:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}salvo_em'],
          )!,
      avisarEm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}avisar_em'],
      ),
    );
  }

  @override
  $LembretesTable createAlias(String alias) {
    return $LembretesTable(attachedDatabase, alias);
  }
}

class LinhaLembrete extends DataClass implements Insertable<LinhaLembrete> {
  final String chave;
  final String texto;
  final int salvoEm;
  final int? avisarEm;
  const LinhaLembrete({
    required this.chave,
    required this.texto,
    required this.salvoEm,
    this.avisarEm,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['chave'] = Variable<String>(chave);
    map['texto'] = Variable<String>(texto);
    map['salvo_em'] = Variable<int>(salvoEm);
    if (!nullToAbsent || avisarEm != null) {
      map['avisar_em'] = Variable<int>(avisarEm);
    }
    return map;
  }

  LembretesCompanion toCompanion(bool nullToAbsent) {
    return LembretesCompanion(
      chave: Value(chave),
      texto: Value(texto),
      salvoEm: Value(salvoEm),
      avisarEm:
          avisarEm == null && nullToAbsent
              ? const Value.absent()
              : Value(avisarEm),
    );
  }

  factory LinhaLembrete.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LinhaLembrete(
      chave: serializer.fromJson<String>(json['chave']),
      texto: serializer.fromJson<String>(json['texto']),
      salvoEm: serializer.fromJson<int>(json['salvoEm']),
      avisarEm: serializer.fromJson<int?>(json['avisarEm']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'chave': serializer.toJson<String>(chave),
      'texto': serializer.toJson<String>(texto),
      'salvoEm': serializer.toJson<int>(salvoEm),
      'avisarEm': serializer.toJson<int?>(avisarEm),
    };
  }

  LinhaLembrete copyWith({
    String? chave,
    String? texto,
    int? salvoEm,
    Value<int?> avisarEm = const Value.absent(),
  }) => LinhaLembrete(
    chave: chave ?? this.chave,
    texto: texto ?? this.texto,
    salvoEm: salvoEm ?? this.salvoEm,
    avisarEm: avisarEm.present ? avisarEm.value : this.avisarEm,
  );
  LinhaLembrete copyWithCompanion(LembretesCompanion data) {
    return LinhaLembrete(
      chave: data.chave.present ? data.chave.value : this.chave,
      texto: data.texto.present ? data.texto.value : this.texto,
      salvoEm: data.salvoEm.present ? data.salvoEm.value : this.salvoEm,
      avisarEm: data.avisarEm.present ? data.avisarEm.value : this.avisarEm,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LinhaLembrete(')
          ..write('chave: $chave, ')
          ..write('texto: $texto, ')
          ..write('salvoEm: $salvoEm, ')
          ..write('avisarEm: $avisarEm')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(chave, texto, salvoEm, avisarEm);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LinhaLembrete &&
          other.chave == this.chave &&
          other.texto == this.texto &&
          other.salvoEm == this.salvoEm &&
          other.avisarEm == this.avisarEm);
}

class LembretesCompanion extends UpdateCompanion<LinhaLembrete> {
  final Value<String> chave;
  final Value<String> texto;
  final Value<int> salvoEm;
  final Value<int?> avisarEm;
  final Value<int> rowid;
  const LembretesCompanion({
    this.chave = const Value.absent(),
    this.texto = const Value.absent(),
    this.salvoEm = const Value.absent(),
    this.avisarEm = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LembretesCompanion.insert({
    required String chave,
    required String texto,
    required int salvoEm,
    this.avisarEm = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : chave = Value(chave),
       texto = Value(texto),
       salvoEm = Value(salvoEm);
  static Insertable<LinhaLembrete> custom({
    Expression<String>? chave,
    Expression<String>? texto,
    Expression<int>? salvoEm,
    Expression<int>? avisarEm,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (chave != null) 'chave': chave,
      if (texto != null) 'texto': texto,
      if (salvoEm != null) 'salvo_em': salvoEm,
      if (avisarEm != null) 'avisar_em': avisarEm,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LembretesCompanion copyWith({
    Value<String>? chave,
    Value<String>? texto,
    Value<int>? salvoEm,
    Value<int?>? avisarEm,
    Value<int>? rowid,
  }) {
    return LembretesCompanion(
      chave: chave ?? this.chave,
      texto: texto ?? this.texto,
      salvoEm: salvoEm ?? this.salvoEm,
      avisarEm: avisarEm ?? this.avisarEm,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (chave.present) {
      map['chave'] = Variable<String>(chave.value);
    }
    if (texto.present) {
      map['texto'] = Variable<String>(texto.value);
    }
    if (salvoEm.present) {
      map['salvo_em'] = Variable<int>(salvoEm.value);
    }
    if (avisarEm.present) {
      map['avisar_em'] = Variable<int>(avisarEm.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LembretesCompanion(')
          ..write('chave: $chave, ')
          ..write('texto: $texto, ')
          ..write('salvoEm: $salvoEm, ')
          ..write('avisarEm: $avisarEm, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EpisodiosNotificadosTable extends EpisodiosNotificados
    with TableInfo<$EpisodiosNotificadosTable, LinhaNotificado> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EpisodiosNotificadosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _episodioIdMeta = const VerificationMeta(
    'episodioId',
  );
  @override
  late final GeneratedColumn<String> episodioId = GeneratedColumn<String>(
    'episodio_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nivelMeta = const VerificationMeta('nivel');
  @override
  late final GeneratedColumn<String> nivel = GeneratedColumn<String>(
    'nivel',
    aliasedName,
    false,
    check: () => nivel.isIn(niveisValidos),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parDeCanaisMeta = const VerificationMeta(
    'parDeCanais',
  );
  @override
  late final GeneratedColumn<String> parDeCanais = GeneratedColumn<String>(
    'par_de_canais',
    aliasedName,
    false,
    check: () => parDeCanais.isIn(paresDeCanais),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notificadoEmMeta = const VerificationMeta(
    'notificadoEm',
  );
  @override
  late final GeneratedColumn<int> notificadoEm = GeneratedColumn<int>(
    'notificado_em',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vezesMeta = const VerificationMeta('vezes');
  @override
  late final GeneratedColumn<int> vezes = GeneratedColumn<int>(
    'vezes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    episodioId,
    nivel,
    parDeCanais,
    notificadoEm,
    vezes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'episodios_notificados';
  @override
  VerificationContext validateIntegrity(
    Insertable<LinhaNotificado> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('episodio_id')) {
      context.handle(
        _episodioIdMeta,
        episodioId.isAcceptableOrUnknown(data['episodio_id']!, _episodioIdMeta),
      );
    } else if (isInserting) {
      context.missing(_episodioIdMeta);
    }
    if (data.containsKey('nivel')) {
      context.handle(
        _nivelMeta,
        nivel.isAcceptableOrUnknown(data['nivel']!, _nivelMeta),
      );
    } else if (isInserting) {
      context.missing(_nivelMeta);
    }
    if (data.containsKey('par_de_canais')) {
      context.handle(
        _parDeCanaisMeta,
        parDeCanais.isAcceptableOrUnknown(
          data['par_de_canais']!,
          _parDeCanaisMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_parDeCanaisMeta);
    }
    if (data.containsKey('notificado_em')) {
      context.handle(
        _notificadoEmMeta,
        notificadoEm.isAcceptableOrUnknown(
          data['notificado_em']!,
          _notificadoEmMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_notificadoEmMeta);
    }
    if (data.containsKey('vezes')) {
      context.handle(
        _vezesMeta,
        vezes.isAcceptableOrUnknown(data['vezes']!, _vezesMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {episodioId};
  @override
  LinhaNotificado map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LinhaNotificado(
      episodioId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}episodio_id'],
          )!,
      nivel:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}nivel'],
          )!,
      parDeCanais:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}par_de_canais'],
          )!,
      notificadoEm:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}notificado_em'],
          )!,
      vezes:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}vezes'],
          )!,
    );
  }

  @override
  $EpisodiosNotificadosTable createAlias(String alias) {
    return $EpisodiosNotificadosTable(attachedDatabase, alias);
  }
}

class LinhaNotificado extends DataClass implements Insertable<LinhaNotificado> {
  final String episodioId;
  final String nivel;
  final String parDeCanais;
  final int notificadoEm;

  /// Quantas vezes notificou (1 = so a primeira; mais = houve subida).
  final int vezes;
  const LinhaNotificado({
    required this.episodioId,
    required this.nivel,
    required this.parDeCanais,
    required this.notificadoEm,
    required this.vezes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['episodio_id'] = Variable<String>(episodioId);
    map['nivel'] = Variable<String>(nivel);
    map['par_de_canais'] = Variable<String>(parDeCanais);
    map['notificado_em'] = Variable<int>(notificadoEm);
    map['vezes'] = Variable<int>(vezes);
    return map;
  }

  EpisodiosNotificadosCompanion toCompanion(bool nullToAbsent) {
    return EpisodiosNotificadosCompanion(
      episodioId: Value(episodioId),
      nivel: Value(nivel),
      parDeCanais: Value(parDeCanais),
      notificadoEm: Value(notificadoEm),
      vezes: Value(vezes),
    );
  }

  factory LinhaNotificado.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LinhaNotificado(
      episodioId: serializer.fromJson<String>(json['episodioId']),
      nivel: serializer.fromJson<String>(json['nivel']),
      parDeCanais: serializer.fromJson<String>(json['parDeCanais']),
      notificadoEm: serializer.fromJson<int>(json['notificadoEm']),
      vezes: serializer.fromJson<int>(json['vezes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'episodioId': serializer.toJson<String>(episodioId),
      'nivel': serializer.toJson<String>(nivel),
      'parDeCanais': serializer.toJson<String>(parDeCanais),
      'notificadoEm': serializer.toJson<int>(notificadoEm),
      'vezes': serializer.toJson<int>(vezes),
    };
  }

  LinhaNotificado copyWith({
    String? episodioId,
    String? nivel,
    String? parDeCanais,
    int? notificadoEm,
    int? vezes,
  }) => LinhaNotificado(
    episodioId: episodioId ?? this.episodioId,
    nivel: nivel ?? this.nivel,
    parDeCanais: parDeCanais ?? this.parDeCanais,
    notificadoEm: notificadoEm ?? this.notificadoEm,
    vezes: vezes ?? this.vezes,
  );
  LinhaNotificado copyWithCompanion(EpisodiosNotificadosCompanion data) {
    return LinhaNotificado(
      episodioId:
          data.episodioId.present ? data.episodioId.value : this.episodioId,
      nivel: data.nivel.present ? data.nivel.value : this.nivel,
      parDeCanais:
          data.parDeCanais.present ? data.parDeCanais.value : this.parDeCanais,
      notificadoEm:
          data.notificadoEm.present
              ? data.notificadoEm.value
              : this.notificadoEm,
      vezes: data.vezes.present ? data.vezes.value : this.vezes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LinhaNotificado(')
          ..write('episodioId: $episodioId, ')
          ..write('nivel: $nivel, ')
          ..write('parDeCanais: $parDeCanais, ')
          ..write('notificadoEm: $notificadoEm, ')
          ..write('vezes: $vezes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(episodioId, nivel, parDeCanais, notificadoEm, vezes);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LinhaNotificado &&
          other.episodioId == this.episodioId &&
          other.nivel == this.nivel &&
          other.parDeCanais == this.parDeCanais &&
          other.notificadoEm == this.notificadoEm &&
          other.vezes == this.vezes);
}

class EpisodiosNotificadosCompanion extends UpdateCompanion<LinhaNotificado> {
  final Value<String> episodioId;
  final Value<String> nivel;
  final Value<String> parDeCanais;
  final Value<int> notificadoEm;
  final Value<int> vezes;
  final Value<int> rowid;
  const EpisodiosNotificadosCompanion({
    this.episodioId = const Value.absent(),
    this.nivel = const Value.absent(),
    this.parDeCanais = const Value.absent(),
    this.notificadoEm = const Value.absent(),
    this.vezes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EpisodiosNotificadosCompanion.insert({
    required String episodioId,
    required String nivel,
    required String parDeCanais,
    required int notificadoEm,
    this.vezes = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : episodioId = Value(episodioId),
       nivel = Value(nivel),
       parDeCanais = Value(parDeCanais),
       notificadoEm = Value(notificadoEm);
  static Insertable<LinhaNotificado> custom({
    Expression<String>? episodioId,
    Expression<String>? nivel,
    Expression<String>? parDeCanais,
    Expression<int>? notificadoEm,
    Expression<int>? vezes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (episodioId != null) 'episodio_id': episodioId,
      if (nivel != null) 'nivel': nivel,
      if (parDeCanais != null) 'par_de_canais': parDeCanais,
      if (notificadoEm != null) 'notificado_em': notificadoEm,
      if (vezes != null) 'vezes': vezes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EpisodiosNotificadosCompanion copyWith({
    Value<String>? episodioId,
    Value<String>? nivel,
    Value<String>? parDeCanais,
    Value<int>? notificadoEm,
    Value<int>? vezes,
    Value<int>? rowid,
  }) {
    return EpisodiosNotificadosCompanion(
      episodioId: episodioId ?? this.episodioId,
      nivel: nivel ?? this.nivel,
      parDeCanais: parDeCanais ?? this.parDeCanais,
      notificadoEm: notificadoEm ?? this.notificadoEm,
      vezes: vezes ?? this.vezes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (episodioId.present) {
      map['episodio_id'] = Variable<String>(episodioId.value);
    }
    if (nivel.present) {
      map['nivel'] = Variable<String>(nivel.value);
    }
    if (parDeCanais.present) {
      map['par_de_canais'] = Variable<String>(parDeCanais.value);
    }
    if (notificadoEm.present) {
      map['notificado_em'] = Variable<int>(notificadoEm.value);
    }
    if (vezes.present) {
      map['vezes'] = Variable<int>(vezes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EpisodiosNotificadosCompanion(')
          ..write('episodioId: $episodioId, ')
          ..write('nivel: $nivel, ')
          ..write('parDeCanais: $parDeCanais, ')
          ..write('notificadoEm: $notificadoEm, ')
          ..write('vezes: $vezes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$BancoPuzzleBand extends GeneratedDatabase {
  _$BancoPuzzleBand(QueryExecutor e) : super(e);
  $BancoPuzzleBandManager get managers => $BancoPuzzleBandManager(this);
  late final $EpisodiosTable episodios = $EpisodiosTable(this);
  late final $LembretesTable lembretes = $LembretesTable(this);
  late final $EpisodiosNotificadosTable episodiosNotificados =
      $EpisodiosNotificadosTable(this);
  late final Index idxEpisodiosInicio = Index(
    'idx_episodios_inicio',
    'CREATE INDEX IF NOT EXISTS idx_episodios_inicio ON episodios (inicio)',
  );
  late final Index idxLembretesSalvoEm = Index(
    'idx_lembretes_salvo_em',
    'CREATE INDEX IF NOT EXISTS idx_lembretes_salvo_em ON lembretes (salvo_em)',
  );
  late final Index idxNotificadosEm = Index(
    'idx_notificados_em',
    'CREATE INDEX IF NOT EXISTS idx_notificados_em ON episodios_notificados (notificado_em)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    episodios,
    lembretes,
    episodiosNotificados,
    idxEpisodiosInicio,
    idxLembretesSalvoEm,
    idxNotificadosEm,
  ];
}

typedef $$EpisodiosTableCreateCompanionBuilder =
    EpisodiosCompanion Function({
      required String id,
      Value<String?> crianca,
      Value<String?> fonte,
      required int inicio,
      Value<int?> fim,
      Value<double?> duracaoS,
      Value<String?> encerramento,
      required String nivelMaximo,
      Value<double?> probabilidadeMaxima,
      Value<String?> gatilhoTipo,
      Value<String?> gatilhoTexto,
      Value<String> avaliacao,
      Value<String> observacao,
      Value<String?> avaliacaoOrigem,
      Value<int?> avaliacaoEm,
      Value<int?> vistoEm,
      required int recebidoEm,
      Value<bool> naPulseira,
      Value<String?> avaliacaoLocal,
      Value<String?> observacaoLocal,
      Value<int?> avaliacaoLocalEm,
      Value<int> rowid,
    });
typedef $$EpisodiosTableUpdateCompanionBuilder =
    EpisodiosCompanion Function({
      Value<String> id,
      Value<String?> crianca,
      Value<String?> fonte,
      Value<int> inicio,
      Value<int?> fim,
      Value<double?> duracaoS,
      Value<String?> encerramento,
      Value<String> nivelMaximo,
      Value<double?> probabilidadeMaxima,
      Value<String?> gatilhoTipo,
      Value<String?> gatilhoTexto,
      Value<String> avaliacao,
      Value<String> observacao,
      Value<String?> avaliacaoOrigem,
      Value<int?> avaliacaoEm,
      Value<int?> vistoEm,
      Value<int> recebidoEm,
      Value<bool> naPulseira,
      Value<String?> avaliacaoLocal,
      Value<String?> observacaoLocal,
      Value<int?> avaliacaoLocalEm,
      Value<int> rowid,
    });

class $$EpisodiosTableFilterComposer
    extends Composer<_$BancoPuzzleBand, $EpisodiosTable> {
  $$EpisodiosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get crianca => $composableBuilder(
    column: $table.crianca,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fonte => $composableBuilder(
    column: $table.fonte,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get inicio => $composableBuilder(
    column: $table.inicio,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fim => $composableBuilder(
    column: $table.fim,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get duracaoS => $composableBuilder(
    column: $table.duracaoS,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encerramento => $composableBuilder(
    column: $table.encerramento,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nivelMaximo => $composableBuilder(
    column: $table.nivelMaximo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get probabilidadeMaxima => $composableBuilder(
    column: $table.probabilidadeMaxima,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gatilhoTipo => $composableBuilder(
    column: $table.gatilhoTipo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gatilhoTexto => $composableBuilder(
    column: $table.gatilhoTexto,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avaliacao => $composableBuilder(
    column: $table.avaliacao,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get observacao => $composableBuilder(
    column: $table.observacao,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avaliacaoOrigem => $composableBuilder(
    column: $table.avaliacaoOrigem,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get avaliacaoEm => $composableBuilder(
    column: $table.avaliacaoEm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get vistoEm => $composableBuilder(
    column: $table.vistoEm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recebidoEm => $composableBuilder(
    column: $table.recebidoEm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get naPulseira => $composableBuilder(
    column: $table.naPulseira,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avaliacaoLocal => $composableBuilder(
    column: $table.avaliacaoLocal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get observacaoLocal => $composableBuilder(
    column: $table.observacaoLocal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get avaliacaoLocalEm => $composableBuilder(
    column: $table.avaliacaoLocalEm,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EpisodiosTableOrderingComposer
    extends Composer<_$BancoPuzzleBand, $EpisodiosTable> {
  $$EpisodiosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get crianca => $composableBuilder(
    column: $table.crianca,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fonte => $composableBuilder(
    column: $table.fonte,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get inicio => $composableBuilder(
    column: $table.inicio,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fim => $composableBuilder(
    column: $table.fim,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get duracaoS => $composableBuilder(
    column: $table.duracaoS,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encerramento => $composableBuilder(
    column: $table.encerramento,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nivelMaximo => $composableBuilder(
    column: $table.nivelMaximo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get probabilidadeMaxima => $composableBuilder(
    column: $table.probabilidadeMaxima,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gatilhoTipo => $composableBuilder(
    column: $table.gatilhoTipo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gatilhoTexto => $composableBuilder(
    column: $table.gatilhoTexto,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avaliacao => $composableBuilder(
    column: $table.avaliacao,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get observacao => $composableBuilder(
    column: $table.observacao,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avaliacaoOrigem => $composableBuilder(
    column: $table.avaliacaoOrigem,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get avaliacaoEm => $composableBuilder(
    column: $table.avaliacaoEm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get vistoEm => $composableBuilder(
    column: $table.vistoEm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recebidoEm => $composableBuilder(
    column: $table.recebidoEm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get naPulseira => $composableBuilder(
    column: $table.naPulseira,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avaliacaoLocal => $composableBuilder(
    column: $table.avaliacaoLocal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get observacaoLocal => $composableBuilder(
    column: $table.observacaoLocal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get avaliacaoLocalEm => $composableBuilder(
    column: $table.avaliacaoLocalEm,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EpisodiosTableAnnotationComposer
    extends Composer<_$BancoPuzzleBand, $EpisodiosTable> {
  $$EpisodiosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get crianca =>
      $composableBuilder(column: $table.crianca, builder: (column) => column);

  GeneratedColumn<String> get fonte =>
      $composableBuilder(column: $table.fonte, builder: (column) => column);

  GeneratedColumn<int> get inicio =>
      $composableBuilder(column: $table.inicio, builder: (column) => column);

  GeneratedColumn<int> get fim =>
      $composableBuilder(column: $table.fim, builder: (column) => column);

  GeneratedColumn<double> get duracaoS =>
      $composableBuilder(column: $table.duracaoS, builder: (column) => column);

  GeneratedColumn<String> get encerramento => $composableBuilder(
    column: $table.encerramento,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nivelMaximo => $composableBuilder(
    column: $table.nivelMaximo,
    builder: (column) => column,
  );

  GeneratedColumn<double> get probabilidadeMaxima => $composableBuilder(
    column: $table.probabilidadeMaxima,
    builder: (column) => column,
  );

  GeneratedColumn<String> get gatilhoTipo => $composableBuilder(
    column: $table.gatilhoTipo,
    builder: (column) => column,
  );

  GeneratedColumn<String> get gatilhoTexto => $composableBuilder(
    column: $table.gatilhoTexto,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avaliacao =>
      $composableBuilder(column: $table.avaliacao, builder: (column) => column);

  GeneratedColumn<String> get observacao => $composableBuilder(
    column: $table.observacao,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avaliacaoOrigem => $composableBuilder(
    column: $table.avaliacaoOrigem,
    builder: (column) => column,
  );

  GeneratedColumn<int> get avaliacaoEm => $composableBuilder(
    column: $table.avaliacaoEm,
    builder: (column) => column,
  );

  GeneratedColumn<int> get vistoEm =>
      $composableBuilder(column: $table.vistoEm, builder: (column) => column);

  GeneratedColumn<int> get recebidoEm => $composableBuilder(
    column: $table.recebidoEm,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get naPulseira => $composableBuilder(
    column: $table.naPulseira,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avaliacaoLocal => $composableBuilder(
    column: $table.avaliacaoLocal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get observacaoLocal => $composableBuilder(
    column: $table.observacaoLocal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get avaliacaoLocalEm => $composableBuilder(
    column: $table.avaliacaoLocalEm,
    builder: (column) => column,
  );
}

class $$EpisodiosTableTableManager
    extends
        RootTableManager<
          _$BancoPuzzleBand,
          $EpisodiosTable,
          LinhaEpisodio,
          $$EpisodiosTableFilterComposer,
          $$EpisodiosTableOrderingComposer,
          $$EpisodiosTableAnnotationComposer,
          $$EpisodiosTableCreateCompanionBuilder,
          $$EpisodiosTableUpdateCompanionBuilder,
          (
            LinhaEpisodio,
            BaseReferences<_$BancoPuzzleBand, $EpisodiosTable, LinhaEpisodio>,
          ),
          LinhaEpisodio,
          PrefetchHooks Function()
        > {
  $$EpisodiosTableTableManager(_$BancoPuzzleBand db, $EpisodiosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$EpisodiosTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$EpisodiosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$EpisodiosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> crianca = const Value.absent(),
                Value<String?> fonte = const Value.absent(),
                Value<int> inicio = const Value.absent(),
                Value<int?> fim = const Value.absent(),
                Value<double?> duracaoS = const Value.absent(),
                Value<String?> encerramento = const Value.absent(),
                Value<String> nivelMaximo = const Value.absent(),
                Value<double?> probabilidadeMaxima = const Value.absent(),
                Value<String?> gatilhoTipo = const Value.absent(),
                Value<String?> gatilhoTexto = const Value.absent(),
                Value<String> avaliacao = const Value.absent(),
                Value<String> observacao = const Value.absent(),
                Value<String?> avaliacaoOrigem = const Value.absent(),
                Value<int?> avaliacaoEm = const Value.absent(),
                Value<int?> vistoEm = const Value.absent(),
                Value<int> recebidoEm = const Value.absent(),
                Value<bool> naPulseira = const Value.absent(),
                Value<String?> avaliacaoLocal = const Value.absent(),
                Value<String?> observacaoLocal = const Value.absent(),
                Value<int?> avaliacaoLocalEm = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EpisodiosCompanion(
                id: id,
                crianca: crianca,
                fonte: fonte,
                inicio: inicio,
                fim: fim,
                duracaoS: duracaoS,
                encerramento: encerramento,
                nivelMaximo: nivelMaximo,
                probabilidadeMaxima: probabilidadeMaxima,
                gatilhoTipo: gatilhoTipo,
                gatilhoTexto: gatilhoTexto,
                avaliacao: avaliacao,
                observacao: observacao,
                avaliacaoOrigem: avaliacaoOrigem,
                avaliacaoEm: avaliacaoEm,
                vistoEm: vistoEm,
                recebidoEm: recebidoEm,
                naPulseira: naPulseira,
                avaliacaoLocal: avaliacaoLocal,
                observacaoLocal: observacaoLocal,
                avaliacaoLocalEm: avaliacaoLocalEm,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> crianca = const Value.absent(),
                Value<String?> fonte = const Value.absent(),
                required int inicio,
                Value<int?> fim = const Value.absent(),
                Value<double?> duracaoS = const Value.absent(),
                Value<String?> encerramento = const Value.absent(),
                required String nivelMaximo,
                Value<double?> probabilidadeMaxima = const Value.absent(),
                Value<String?> gatilhoTipo = const Value.absent(),
                Value<String?> gatilhoTexto = const Value.absent(),
                Value<String> avaliacao = const Value.absent(),
                Value<String> observacao = const Value.absent(),
                Value<String?> avaliacaoOrigem = const Value.absent(),
                Value<int?> avaliacaoEm = const Value.absent(),
                Value<int?> vistoEm = const Value.absent(),
                required int recebidoEm,
                Value<bool> naPulseira = const Value.absent(),
                Value<String?> avaliacaoLocal = const Value.absent(),
                Value<String?> observacaoLocal = const Value.absent(),
                Value<int?> avaliacaoLocalEm = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EpisodiosCompanion.insert(
                id: id,
                crianca: crianca,
                fonte: fonte,
                inicio: inicio,
                fim: fim,
                duracaoS: duracaoS,
                encerramento: encerramento,
                nivelMaximo: nivelMaximo,
                probabilidadeMaxima: probabilidadeMaxima,
                gatilhoTipo: gatilhoTipo,
                gatilhoTexto: gatilhoTexto,
                avaliacao: avaliacao,
                observacao: observacao,
                avaliacaoOrigem: avaliacaoOrigem,
                avaliacaoEm: avaliacaoEm,
                vistoEm: vistoEm,
                recebidoEm: recebidoEm,
                naPulseira: naPulseira,
                avaliacaoLocal: avaliacaoLocal,
                observacaoLocal: observacaoLocal,
                avaliacaoLocalEm: avaliacaoLocalEm,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable<$EpisodiosTable, LinhaEpisodio>(table),
                          BaseReferences<
                            _$BancoPuzzleBand,
                            $EpisodiosTable,
                            LinhaEpisodio
                          >(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EpisodiosTableProcessedTableManager =
    ProcessedTableManager<
      _$BancoPuzzleBand,
      $EpisodiosTable,
      LinhaEpisodio,
      $$EpisodiosTableFilterComposer,
      $$EpisodiosTableOrderingComposer,
      $$EpisodiosTableAnnotationComposer,
      $$EpisodiosTableCreateCompanionBuilder,
      $$EpisodiosTableUpdateCompanionBuilder,
      (
        LinhaEpisodio,
        BaseReferences<_$BancoPuzzleBand, $EpisodiosTable, LinhaEpisodio>,
      ),
      LinhaEpisodio,
      PrefetchHooks Function()
    >;
typedef $$LembretesTableCreateCompanionBuilder =
    LembretesCompanion Function({
      required String chave,
      required String texto,
      required int salvoEm,
      Value<int?> avisarEm,
      Value<int> rowid,
    });
typedef $$LembretesTableUpdateCompanionBuilder =
    LembretesCompanion Function({
      Value<String> chave,
      Value<String> texto,
      Value<int> salvoEm,
      Value<int?> avisarEm,
      Value<int> rowid,
    });

class $$LembretesTableFilterComposer
    extends Composer<_$BancoPuzzleBand, $LembretesTable> {
  $$LembretesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get chave => $composableBuilder(
    column: $table.chave,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get texto => $composableBuilder(
    column: $table.texto,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get salvoEm => $composableBuilder(
    column: $table.salvoEm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get avisarEm => $composableBuilder(
    column: $table.avisarEm,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LembretesTableOrderingComposer
    extends Composer<_$BancoPuzzleBand, $LembretesTable> {
  $$LembretesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get chave => $composableBuilder(
    column: $table.chave,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get texto => $composableBuilder(
    column: $table.texto,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get salvoEm => $composableBuilder(
    column: $table.salvoEm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get avisarEm => $composableBuilder(
    column: $table.avisarEm,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LembretesTableAnnotationComposer
    extends Composer<_$BancoPuzzleBand, $LembretesTable> {
  $$LembretesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get chave =>
      $composableBuilder(column: $table.chave, builder: (column) => column);

  GeneratedColumn<String> get texto =>
      $composableBuilder(column: $table.texto, builder: (column) => column);

  GeneratedColumn<int> get salvoEm =>
      $composableBuilder(column: $table.salvoEm, builder: (column) => column);

  GeneratedColumn<int> get avisarEm =>
      $composableBuilder(column: $table.avisarEm, builder: (column) => column);
}

class $$LembretesTableTableManager
    extends
        RootTableManager<
          _$BancoPuzzleBand,
          $LembretesTable,
          LinhaLembrete,
          $$LembretesTableFilterComposer,
          $$LembretesTableOrderingComposer,
          $$LembretesTableAnnotationComposer,
          $$LembretesTableCreateCompanionBuilder,
          $$LembretesTableUpdateCompanionBuilder,
          (
            LinhaLembrete,
            BaseReferences<_$BancoPuzzleBand, $LembretesTable, LinhaLembrete>,
          ),
          LinhaLembrete,
          PrefetchHooks Function()
        > {
  $$LembretesTableTableManager(_$BancoPuzzleBand db, $LembretesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$LembretesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$LembretesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$LembretesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> chave = const Value.absent(),
                Value<String> texto = const Value.absent(),
                Value<int> salvoEm = const Value.absent(),
                Value<int?> avisarEm = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LembretesCompanion(
                chave: chave,
                texto: texto,
                salvoEm: salvoEm,
                avisarEm: avisarEm,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String chave,
                required String texto,
                required int salvoEm,
                Value<int?> avisarEm = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LembretesCompanion.insert(
                chave: chave,
                texto: texto,
                salvoEm: salvoEm,
                avisarEm: avisarEm,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable<$LembretesTable, LinhaLembrete>(table),
                          BaseReferences<
                            _$BancoPuzzleBand,
                            $LembretesTable,
                            LinhaLembrete
                          >(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LembretesTableProcessedTableManager =
    ProcessedTableManager<
      _$BancoPuzzleBand,
      $LembretesTable,
      LinhaLembrete,
      $$LembretesTableFilterComposer,
      $$LembretesTableOrderingComposer,
      $$LembretesTableAnnotationComposer,
      $$LembretesTableCreateCompanionBuilder,
      $$LembretesTableUpdateCompanionBuilder,
      (
        LinhaLembrete,
        BaseReferences<_$BancoPuzzleBand, $LembretesTable, LinhaLembrete>,
      ),
      LinhaLembrete,
      PrefetchHooks Function()
    >;
typedef $$EpisodiosNotificadosTableCreateCompanionBuilder =
    EpisodiosNotificadosCompanion Function({
      required String episodioId,
      required String nivel,
      required String parDeCanais,
      required int notificadoEm,
      Value<int> vezes,
      Value<int> rowid,
    });
typedef $$EpisodiosNotificadosTableUpdateCompanionBuilder =
    EpisodiosNotificadosCompanion Function({
      Value<String> episodioId,
      Value<String> nivel,
      Value<String> parDeCanais,
      Value<int> notificadoEm,
      Value<int> vezes,
      Value<int> rowid,
    });

class $$EpisodiosNotificadosTableFilterComposer
    extends Composer<_$BancoPuzzleBand, $EpisodiosNotificadosTable> {
  $$EpisodiosNotificadosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get episodioId => $composableBuilder(
    column: $table.episodioId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nivel => $composableBuilder(
    column: $table.nivel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parDeCanais => $composableBuilder(
    column: $table.parDeCanais,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get notificadoEm => $composableBuilder(
    column: $table.notificadoEm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get vezes => $composableBuilder(
    column: $table.vezes,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EpisodiosNotificadosTableOrderingComposer
    extends Composer<_$BancoPuzzleBand, $EpisodiosNotificadosTable> {
  $$EpisodiosNotificadosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get episodioId => $composableBuilder(
    column: $table.episodioId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nivel => $composableBuilder(
    column: $table.nivel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parDeCanais => $composableBuilder(
    column: $table.parDeCanais,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get notificadoEm => $composableBuilder(
    column: $table.notificadoEm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get vezes => $composableBuilder(
    column: $table.vezes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EpisodiosNotificadosTableAnnotationComposer
    extends Composer<_$BancoPuzzleBand, $EpisodiosNotificadosTable> {
  $$EpisodiosNotificadosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get episodioId => $composableBuilder(
    column: $table.episodioId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nivel =>
      $composableBuilder(column: $table.nivel, builder: (column) => column);

  GeneratedColumn<String> get parDeCanais => $composableBuilder(
    column: $table.parDeCanais,
    builder: (column) => column,
  );

  GeneratedColumn<int> get notificadoEm => $composableBuilder(
    column: $table.notificadoEm,
    builder: (column) => column,
  );

  GeneratedColumn<int> get vezes =>
      $composableBuilder(column: $table.vezes, builder: (column) => column);
}

class $$EpisodiosNotificadosTableTableManager
    extends
        RootTableManager<
          _$BancoPuzzleBand,
          $EpisodiosNotificadosTable,
          LinhaNotificado,
          $$EpisodiosNotificadosTableFilterComposer,
          $$EpisodiosNotificadosTableOrderingComposer,
          $$EpisodiosNotificadosTableAnnotationComposer,
          $$EpisodiosNotificadosTableCreateCompanionBuilder,
          $$EpisodiosNotificadosTableUpdateCompanionBuilder,
          (
            LinhaNotificado,
            BaseReferences<
              _$BancoPuzzleBand,
              $EpisodiosNotificadosTable,
              LinhaNotificado
            >,
          ),
          LinhaNotificado,
          PrefetchHooks Function()
        > {
  $$EpisodiosNotificadosTableTableManager(
    _$BancoPuzzleBand db,
    $EpisodiosNotificadosTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$EpisodiosNotificadosTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$EpisodiosNotificadosTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$EpisodiosNotificadosTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> episodioId = const Value.absent(),
                Value<String> nivel = const Value.absent(),
                Value<String> parDeCanais = const Value.absent(),
                Value<int> notificadoEm = const Value.absent(),
                Value<int> vezes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EpisodiosNotificadosCompanion(
                episodioId: episodioId,
                nivel: nivel,
                parDeCanais: parDeCanais,
                notificadoEm: notificadoEm,
                vezes: vezes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String episodioId,
                required String nivel,
                required String parDeCanais,
                required int notificadoEm,
                Value<int> vezes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EpisodiosNotificadosCompanion.insert(
                episodioId: episodioId,
                nivel: nivel,
                parDeCanais: parDeCanais,
                notificadoEm: notificadoEm,
                vezes: vezes,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable<
                            $EpisodiosNotificadosTable,
                            LinhaNotificado
                          >(table),
                          BaseReferences<
                            _$BancoPuzzleBand,
                            $EpisodiosNotificadosTable,
                            LinhaNotificado
                          >(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EpisodiosNotificadosTableProcessedTableManager =
    ProcessedTableManager<
      _$BancoPuzzleBand,
      $EpisodiosNotificadosTable,
      LinhaNotificado,
      $$EpisodiosNotificadosTableFilterComposer,
      $$EpisodiosNotificadosTableOrderingComposer,
      $$EpisodiosNotificadosTableAnnotationComposer,
      $$EpisodiosNotificadosTableCreateCompanionBuilder,
      $$EpisodiosNotificadosTableUpdateCompanionBuilder,
      (
        LinhaNotificado,
        BaseReferences<
          _$BancoPuzzleBand,
          $EpisodiosNotificadosTable,
          LinhaNotificado
        >,
      ),
      LinhaNotificado,
      PrefetchHooks Function()
    >;

class $BancoPuzzleBandManager {
  final _$BancoPuzzleBand _db;
  $BancoPuzzleBandManager(this._db);
  $$EpisodiosTableTableManager get episodios =>
      $$EpisodiosTableTableManager(_db, _db.episodios);
  $$LembretesTableTableManager get lembretes =>
      $$LembretesTableTableManager(_db, _db.lembretes);
  $$EpisodiosNotificadosTableTableManager get episodiosNotificados =>
      $$EpisodiosNotificadosTableTableManager(_db, _db.episodiosNotificados);
}

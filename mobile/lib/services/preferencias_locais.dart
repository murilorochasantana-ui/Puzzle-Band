// Dados que o cuidador escreve e que ficam SO neste celular
// (shared_preferences): o nome da crianca, os lembretes (de um episodio ou
// do dia) e a aparencia (claro, escuro ou seguir o sistema). Decisao de privacidade (docs/app.md): nada disto vai para o MQTT,
// para o painel (site) nem para outro aparelho.

import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/relogio.dart';
import 'aviso_de_lembrete.dart';
import 'notification_service.dart' show idDeNotificacao;

/// Lembrete curto do cuidador, com um aviso opcional no celular.
@immutable
class Lembrete {
  const Lembrete({required this.texto, required this.salvoEm, this.avisarEm});

  final String texto;
  final DateTime salvoEm;
  final DateTime? avisarEm;

  /// Aviso ainda por vir (os passados nao aparecem mais na tela).
  DateTime? avisoPendente(DateTime agora) {
    final aviso = avisarEm;
    return aviso != null && aviso.isAfter(agora) ? aviso : null;
  }

  Map<String, dynamic> toJson() => {
        'texto': texto,
        'salvo_em': salvoEm.toUtc().toIso8601String(),
        if (avisarEm != null) 'avisar_em': avisarEm!.toUtc().toIso8601String(),
      };

  static Lembrete? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final texto = json['texto'];
    final salvo = json['salvo_em'];
    if (texto is! String || texto.trim().isEmpty || salvo is! String) return null;
    final salvoEm = DateTime.tryParse(salvo)?.toLocal();
    if (salvoEm == null) return null;
    final aviso = json['avisar_em'];
    return Lembrete(
      texto: texto,
      salvoEm: salvoEm,
      avisarEm: aviso is String ? DateTime.tryParse(aviso)?.toLocal() : null,
    );
  }
}

/// Tema do app escolhido em Ajustes > Aparencia.
enum Aparencia {
  sistema('sistema', ThemeMode.system),
  claro('claro', ThemeMode.light),
  escuro('escuro', ThemeMode.dark);

  const Aparencia(this.codigo, this.themeMode);

  /// Valor salvo no shared_preferences.
  final String codigo;
  final ThemeMode themeMode;

  static Aparencia fromCodigo(String? codigo) =>
      Aparencia.values.firstWhere((a) => a.codigo == codigo, orElse: () => Aparencia.sistema);
}

/// Resultado de salvar um lembrete (para a mensagem na tela).
enum ResultadoLembrete { salvo, salvoComAviso, avisoFalhou, apagado }

class PreferenciasLocais extends ChangeNotifier {
  PreferenciasLocais({required this.prefs, required this.nomePadrao, required this.aviso}) {
    _carregar();
  }

  final SharedPreferences prefs;

  /// Nome mostrado quando o cuidador nao digitou um (o CHILD_ID).
  final String nomePadrao;
  final AvisoDeLembrete aviso;

  static const maxNome = 40;
  static const maxLembrete = 120;
  static const _maxLembretes = 200;
  static const _diasDoLembreteDoDia = 30;

  static const _chaveNome = 'nome_crianca';
  static const _chaveAparencia = 'aparencia';
  static const _chaveLembretes = 'lembretes_v1';

  String _nome = '';
  Aparencia _aparencia = Aparencia.sistema;
  final Map<String, Lembrete> _lembretes = {};

  // -------------------------------------------------------------------------
  // Aparencia
  // -------------------------------------------------------------------------

  /// Padrao: seguir o sistema.
  Aparencia get aparencia => _aparencia;

  /// Troca o tema na hora (o MaterialApp escuta estas preferencias) e salva.
  Future<void> definirAparencia(Aparencia aparencia) async {
    if (aparencia == _aparencia) return;
    _aparencia = aparencia;
    notifyListeners();
    if (aparencia == Aparencia.sistema) {
      await prefs.remove(_chaveAparencia);
    } else {
      await prefs.setString(_chaveAparencia, aparencia.codigo);
    }
  }

  // -------------------------------------------------------------------------
  // Nome da crianca
  // -------------------------------------------------------------------------

  /// Nome para mostrar (o digitado ou, vazio, o CHILD_ID).
  String get nomeCrianca => _nome.isEmpty ? nomePadrao : _nome;

  /// O que o cuidador digitou (pode ser vazio).
  String get nomeDigitado => _nome;

  Future<void> definirNomeCrianca(String nome) async {
    var limpo = nome.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (limpo.length > maxNome) limpo = limpo.substring(0, maxNome);
    if (limpo == _nome) return;
    _nome = limpo;
    notifyListeners();
    if (limpo.isEmpty) {
      await prefs.remove(_chaveNome);
    } else {
      await prefs.setString(_chaveNome, limpo);
    }
  }

  // -------------------------------------------------------------------------
  // Lembretes
  // -------------------------------------------------------------------------

  static String chaveEpisodio(String episodioId) => 'episodio:$episodioId';

  static String chaveDia(DateTime dia) =>
      'dia:${dia.year}-${dia.month.toString().padLeft(2, '0')}-${dia.day.toString().padLeft(2, '0')}';

  static int idDoAviso(String chave) => idDeNotificacao('lembrete:$chave');

  Lembrete? lembrete(String chave) => _lembretes[chave];

  /// Salva (ou substitui) o lembrete. Texto vazio apaga. `avisarEm` agenda o
  /// aviso no celular; sem ele, um aviso anterior e cancelado.
  Future<ResultadoLembrete> salvarLembrete(
    String chave,
    String texto, {
    DateTime? avisarEm,
    required String tituloDoAviso,
  }) async {
    var limpo = texto.trim();
    if (limpo.isEmpty) {
      await apagarLembrete(chave);
      return ResultadoLembrete.apagado;
    }
    if (limpo.length > maxLembrete) limpo = limpo.substring(0, maxLembrete);
    final agora = relogio();
    final avisoValido = avisarEm != null && avisarEm.isAfter(agora) ? avisarEm : null;

    var resultado = ResultadoLembrete.salvo;
    final id = idDoAviso(chave);
    if (avisoValido != null) {
      final ok = await aviso.agendar(id: id, quando: avisoValido, titulo: tituloDoAviso, texto: limpo);
      resultado = ok ? ResultadoLembrete.salvoComAviso : ResultadoLembrete.avisoFalhou;
    } else if (_lembretes[chave]?.avisoPendente(agora) != null) {
      await aviso.cancelar(id);
    }

    _lembretes[chave] = Lembrete(
      texto: limpo,
      salvoEm: agora,
      avisarEm: resultado == ResultadoLembrete.avisoFalhou ? null : avisoValido,
    );
    _limitar();
    notifyListeners();
    await _salvar();
    return resultado;
  }

  Future<void> apagarLembrete(String chave) async {
    final anterior = _lembretes.remove(chave);
    if (anterior == null) return;
    notifyListeners();
    if (anterior.avisoPendente(relogio()) != null) await aviso.cancelar(idDoAviso(chave));
    await _salvar();
  }

  // -------------------------------------------------------------------------
  // Persistencia
  // -------------------------------------------------------------------------

  void _carregar() {
    _nome = prefs.getString(_chaveNome) ?? '';
    _aparencia = Aparencia.fromCodigo(prefs.getString(_chaveAparencia));
    try {
      final dados = jsonDecode(prefs.getString(_chaveLembretes) ?? '{}');
      if (dados is Map<String, dynamic>) {
        for (final MapEntry(:key, :value) in dados.entries) {
          final lembrete = Lembrete.fromJson(value);
          if (lembrete != null) _lembretes[key] = lembrete;
        }
      }
    } catch (_) {
      // lista corrompida: recomeca vazia
    }
    // Lembrete do dia so vale para aquele dia: os antigos saem.
    final limite = relogio().subtract(const Duration(days: _diasDoLembreteDoDia));
    _lembretes.removeWhere((chave, l) => chave.startsWith('dia:') && l.salvoEm.isBefore(limite));
    _limitar();
  }

  /// No maximo [_maxLembretes]: os mais antigos saem primeiro.
  void _limitar() {
    if (_lembretes.length <= _maxLembretes) return;
    final ordem = _lembretes.entries.toList()..sort((a, b) => a.value.salvoEm.compareTo(b.value.salvoEm));
    for (final e in ordem.take(_lembretes.length - _maxLembretes)) {
      _lembretes.remove(e.key);
    }
  }

  Future<void> _salvar() async {
    await prefs.setString(
      _chaveLembretes,
      jsonEncode({for (final e in _lembretes.entries) e.key: e.value.toJson()}),
    );
  }
}

/// Entrega as preferencias locais as telas (mesmo esquema do AppScope).
class PreferenciasScope extends InheritedNotifier<PreferenciasLocais> {
  const PreferenciasScope({super.key, required PreferenciasLocais preferencias, required super.child})
      : super(notifier: preferencias);

  static PreferenciasLocais of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PreferenciasScope>()!.notifier!;

  /// Sem se inscrever para reconstrucao (use em callbacks de botao).
  static PreferenciasLocais read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PreferenciasScope>()!.notifier!;
}

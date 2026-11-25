// Dados que o cuidador escreve e que ficam SO neste celular: o nome da
// crianca, a aparencia (claro, escuro ou seguir o sistema) e por quanto tempo
// guardar o historico no shared_preferences, e os lembretes (de um episodio ou do dia) na tabela
// `lembretes` do banco local (banco.dart). Decisao de privacidade
// (docs/app.md): nada disto vai para o MQTT, para o painel (site) nem para
// outro aparelho. A ordem de reset do terminal (npm run resetar) e o botao
// "Apagar dados deste aparelho" apagam os lembretes (e, com --tudo, o nome e
// a aparencia): apagarDados.

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lembrete.dart';
import '../utils/relogio.dart';
import 'aviso_de_lembrete.dart';
import 'banco.dart';
import 'notification_service.dart' show idDeNotificacao;

export '../models/lembrete.dart';

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
  /// O nome e a aparencia ficam prontos aqui; os lembretes, depois de
  /// [carregar] (o main espera antes de abrir as telas).
  PreferenciasLocais({required this.prefs, required this.banco, required this.nomePadrao, required this.aviso}) {
    _nome = prefs.getString(_chaveNome) ?? '';
    _aparencia = Aparencia.fromCodigo(prefs.getString(_chaveAparencia));
    _guardarHistorico = GuardarHistorico.fromCodigo(prefs.getString(GuardarHistorico.chave));
  }

  final SharedPreferences prefs;
  final BancoPuzzleBand banco;

  /// Nome mostrado quando o cuidador nao digitou um (o CHILD_ID).
  final String nomePadrao;
  final AvisoDeLembrete aviso;

  static const maxNome = 40;
  static const maxLembrete = 120;
  static const _maxLembretes = 200;
  static const _diasDoLembreteDoDia = 30;

  static const _chaveNome = 'nome_crianca';
  static const _chaveAparencia = 'aparencia';

  String _nome = '';
  Aparencia _aparencia = Aparencia.sistema;
  GuardarHistorico _guardarHistorico = GuardarHistorico.padrao;
  final Map<String, Lembrete> _lembretes = {};

  // -------------------------------------------------------------------------
  // Guardar historico por (retencao dos episodios)
  // -------------------------------------------------------------------------

  /// Padrao: 1 ano. O servico em primeiro plano le a mesma chave do disco.
  GuardarHistorico get guardarHistorico => _guardarHistorico;

  /// Salva a opcao. Quem chama aplica a retencao em seguida
  /// (HistoricoLocal.aplicarRetencao): um periodo menor apaga na hora.
  Future<void> definirGuardarHistorico(GuardarHistorico valor) async {
    if (valor == _guardarHistorico) return;
    _guardarHistorico = valor;
    notifyListeners();
    if (valor == GuardarHistorico.padrao) {
      await prefs.remove(GuardarHistorico.chave);
    } else {
      await prefs.setString(GuardarHistorico.chave, valor.codigo);
    }
  }

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
    final excedentes = _limitar();
    notifyListeners();
    await banco.gravarLembrete(chave, _lembretes[chave]!);
    await banco.apagarLembretes(excedentes);
    return resultado;
  }

  Future<void> apagarLembrete(String chave) async {
    final anterior = _lembretes.remove(chave);
    if (anterior == null) return;
    notifyListeners();
    if (anterior.avisoPendente(relogio()) != null) await aviso.cancelar(idDoAviso(chave));
    await banco.apagarLembretes([chave]);
  }

  // -------------------------------------------------------------------------
  // Apagar (reset para uma apresentacao)
  // -------------------------------------------------------------------------

  int _geracao = 0;

  /// Muda a cada [apagarDados]: campos de texto que guardam uma copia do
  /// valor (o "Nome da criança" em Ajustes) usam como chave e recomecam.
  int get geracao => _geracao;

  /// Apaga os lembretes e cancela os avisos agendados deles. Com
  /// `manterPreferencias` false, tambem volta o nome da crianca e a
  /// aparencia ao padrao. Chamado pela ordem do terminal (npm run resetar,
  /// via MqttService) e pelo botao "Apagar dados deste aparelho".
  Future<void> apagarDados({required bool manterPreferencias}) async {
    final chaves = _lembretes.keys.toList();
    _lembretes.clear();
    if (!manterPreferencias) {
      _nome = '';
      _aparencia = Aparencia.sistema;
      _guardarHistorico = GuardarHistorico.padrao;
    }
    _geracao++;
    notifyListeners();
    // Cancela todos (nao so os pendentes): um aviso agendado nao fica para
    // tras por diferenca de relogio.
    for (final chave in chaves) {
      await aviso.cancelar(idDoAviso(chave));
    }
    await banco.apagarTodosOsLembretes();
    if (!manterPreferencias) {
      await prefs.remove(_chaveNome);
      await prefs.remove(_chaveAparencia);
      await prefs.remove(GuardarHistorico.chave);
    }
  }

  // -------------------------------------------------------------------------
  // Persistencia
  // -------------------------------------------------------------------------

  /// Le os lembretes do banco. Os lembretes do dia so valem para aquele dia:
  /// os de mais de 30 dias saem (tambem do banco), e no maximo 200 ficam.
  Future<void> carregar() async {
    try {
      final salvos = await banco.lembretesSalvos();
      _lembretes
        ..clear()
        ..addAll(salvos);
    } catch (e) {
      debugPrint('Falha ao ler os lembretes do banco: $e');
      return;
    }
    final limite = relogio().subtract(const Duration(days: _diasDoLembreteDoDia));
    final velhos = [
      for (final MapEntry(key: chave, value: l) in _lembretes.entries)
        if (chave.startsWith('dia:') && l.salvoEm.isBefore(limite)) chave,
    ];
    velhos.forEach(_lembretes.remove);
    final excedentes = _limitar();
    notifyListeners();
    await banco.apagarLembretes([...velhos, ...excedentes]);
  }

  /// No maximo [_maxLembretes]: os mais antigos saem primeiro. Devolve as
  /// chaves que sairam (para apagar do banco).
  List<String> _limitar() {
    if (_lembretes.length <= _maxLembretes) return const [];
    final ordem = _lembretes.entries.toList()..sort((a, b) => a.value.salvoEm.compareTo(b.value.salvoEm));
    final sairam = [for (final e in ordem.take(_lembretes.length - _maxLembretes)) e.key];
    sairam.forEach(_lembretes.remove);
    return sairam;
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

// Historico de episodios para as telas, lido do banco local (banco.dart) por
// consultas: os de um dia (Inicio, filtro do calendario), os de um mes
// (calendario, total do mes), os dos ultimos 7 dias (Graficos), um episodio
// pelo id (Detalhe) e a lista do Historico em paginas de 50, que crescem
// conforme se rola.
//
// As telas leem de forma sincrona o que ja foi carregado (o build nao
// espera o banco): pedir um dia/mes que ainda nao esta na memoria dispara a
// consulta e devolve vazio; quando ela termina, as telas sao avisadas. Toda
// escrita (lista da pulseira, avaliacao, reset) e seguida de uma releitura
// do que as telas estao mostrando. As operacoes rodam uma de cada vez, na
// ordem em que foram pedidas.
//
// Na conexao do servico em primeiro plano (paraTelas false) so ha escritas:
// nenhuma consulta para tela.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/metricas.dart';
import '../models/models.dart';
import '../models/resumo.dart';
import '../utils/relogio.dart';
import 'banco.dart';

class HistoricoLocal extends ChangeNotifier {
  HistoricoLocal(this.banco, {this.paraTelas = true, Future<GuardarHistorico> Function()? guardarHistorico})
      : _guardarHistorico = guardarHistorico ?? (() async => GuardarHistorico.padrao);

  final BancoPuzzleBand banco;
  final bool paraTelas;

  /// Opcao "Guardar historico por" (Ajustes), lida a cada lista recebida: um
  /// episodio fora da retencao nao entra.
  final Future<GuardarHistorico> Function() _guardarHistorico;

  /// Episodios por pagina na lista do Historico.
  static const tamanhoDaPagina = 50;

  int _total = 0;
  DateTime? _primeiro;
  DateTime? _recebidoNoBanco;
  DateTime? _listaRecebidaEm;
  List<Episodio> _recentes = const [];
  int _limite = tamanhoDaPagina;
  bool _temMais = false;
  bool _carregandoMais = false;
  final _dias = <DateTime, List<Episodio>>{};
  final _meses = <DateTime, List<Episodio>>{};
  final _semanas = <DateTime, List<Episodio>>{}; // chave: o ultimo dia (hoje)
  final _porId = <String, Episodio?>{};
  final _pedidos = <Object>{};

  Future<void> _fila = Future.value();
  // Muda a cada apagar(): o que foi pedido antes nao repoe dados apagados.
  int _geracao = 0;
  bool _descartado = false;

  // -------------------------------------------------------------------------
  // Leitura (telas)
  // -------------------------------------------------------------------------

  /// Nenhum episodio no banco.
  bool get vazio => _total == 0;

  int get total => _total;

  /// Inicio do episodio mais antigo (primeiro mes do calendario).
  DateTime? get primeiroInicio => _primeiro;

  /// Ultima vez que chegou uma lista da pulseira (o "cópia salva de ...").
  DateTime? get recebidoEm {
    final a = _recebidoNoBanco;
    final b = _listaRecebidaEm;
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  /// Os episodios mais recentes (mais recente primeiro), sempre com dias
  /// inteiros: a lista do Historico.
  List<Episodio> get recentes => _recentes;

  /// Ha episodios mais antigos fora de [recentes] (carregarMais).
  bool get temMais => _temMais;

  /// O episodio mais recente (cartao "Nenhum episódio agora").
  Episodio? get ultimo => _recentes.isEmpty ? null : _recentes.first;

  /// Episodios do dia (mais recente primeiro).
  List<Episodio> doDia(DateTime dia) {
    final d = diaDe(dia);
    return _doCache(_dias, d, () => _consultarDia(d));
  }

  /// Contagem por dia do mes de [mes] (calendario e total do mes).
  Map<DateTime, ContagemDia> contagensDoMes(DateTime mes) {
    final m = DateTime(mes.year, mes.month);
    return contagemPorDia(_doCache(_meses, m, () => _consultarMes(m)));
  }

  /// Os ultimos 7 dias terminando em [agora] (grafico de 7 dias).
  List<DiaResumo> seteDias(DateTime agora) {
    final hoje = diaDe(agora);
    return ultimos7Dias(_doCache(_semanas, hoje, () => _consultarSemana(hoje)), agora);
  }

  /// Um episodio pelo id (null enquanto carrega ou se nao existe).
  Episodio? porId(String id) {
    for (final lista in [_recentes, ..._dias.values, ..._meses.values, ..._semanas.values]) {
      for (final e in lista) {
        if (e.id == id) return e;
      }
    }
    if (_porId.containsKey(id)) return _porId[id];
    final g = _geracao;
    if (_pedidos.add(('id', id))) {
      _emOrdem(() async {
        try {
          final e = await banco.episodio(id);
          if (g == _geracao) _porId[id] = e;
        } finally {
          _pedidos.remove(('id', id));
        }
        _avisar();
      });
    }
    return null;
  }

  /// Rolou ate o fim da lista do Historico: mais uma pagina.
  void carregarMais() {
    if (!_temMais || _carregandoMais) return;
    _carregandoMais = true;
    _limite += tamanhoDaPagina;
    final g = _geracao;
    _emOrdem(() async {
      try {
        final r = await _consultarRecentes(_limite, _total);
        if (g == _geracao) {
          _recentes = r.$1;
          _temMais = r.$2;
        }
      } finally {
        _carregandoMais = false;
      }
      _avisar();
    });
  }

  /// Completa quando a fila esvazia (gravacoes e leituras pendentes feitas).
  Future<void> get ocioso async {
    Future<void> anterior;
    do {
      anterior = _fila;
      await anterior;
    } while (!identical(anterior, _fila));
  }

  // -------------------------------------------------------------------------
  // Escrita
  // -------------------------------------------------------------------------

  /// Lista da pulseira (retida ou atualizacao): upsert pelo id. Os que nao
  /// vieram continuam no banco.
  Future<void> receberDaPulseira(List<Episodio> lista, DateTime agora) {
    _listaRecebidaEm = agora;
    return _emOrdem(() async {
      await banco.gravarDaPulseira(lista, agora, guardar: await _guardarHistorico());
      await _recarregarAgora();
    });
  }

  /// Resumos de minuto da pulseira (resumo_minuto): upsert pelo minuto. So
  /// quem notifica chama (MqttService.gravaResumos). Nada muda na tela.
  Future<void> receberResumos(List<ResumoDoMinuto> minutos, DateTime agora) =>
      _emOrdem(() => banco.gravarResumos(minutos, agora));

  /// Mudou a opcao "Guardar historico por": aplica a retencao na hora.
  Future<void> aplicarRetencao(GuardarHistorico guardar, DateTime agora) => _emOrdem(() async {
        await banco.aplicarRetencao(agora, guardar: guardar);
        await _recarregarAgora();
      });

  /// Avaliacao feita neste app: aparece na hora e fica gravada como pendente
  /// de confirmacao (ver Episodios.avaliacaoLocal).
  Future<void> avaliar(Episodio episodio, Avaliacao avaliacao, String observacao, DateTime quando) {
    final novo = episodio.avaliadoPeloApp(avaliacao, observacao, quando);
    List<Episodio> trocar(List<Episodio> l) => [for (final e in l) e.id == novo.id ? novo : e];
    _recentes = trocar(_recentes);
    for (final cache in [_dias, _meses, _semanas]) {
      cache.updateAll((_, l) => trocar(l));
    }
    if (_porId.containsKey(novo.id)) _porId[novo.id] = novo;
    _avisar();
    return _emOrdem(() async {
      await banco.avaliarLocal(episodio.id, avaliacao, observacao, quando);
      await _recarregarAgora();
    });
  }

  /// Reset (npm run resetar, "Apagar os dados"): some da tela na hora e sai
  /// do banco (episodios e notificados).
  Future<void> apagar() {
    _geracao++;
    _total = 0;
    _primeiro = null;
    _recebidoNoBanco = null;
    _listaRecebidaEm = null;
    _recentes = const [];
    _limite = tamanhoDaPagina;
    _temMais = false;
    _dias.clear();
    _meses.clear();
    _semanas.clear();
    _porId.clear();
    _avisar();
    return _emOrdem(() async {
      await banco.apagarHistorico();
      await _recarregarAgora();
    });
  }

  /// Apaga tudo e grava [lista] como a pulseira, numa operacao so (cenarios
  /// dos testes de tela).
  @visibleForTesting
  Future<void> substituirTudo(List<Episodio> lista, DateTime agora) {
    _geracao++;
    _listaRecebidaEm = agora;
    return _emOrdem(() async {
      await banco.apagarHistorico();
      await banco.gravarDaPulseira(lista, agora);
      await _recarregarAgora();
    });
  }

  /// Le de novo o que as telas mostram (abertura, volta para a frente).
  Future<void> recarregar() => _emOrdem(_recarregarAgora);

  // -------------------------------------------------------------------------
  // Consultas
  // -------------------------------------------------------------------------

  Future<List<Episodio>> _consultarDia(DateTime d) => banco.episodiosEntre(d, DateTime(d.year, d.month, d.day + 1));

  Future<List<Episodio>> _consultarMes(DateTime m) => banco.episodiosEntre(m, DateTime(m.year, m.month + 1));

  Future<List<Episodio>> _consultarSemana(DateTime hoje) =>
      banco.episodiosEntre(DateTime(hoje.year, hoje.month, hoje.day - 6), DateTime(hoje.year, hoje.month, hoje.day + 1));

  /// Os [limite] mais recentes, completando o dia do ultimo (um dia nao fica
  /// cortado entre duas paginas, e o total no cabecalho do dia fica certo).
  Future<(List<Episodio>, bool)> _consultarRecentes(int limite, int total) async {
    final lista = await banco.recentes(limite + 1);
    if (lista.length <= limite) return (lista, false);
    final inteiros = await banco.episodiosDesde(diaDe(lista[limite - 1].inicio));
    return (inteiros, inteiros.length < total);
  }

  Future<void> _recarregarAgora() async {
    if (!paraTelas || _descartado) return;
    final g = _geracao;
    final hoje = diaDe(relogio());
    final dias = {..._dias.keys, hoje};
    final meses = {..._meses.keys, DateTime(hoje.year, hoje.month)};
    final semanas = {..._semanas.keys, hoje};
    try {
      final resumo = await banco.resumo();
      final recentes = await _consultarRecentes(_limite, resumo.total);
      final novosDias = {for (final d in dias) d: await _consultarDia(d)};
      final novosMeses = {for (final m in meses) m: await _consultarMes(m)};
      final novasSemanas = {for (final s in semanas) s: await _consultarSemana(s)};
      final novosPorId = {for (final id in _porId.keys.toList()) id: await banco.episodio(id)};
      if (g != _geracao) return;
      _total = resumo.total;
      _primeiro = resumo.primeiro;
      _recebidoNoBanco = resumo.recebidoEm;
      _recentes = recentes.$1;
      _temMais = recentes.$2;
      _dias
        ..clear()
        ..addAll(novosDias);
      _meses
        ..clear()
        ..addAll(novosMeses);
      _semanas
        ..clear()
        ..addAll(novasSemanas);
      _porId
        ..clear()
        ..addAll(novosPorId);
    } catch (e) {
      debugPrint('Falha ao ler o historico do banco: $e');
    }
    _avisar();
  }

  List<Episodio> _doCache(
    Map<DateTime, List<Episodio>> cache,
    DateTime chave,
    Future<List<Episodio>> Function() consulta,
  ) {
    final pronto = cache[chave];
    if (pronto != null) return pronto;
    final pedido = (identityHashCode(cache), chave);
    final g = _geracao;
    if (paraTelas && _pedidos.add(pedido)) {
      _emOrdem(() async {
        try {
          final lista = await consulta();
          if (g == _geracao) cache[chave] = lista;
        } finally {
          _pedidos.remove(pedido);
        }
        _avisar();
      });
    }
    return const [];
  }

  /// Uma operacao de cada vez, na ordem. Um erro e registrado e nao trava as
  /// seguintes.
  Future<void> _emOrdem(Future<void> Function() tarefa) {
    final feita = _fila.then((_) => tarefa()).catchError((Object e) {
      debugPrint('Falha no historico local: $e');
    });
    _fila = feita;
    return feita;
  }

  void _avisar() {
    if (!_descartado) notifyListeners();
  }

  @override
  void dispose() {
    _descartado = true;
    super.dispose();
  }
}

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_scope.dart';
import '../services/mqtt_service.dart';
import '../utils/formatters.dart';
import '../widgets/nivel_visual.dart';

/// Episodios recebidos do site (`puzzleband/<id>/historico`). O cuidador
/// confirma ou descarta o gatilho, com uma observacao curta, e o app publica
/// em `puzzleband/<id>/avaliacao`. A ultima copia fica salva para ver offline.
class HistoricoScreen extends StatefulWidget {
  const HistoricoScreen({super.key});

  @override
  State<HistoricoScreen> createState() => _HistoricoScreenState();
}

class _HistoricoScreenState extends State<HistoricoScreen> {
  static const _maxObservacao = 200;

  // Um campo de observacao por episodio. `_obsDoSite` guarda o ultimo valor
  // recebido: se o cuidador nao editou, o campo acompanha o site.
  final Map<String, TextEditingController> _obs = {};
  final Map<String, String> _obsDoSite = {};

  @override
  void dispose() {
    for (final c in _obs.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerPara(Episodio ep) {
    final existente = _obs[ep.id];
    if (existente == null) {
      _obsDoSite[ep.id] = ep.observacao;
      return _obs[ep.id] = TextEditingController(text: ep.observacao);
    }
    final anterior = _obsDoSite[ep.id];
    if (anterior != ep.observacao) {
      if (existente.text == anterior) existente.text = ep.observacao;
      _obsDoSite[ep.id] = ep.observacao;
    }
    return existente;
  }

  void _avaliar(Episodio ep, Avaliacao avaliacao) {
    FocusScope.of(context).unfocus();
    final service = AppScope.read(context);
    final texto = _obs[ep.id]?.text ?? ep.observacao;
    final enviado = service.enviarAvaliacao(ep, avaliacao, texto);
    if (enviado) _obsDoSite[ep.id] = texto.trim();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enviado
              ? (avaliacao == Avaliacao.confirmado ? 'Gatilho confirmado. Enviado ao painel.' : 'Indicação descartada. Enviado ao painel.')
              : 'Sem conexão com o broker: a avaliação não foi enviada.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = AppScope.of(context);
    final episodios = service.historico;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                children: [
                  const Text(
                    'HISTÓRICO',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Episódios detectados pelo painel. Confirme ou descarte o provável gatilho.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF888888)),
                  ),
                  const SizedBox(height: 12),
                  _buildFonteDosDados(service),
                  const SizedBox(height: 16),
                  if (episodios.isEmpty)
                    _buildVazio()
                  else
                    for (final ep in episodios) ...[
                      _buildEpisodio(service, ep),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Header (mesmo das outras telas)
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE8F5E9),
              border: Border.all(color: const Color(0xFF4CAF50), width: 1.5),
            ),
            child: const Icon(Icons.person, size: 20, color: Color(0xFF4CAF50)),
          ),
          const SizedBox(width: 12),
          const Text(
            'PUZZLE BAND',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              color: Color(0xFF222222),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFonteDosDados(MqttService service) {
    final aoVivo = service.historicoAoVivo;
    final recebido = service.historicoRecebidoEm;
    final String texto;
    if (aoVivo) {
      texto = 'Atualizado pelo painel${recebido != null ? ' às ${horaMinuto(recebido)}' : ''}.';
    } else if (recebido != null) {
      texto = 'Sem conexão: mostrando a última cópia salva (${diaHora(recebido)}).';
    } else {
      texto = 'Sem conexão e sem cópia salva ainda.';
    }
    final cor = aoVivo ? const Color(0xFF2E7D32) : const Color(0xFF757575);
    return Row(
      children: [
        Icon(aoVivo ? Icons.sync : Icons.cloud_off, size: 16, color: cor),
        const SizedBox(width: 6),
        Expanded(child: Text(texto, style: TextStyle(fontSize: 12, color: cor))),
      ],
    );
  }

  Widget _buildVazio() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: const Column(
        children: [
          Icon(Icons.history, size: 40, color: Color(0xFFBDBDBD)),
          SizedBox(height: 10),
          Text(
            'Nenhum episódio recebido ainda',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF666666)),
          ),
          SizedBox(height: 4),
          Text(
            'Quando o painel (site) detectar sinais de atenção ou de possível crise, o episódio aparece aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
          ),
        ],
      ),
    );
  }

  Widget _tag(String texto, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor),
      ),
      child: Text(texto, style: TextStyle(fontSize: 11, color: cor, fontWeight: FontWeight.w600)),
    );
  }

  String _textoAvaliacao(Episodio ep) {
    final quem = ep.avaliacaoOrigem == 'app' ? 'pelo app' : 'no painel';
    final quando = ep.avaliacaoEm != null ? ' às ${horaMinuto(ep.avaliacaoEm!)}' : '';
    return switch (ep.avaliacao) {
      Avaliacao.confirmado => '✓ Gatilho confirmado $quem$quando',
      Avaliacao.descartado => '✕ Indicação descartada $quem$quando',
      Avaliacao.pendente => '○ Avaliação pendente',
    };
  }

  Widget _buildEpisodio(MqttService service, Episodio ep) {
    final visual = NivelVisual.de(ep.nivelMaximo);
    final controller = _controllerPara(ep);
    final gatilho = ep.gatilho?.texto ?? '';
    final ciente = ep.vistoEm ?? service.cienteEm(ep.id);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nivel maximo + horario
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: visual.fundo,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(visual.icone, size: 16, color: visual.cor),
                    const SizedBox(width: 4),
                    Text(
                      visual.rotulo,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: visual.cor),
                    ),
                  ],
                ),
              ),
              Text(
                diaHora(ep.inicio),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF222222)),
              ),
              if (ep.emAndamento) _tag('em andamento', const Color(0xFFE53935)),
              if (ep.encerramento == 'interrompido') _tag('interrompido', const Color(0xFF9E9E9E)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            [
              'Duração: ${ep.emAndamento ? 'em andamento' : duracao(ep.duracaoS)}',
              if (ep.probabilidadeMaxima != null) 'Prob. máx.: ${(ep.probabilidadeMaxima! * 100).round()}%',
              rotuloFonte(ep.fonte),
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
          ),
          const SizedBox(height: 10),
          Text(
            gatilho.isNotEmpty ? gatilho : 'Gatilho não calculado.',
            style: const TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w600, color: Color(0xFF222222)),
          ),
          if (ciente != null) ...[
            const SizedBox(height: 6),
            Text(
              '✓ Alerta visto pelo cuidador às ${horaMinuto(ciente)}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _textoAvaliacao(ep),
            style: const TextStyle(fontSize: 12, color: Color(0xFF555555)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLength: _maxObservacao,
            style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Observação (opcional)',
              hintText: 'Ex.: sirene da escola tocou antes',
              hintStyle: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 13),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 1.5),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _botaoAvaliacao(
                  ep: ep,
                  avaliacao: Avaliacao.confirmado,
                  icone: Icons.check,
                  rotulo: 'Confirmar gatilho',
                  cor: const Color(0xFF2E7D32),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _botaoAvaliacao(
                  ep: ep,
                  avaliacao: Avaliacao.descartado,
                  icone: Icons.close,
                  rotulo: 'Descartar',
                  cor: const Color(0xFFE53935),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _botaoAvaliacao({
    required Episodio ep,
    required Avaliacao avaliacao,
    required IconData icone,
    required String rotulo,
    required Color cor,
  }) {
    final selecionado = ep.avaliacao == avaliacao;
    final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    const padding = EdgeInsets.symmetric(vertical: 10);
    final conteudo = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icone, size: 16),
        const SizedBox(width: 4),
        Flexible(child: Text(rotulo, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
      ],
    );
    return Semantics(
      selected: selecionado,
      child: selecionado
          ? ElevatedButton(
              onPressed: () => _avaliar(ep, avaliacao),
              style: ElevatedButton.styleFrom(
                backgroundColor: cor,
                foregroundColor: Colors.white,
                padding: padding,
                shape: forma,
                elevation: 0,
              ),
              child: conteudo,
            )
          : OutlinedButton(
              onPressed: () => _avaliar(ep, avaliacao),
              style: OutlinedButton.styleFrom(
                foregroundColor: cor,
                side: BorderSide(color: cor),
                padding: padding,
                shape: forma,
              ),
              child: conteudo,
            ),
    );
  }
}

// Processamento na borda (edge): a pulseira roda o modelo, os episodios e o
// gatilho e publica o resultado pronto - o app do cuidador funciona so com a
// pulseira ligada, sem site. Na pulseira real isso rodaria no ESP32 (com o
// modelo convertido para TinyML, trabalho futuro); aqui roda em Node com os
// MESMOS modulos do frontend/src (nada duplicado):
//
//   leitura -> buffer de 300 -> classifyAt (predict.js + forest.json)
//           -> ingestReadings / upsertEpisode (episodes.js) -> gatilho (trigger.js)
//           -> buildStateMessage / buildAlertMessage / buildHistoryMessage (buildMessages.js)
//
// Duas partes:
//   createEdgeProcessor  processamento puro, sem rede (usado tambem pelo
//                        verificar.js, que roda os cenarios offline);
//   createEdgeLink       ligacao com o broker: publica estado, alertas e
//                        historico; aplica ack, avaliacao e controle;
//                        recupera o historico da mensagem retida.
// Topicos e formatos: docs/mqtt.md.

import { classifyAt } from '../frontend/src/model/classify.js';
import {
  HISTORY_LIMIT,
  byStartDesc,
  closeOpenEpisode,
  createEpisodeStore,
  createMonitor,
  ingestReadings,
  normalizeEpisodes,
  updateEpisode,
  upsertEpisode,
} from '../frontend/src/model/episodes.js';
import {
  buildAlertMessage,
  buildHistoryMessage,
  buildStateMessage,
  historyEntryToEpisode,
  historySignature,
  topicsFor,
} from '../frontend/src/hooks/buildMessages.js';
import { parseAck, parseControl, parseEvaluation, parseHistory } from '../frontend/src/hooks/parseMessages.js';

export const MAX_BUFFER = 300; // 5 min de sinal a 1 Hz (o gatilho usa ate 6 min de memoria propria)
export const RECOVERY_TIMEOUT_MS = 5000; // espera pela mensagem retida de historico ao iniciar

// ---------------------------------------------------------------------------
// Processamento (sem rede)
// ---------------------------------------------------------------------------

// `source`: 'pulseira' (cenarios) | 'manual' (modo controle). `storage`:
// objeto getItem/setItem onde o historico fica gravado (historico.js) ou null
// (so em memoria).
export function createEdgeProcessor({ childId, source = 'pulseira', storage = null, classify = classifyAt, maxBuffer = MAX_BUFFER }) {
  const store = createEpisodeStore(storage);
  let monitor = createMonitor({ childId, source });
  let buffer = [];
  let lastReading = null;
  let last = { tier: 'baixo_risco', probability: null };

  const episodes = () => store.getSnapshot().episodes;
  const isKnown = (id) => episodes().some((ep) => ep.id === id);
  const now = () => new Date().toISOString();

  return {
    childId,
    source,

    // Uma leitura nova (1x/s). Mesmo caminho de antes no site: buffer
    // deslizante -> ingestReadings (classifica so as leituras novas) ->
    // episodios -> alertas na MUDANCA de nivel para atencao/alto_risco.
    ingest(reading) {
      buffer = [...buffer, reading].slice(-maxBuffer);
      const capture = (readings, i) => {
        last = classify(readings, i);
        return last;
      };
      const result = ingestReadings(monitor, lastReading, buffer, capture);
      monitor = result.monitor;
      lastReading = result.lastReading;
      if (result.changed.length) {
        store.update((prev) => result.changed.reduce((acc, ep) => upsertEpisode(acc, ep), prev));
      }
      const alerts = result.alerts.map((alert) => buildAlertMessage(
        { timestamp: reading.timestamp, ...alert },
        { source, childId },
      ));
      return { tier: last.tier, probability: last.probability, alerts, changed: result.changed };
    },

    tier: () => last.tier,
    probability: () => last.probability,
    readings: () => buffer,
    episodes,
    openEpisode: () => episodes().find((ep) => !ep.encerramento) ?? null,
    storageOk: () => store.getSnapshot().storageOk,

    state(timestamp = now()) {
      return buildStateMessage({
        timestamp,
        source,
        childId,
        tier: last.tier,
        probability: last.probability,
        readings: buffer,
        openEpisode: episodes().find((ep) => !ep.encerramento) ?? null,
      });
    },
    history: (timestamp = now()) => buildHistoryMessage(episodes(), { childId, timestamp }),
    signature: () => historySignature(episodes()),

    // "Estou ciente" do app. false = episodio desconhecido.
    applyAck({ episodio_id: id, timestamp }) {
      if (!isKnown(id)) return false;
      store.update((prev) => updateEpisode(prev, id, { visto_pelo_cuidador_em: timestamp ?? now() }));
      return true;
    },

    // Avaliacao do app ou do painel do site ("pendente" desfaz). false = episodio desconhecido.
    applyEvaluation({ episodio_id: id, avaliacao, origem, timestamp, observacao }) {
      if (!isKnown(id)) return false;
      store.update((prev) => {
        let next = updateEpisode(prev, id, {
          avaliacao_cuidador: avaliacao,
          avaliacao_origem: origem,
          avaliacao_em: timestamp ?? now(),
        });
        if (observacao !== undefined) next = updateEpisode(next, id, { observacao });
        return next;
      });
      return true;
    },

    // Episodios recuperados da mensagem retida (entradas de parseHistory).
    // Os que ja existem ficam como estao; os "em andamento" viram
    // "interrompido" (a pulseira foi desligada no meio). Devolve quantos entraram.
    importHistory(entries) {
      const known = new Set(episodes().map((ep) => ep.id));
      const incoming = normalizeEpisodes(entries.filter((e) => !known.has(e.id)).map(historyEntryToEpisode));
      if (!incoming.length) return 0;
      store.update((prev) => [...prev, ...incoming].sort(byStartDesc).slice(0, HISTORY_LIMIT));
      return incoming.length;
    },

    // Pulseira desligando: fecha o episodio aberto como "interrompido".
    close() {
      const closed = closeOpenEpisode(monitor);
      if (closed) store.update((prev) => upsertEpisode(prev, closed));
      monitor = createMonitor({ childId, source });
      buffer = [];
      lastReading = null;
      last = { tier: 'baixo_risco', probability: null };
      return closed;
    },

    clear() {
      store.update(() => []);
    },
  };
}

// ---------------------------------------------------------------------------
// Ligacao com o broker
// ---------------------------------------------------------------------------

// `client`: cliente do pacote mqtt (ou um falso nos testes) com connected,
// publish, subscribe, unsubscribe e on. `control`: no modo controle, o
// estado dos valores-alvo (controle.js); fora dele, null (nao assina controle).
// `recoverFromRetained`: sem arquivo local, recupera o historico da mensagem
// retida em historico antes de publicar o seu (para nao apaga-la com uma
// lista vazia). `log(evento, texto)` vai para o terminal.
export function createEdgeLink({
  client,
  processor,
  control = null,
  recoverFromRetained = false,
  recoveryTimeoutMs = RECOVERY_TIMEOUT_MS,
  log = () => {},
}) {
  const topics = topicsFor(processor.childId);
  let recovering = recoverFromRetained;
  let recoveryTimer = null;
  let publishedSignature = null;

  // So publica com o broker conectado: estado ou alerta velho entregue
  // depois da reconexao seria enganoso. O historico e republicado a cada
  // (re)conexao, entao nada se perde.
  const publishJson = (topic, message, options) => {
    if (!client.connected) return false;
    client.publish(topic, JSON.stringify(message), options);
    return true;
  };

  function publishHistory(reason) {
    if (recovering) return false; // primeiro recupera o retido
    const message = processor.history();
    if (!publishJson(topics.historico, message, { qos: 1, retain: true })) return false;
    publishedSignature = processor.signature();
    log('historico', `historico publicado (${message.episodios.length} de ${message.total} episódio(s)) — ${reason}`);
    return true;
  }

  function finishRecovery(history) {
    if (!recovering) return;
    recovering = false;
    clearTimeout(recoveryTimer);
    recoveryTimer = null;
    client.unsubscribe(topics.historico);
    if (history) {
      const n = processor.importHistory(history.episodios);
      log('recuperacao', `histórico recuperado da mensagem retida: ${n} episódio(s) importado(s)`);
    } else {
      log('recuperacao', `nenhuma mensagem retida em ${topics.historico} em ${recoveryTimeoutMs / 1000} s: começando com histórico vazio`);
    }
    publishHistory('depois da recuperação');
  }

  function onConnect() {
    const subscriptions = { [topics.ack]: { qos: 1 }, [topics.avaliacao]: { qos: 1 } };
    if (control) subscriptions[topics.controle] = { qos: 1 };
    if (recovering) subscriptions[topics.historico] = { qos: 1 };
    client.subscribe(subscriptions);
    if (recovering) {
      if (!recoveryTimer) recoveryTimer = setTimeout(() => finishRecovery(null), recoveryTimeoutMs);
    } else {
      publishHistory('conexão');
    }
  }

  function onMessage(topic, payload) {
    const text = payload.toString();
    if (topic === topics.historico) {
      // so assinado durante a recuperacao
      if (!recovering) return;
      const history = parseHistory(text);
      if (!history) log('aviso', 'mensagem retida de historico inválida: ignorada');
      finishRecovery(history);
    } else if (topic === topics.ack) {
      const ack = parseAck(text);
      if (!ack) {
        log('aviso', `ack inválido ignorado: ${text.slice(0, 80)}`);
        return;
      }
      const known = processor.applyAck(ack);
      log('ack', known
        ? `ack ("Estou ciente") aplicado ao episódio ${ack.episodio_id}`
        : `ack de episódio desconhecido (${ack.episodio_id}): republicando o histórico`);
      publishHistory('ack');
    } else if (topic === topics.avaliacao) {
      const evaluation = parseEvaluation(text);
      if (!evaluation) {
        log('aviso', `avaliação inválida ignorada: ${text.slice(0, 80)}`);
        return;
      }
      const known = processor.applyEvaluation(evaluation);
      log('avaliacao', known
        ? `avaliação "${evaluation.avaliacao}" (origem ${evaluation.origem}) aplicada ao episódio ${evaluation.episodio_id}`
        : `avaliação de episódio desconhecido (${evaluation.episodio_id}): republicando o histórico`);
      publishHistory('avaliação');
    } else if (topic === topics.controle && control) {
      const parsed = parseControl(text);
      if (!parsed) {
        log('aviso', `controle inválido ignorado (não é um objeto JSON): ${text.slice(0, 80)}`);
        return;
      }
      control.set(parsed.valores);
      const aplicados = Object.entries(parsed.valores).map(([k, v]) => `${k} ${v}`).join(', ') || 'nenhum valor';
      const ignorados = parsed.ignorados.length ? ` · ignorados (fora da faixa): ${parsed.ignorados.join(', ')}` : '';
      log('controle', `controle recebido: ${aplicados}${ignorados}`);
    }
  }

  client.on('connect', onConnect);
  client.on('message', onMessage);

  return {
    topics,
    recovering: () => recovering,

    // Uma leitura (1x/s): publica a leitura, processa e publica o resultado.
    step(reading) {
      publishJson(topics.leituras, reading, { qos: 0 });
      const result = processor.ingest(reading);
      for (const alert of result.alerts) {
        const sent = publishJson(topics.alertas, alert, { qos: 1 });
        log('alerta', `alerta ${alert.nivel_anterior} → ${alert.nivel} (${Math.round(alert.probabilidade * 100)}%)`
          + ` · episódio ${alert.episodio_id}${alert.gatilho?.texto ? ` · ${alert.gatilho.texto}` : ''}`
          + `${sent ? '' : ' (não enviado: sem conexão)'}`);
      }
      publishJson(topics.estado, processor.state(reading.timestamp), { qos: 0, retain: true });
      if (processor.signature() !== publishedSignature) publishHistory('episódio abriu, fechou ou mudou');
      return { ...result, sent: client.connected };
    },

    // Pulseira desligando: fecha o episodio aberto e publica o historico
    // final (se conectada e ja recuperada). Espera o PUBACK.
    async close() {
      clearTimeout(recoveryTimer);
      recoveryTimer = null;
      const closed = processor.close();
      if (closed) log('historico', `episódio ${closed.id} encerrado como "interrompido" (pulseira desligando)`);
      if (recovering || !client.connected) return closed;
      const message = processor.history();
      await client.publishAsync(topics.historico, JSON.stringify(message), { qos: 1, retain: true });
      publishedSignature = processor.signature();
      log('historico', `histórico final publicado (${message.episodios.length} episódio(s))`);
      return closed;
    },

    detach() {
      clearTimeout(recoveryTimer);
      client.removeListener?.('connect', onConnect);
      client.removeListener?.('message', onMessage);
    },
  };
}

// Processamento na borda (edge): a pulseira roda o modelo, os episodios e o
// gatilho e publica o resultado pronto - o app do cuidador funciona so com a
// pulseira ligada, sem site. Na pulseira real isso rodaria no ESP32 (com o
// modelo convertido para TinyML, trabalho futuro); aqui roda em Node com os
// MESMOS modulos do frontend/src (nada duplicado):
//
//   leitura -> buffer de 300 -> classifyAt (predict.js + forest.json)
//           -> ingestReadings / upsertEpisode (episodes.js) -> gatilho (trigger.js)
//              e metricas por episodio (metricas.js)
//           -> resumo de cada minuto (resumoMinuto.js)
//           -> buildStateMessage / buildAlertMessage / buildHistoryMessage /
//              buildMinuteSummaryMessage (buildMessages.js)
//
// Duas partes:
//   createEdgeProcessor  processamento puro, sem rede (usado tambem pelo
//                        verificar.js, que roda os cenarios offline);
//   createEdgeLink       ligacao com o broker: publica estado, alertas,
//                        historico e o resumo de cada minuto; aplica ack,
//                        avaliacao, controle e a ordem de reset; recupera o
//                        historico da mensagem retida; reenvia os resumos
//                        que o app perdeu quando ele volta a ficar online.
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
import { createMinuteSummarizer, MINUTE_MS } from '../frontend/src/model/resumoMinuto.js';
import {
  buildAlertMessage,
  buildHistoryMessage,
  buildMinuteSummaryMessage,
  buildMinuteSummaryMessages,
  buildStateMessage,
  historyEntryToEpisode,
  historySignature,
  topicsFor,
} from '../frontend/src/hooks/buildMessages.js';
import {
  BAND_ORIGIN, parseAck, parseAppStatus, parseControl, parseEvaluation, parseHistory, parseResetCommand,
} from '../frontend/src/hooks/parseMessages.js';

export const MAX_BUFFER = 300; // 5 min de sinal a 1 Hz (o gatilho usa ate 6 min de memoria propria)
export const RECOVERY_TIMEOUT_MS = 5000; // espera pelas mensagens retidas (historico, comando) ao iniciar
// O "offline" do app (Last Will) chega ate ~90 s depois da queda (1,5 x
// keepalive de 60 s): o reenvio comeca 5 min antes, para cobrir esse atraso.
export const RESEND_MARGIN_MS = 5 * MINUTE_MS;

// ---------------------------------------------------------------------------
// Processamento (sem rede)
// ---------------------------------------------------------------------------

// `source`: 'pulseira' (cenarios) | 'manual' (modo controle). `storage`:
// objeto getItem/setItem onde o historico fica gravado (historico.js) ou null
// (so em memoria).
export function createEdgeProcessor({ childId, source = 'pulseira', storage = null, classify = classifyAt, maxBuffer = MAX_BUFFER }) {
  const store = createEpisodeStore(storage);
  const minutes = createMinuteSummarizer();
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
      // resumo do minuto que fechou com esta leitura (ou null)
      const minuteSummary = minutes.add(reading, last.tier);
      return {
        tier: last.tier, probability: last.probability, alerts, changed: result.changed, minuteSummary,
      };
    },

    // Resumos de minuto guardados (ultimas 24 h) com minuto >= sinceMs.
    minutesSince: (sinceMs) => minutes.since(sinceMs),
    // Pulseira desligando: fecha o minuto parcial (ou null).
    flushMinute: () => minutes.flush(),
    minuteMessage: (list, motivo = 'minuto', timestamp = now()) => buildMinuteSummaryMessage(list, { childId, timestamp, motivo }),
    resendMessages: (list, timestamp = now()) => buildMinuteSummaryMessages(list, { childId, timestamp }),

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

    // Ordem de reset (puzzleband/<id>/comando): apaga os episodios e descarta
    // o episodio em andamento, sem grava-lo. A memoria dos sinais (buffer,
    // linha de base do gatilho, nivel atual) continua: se o nivel seguir
    // alto, um episodio novo comeca na proxima leitura.
    reset() {
      monitor = { ...monitor, open: null };
      store.update(() => []);
      minutes.clear();
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
// lista vazia). So aceita historico com origem "pulseira".
// `reset`: { lastAppliedId, onApply(ordem) } liga a ordem de reset do
// terminal (npm run resetar, em puzzleband/<id>/comando): ao conectar, a
// pulseira espera a ordem retida (ate `recoveryTimeoutMs`) antes de publicar
// o historico; com id novo, comeca vazia. Uma ordem que chega com a pulseira
// rodando (resetar --forcar) tambem vale. null = nao assina comando.
// `minuteSummaries`: publica o resumo de cada minuto em resumo_minuto e
// assina app/status para reenviar o que o app perdeu (docs/mqtt.md).
// `clock()`: agora em ms (testes).
// `log(evento, texto)` vai para o terminal.
export function createEdgeLink({
  client,
  processor,
  control = null,
  recoverFromRetained = false,
  recoveryTimeoutMs = RECOVERY_TIMEOUT_MS,
  reset = null,
  minuteSummaries = true,
  clock = () => Date.now(),
  log = () => {},
}) {
  const topics = topicsFor(processor.childId);
  let recovering = recoverFromRetained;
  let recoveryTimer = null;
  let checkingReset = Boolean(reset); // esperando a ordem retida (so na partida)
  let resetTimer = null;
  let lastResetId = reset?.lastAppliedId ?? null;
  let publishedSignature = null;
  // Reenvio dos resumos de minuto: o app pode ter perdido os minutos desde
  // `pendingSince` (ms; -Infinity = tudo o que ha na memoria; null = nada).
  // Marca quando o app cai (app/status "offline") ou quando a pulseira nao
  // conseguiu publicar um minuto (sem conexao); reenvia no "online" seguinte.
  let appOnline = null; // null = ainda nao sabe (acabou de conectar)
  let pendingSince = null;
  const markPending = (ms) => {
    pendingSince = pendingSince === null ? ms : Math.min(pendingSince, ms);
  };

  // So publica com o broker conectado: estado ou alerta velho entregue
  // depois da reconexao seria enganoso. O historico e republicado a cada
  // (re)conexao, entao nada se perde.
  const publishJson = (topic, message, options) => {
    if (!client.connected) return false;
    client.publish(topic, JSON.stringify(message), options);
    return true;
  };

  function publishHistory(reason) {
    if (recovering || checkingReset) return false; // primeiro o retido (historico e comando)
    const message = processor.history();
    if (!publishJson(topics.historico, message, { qos: 1, retain: true })) return false;
    publishedSignature = processor.signature();
    log('historico', `historico publicado (${message.episodios.length} de ${message.total} episódio(s)) — ${reason}`);
    return true;
  }

  function stopRecovery() {
    recovering = false;
    clearTimeout(recoveryTimer);
    recoveryTimer = null;
    client.unsubscribe(topics.historico);
  }

  function finishRecovery(history) {
    if (!recovering) return;
    stopRecovery();
    if (history) {
      const n = processor.importHistory(history.episodios);
      log('recuperacao', `histórico recuperado da mensagem retida: ${n} episódio(s) importado(s)`);
    } else {
      log('recuperacao', `nenhum histórico da pulseira retido em ${topics.historico}: começando com histórico vazio`);
    }
    publishHistory('depois da recuperação');
  }

  function finishResetCheck() {
    if (!checkingReset) return;
    checkingReset = false;
    clearTimeout(resetTimer);
    resetTimer = null;
    publishHistory('conexão');
  }

  // Ordem de reset com id novo: historico vazio (como --limpar-historico)
  function applyReset(order) {
    lastResetId = order.id;
    processor.reset();
    pendingSince = null;
    reset.onApply?.(order);
    log('reset', `ordem de reset ${order.id} aplicada: histórico de episódios apagado`
      + `${checkingReset ? ' (começando vazia)' : ' (com a pulseira rodando)'}`);
    // a ordem manda comecar vazia: o historico retido nao e importado
    if (recovering) stopRecovery();
  }

  function publishMinute(summary, motivo = 'minuto') {
    if (!summary) return;
    if (!publishJson(topics.resumoMinuto, processor.minuteMessage([summary], motivo), { qos: 1 })) {
      markPending(Date.parse(summary.minuto));
    }
  }

  function resendMinutes() {
    if (pendingSince === null) return;
    const list = processor.minutesSince(pendingSince);
    pendingSince = null;
    if (!list.length) return;
    const messages = processor.resendMessages(list);
    for (const message of messages) publishJson(topics.resumoMinuto, message, { qos: 1 });
    log('resumo', `app online de novo: ${list.length} resumo(s) de minuto reenviado(s) em ${messages.length} mensagem(ns)`);
  }

  function onAppStatus(text) {
    const status = parseAppStatus(text);
    if (!status) return; // payload vazio (reset apagando o retido)
    if (status === 'offline') {
      // visto ao vivo: desde a queda (com margem); retido: nao se sabe desde quando
      if (appOnline !== false) markPending(appOnline === true ? clock() - RESEND_MARGIN_MS : -Infinity);
      appOnline = false;
    } else {
      appOnline = true;
      resendMinutes();
    }
  }

  function onConnect() {
    appOnline = null;
    const subscriptions = { [topics.ack]: { qos: 1 }, [topics.avaliacao]: { qos: 1 } };
    if (minuteSummaries) subscriptions[topics.appStatus] = { qos: 1 };
    if (control) subscriptions[topics.controle] = { qos: 1 };
    if (reset) subscriptions[topics.comando] = { qos: 1 };
    if (recovering) subscriptions[topics.historico] = { qos: 1 };
    client.subscribe(subscriptions);
    if (checkingReset && !resetTimer) resetTimer = setTimeout(finishResetCheck, recoveryTimeoutMs);
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
      let history = parseHistory(text);
      if (!history) {
        log('aviso', 'mensagem retida de historico inválida: ignorada');
      } else if (history.origem !== BAND_ORIGIN) {
        // so a pulseira publica historico; outra origem (ex.: aba antiga do site) nao entra
        log('aviso', `histórico retido com origem "${history.origem ?? 'sem origem'}" ignorado (só vale o da pulseira)`);
        history = null;
      }
      finishRecovery(history);
    } else if (topic === topics.comando && reset) {
      const order = parseResetCommand(text);
      if (order && order.id !== lastResetId) {
        applyReset(order);
        if (!checkingReset) publishHistory('ordem de reset');
      } else if (order && checkingReset) {
        log('reset', `ordem de reset ${order.id} retida: já aplicada antes, nada a apagar`);
      }
      finishResetCheck(); // a retida (se houver) chega logo apos a assinatura
    } else if (topic === topics.appStatus && minuteSummaries) {
      onAppStatus(text);
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
    checkingReset: () => checkingReset,

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
      if (minuteSummaries) publishMinute(result.minuteSummary);
      if (processor.signature() !== publishedSignature) publishHistory('episódio abriu, fechou ou mudou');
      return { ...result, sent: client.connected };
    },

    // Pulseira desligando: fecha o episodio aberto e publica o historico
    // final (se conectada e ja recuperada). Espera o PUBACK.
    async close() {
      clearTimeout(recoveryTimer);
      recoveryTimer = null;
      clearTimeout(resetTimer);
      resetTimer = null;
      const closed = processor.close();
      if (closed) log('historico', `episódio ${closed.id} encerrado como "interrompido" (pulseira desligando)`);
      const partial = processor.flushMinute();
      if (minuteSummaries) publishMinute(partial);
      if (recovering || checkingReset || !client.connected) return closed;
      const message = processor.history();
      await client.publishAsync(topics.historico, JSON.stringify(message), { qos: 1, retain: true });
      publishedSignature = processor.signature();
      log('historico', `histórico final publicado (${message.episodios.length} episódio(s))`);
      return closed;
    },

    detach() {
      clearTimeout(recoveryTimer);
      clearTimeout(resetTimer);
      client.removeListener?.('connect', onConnect);
      client.removeListener?.('message', onMessage);
    },
  };
}

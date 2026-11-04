// Mensagens que o site publica para o app do cuidador (ver docs/mqtt.md).
// Funcoes puras (testadas em Node): o hook useCaregiverSync so decide QUANDO
// publicar; o QUE vai em cada mensagem fica aqui.

import { SITE_ORIGIN } from './parseMessages.js';

export const STATE_INTERVAL_MS = 1000; // estado: 1 vez por segundo
export const HISTORY_TOPIC_LIMIT = 50; // historico: os 50 episodios mais recentes

// Leituras atuais que vao no estado (accel_mag_g e idade ficam de fora: o
// app nao mostra e o modelo roda no site).
const STATE_READING_FIELDS = ['bpm', 'eda_uS', 'hrv_ms', 'gyro_mag_dps', 'regularidade', 'luz_lux', 'ruido_db'];

export function topicsFor(childId) {
  const base = `puzzleband/${childId}`;
  return {
    leituras: `${base}/leituras`,
    status: `${base}/status`,
    estado: `${base}/estado`,
    alertas: `${base}/alertas`,
    historico: `${base}/historico`,
    avaliacao: `${base}/avaliacao`,
    ack: `${base}/ack`,
    appStatus: `${base}/app/status`,
  };
}

// Fonte no protocolo: "manual" | "pulseira" (internamente o site usa 'mqtt').
export const protocolSource = (source) => (source === 'mqtt' ? 'pulseira' : 'manual');

const round = (v, digits) => {
  const f = 10 ** digits;
  return Math.round(v * f) / f;
};

// Gatilho resumido (estado e historico). O objeto completo vai so no alerta.
const compactTrigger = (gatilho) => (gatilho ? { tipo: gatilho.tipo ?? null, texto: gatilho.texto ?? '' } : null);

export function averageBpm(readings) {
  const values = readings.map((r) => r?.bpm).filter((v) => Number.isFinite(v));
  if (!values.length) return null;
  return round(values.reduce((a, b) => a + b, 0) / values.length, 1);
}

function pickReading(reading) {
  if (!reading) return null;
  const out = { timestamp: reading.timestamp };
  for (const field of STATE_READING_FIELDS) out[field] = Number.isFinite(reading[field]) ? reading[field] : null;
  return out;
}

// puzzleband/<id>/estado (QoS 0, retain). `readings` e o buffer do site (ate
// 300 leituras = 5 min de sinal a 1 Hz); `openEpisode` o episodio em
// andamento ou null.
export function buildStateMessage({ timestamp, source, childId, tier, probability, readings, openEpisode }) {
  const list = readings ?? [];
  return {
    origem: SITE_ORIGIN,
    timestamp,
    fonte: protocolSource(source),
    crianca: childId ?? null,
    nivel: tier,
    probabilidade: Number.isFinite(probability) ? round(probability, 3) : null,
    leituras: pickReading(list[list.length - 1]),
    media_bpm_5min: averageBpm(list),
    gatilho: openEpisode ? compactTrigger(openEpisode.gatilho) : null,
    episodio: openEpisode
      ? {
        id: openEpisode.id,
        inicio: openEpisode.inicio,
        nivel_maximo: openEpisode.nivel_maximo,
        visto_pelo_cuidador_em: openEpisode.visto_pelo_cuidador_em ?? null,
      }
      : null,
  };
}

// puzzleband/<id>/alertas (QoS 1). `alert` vem de ingestReadings
// (model/episodes.js) com o timestamp acrescentado pelo useEpisodeMonitor.
export function buildAlertMessage(alert, { source, childId }) {
  return {
    origem: SITE_ORIGIN,
    timestamp: alert.timestamp ?? new Date().toISOString(),
    fonte: protocolSource(source),
    crianca: childId ?? null,
    episodio_id: alert.episodio_id ?? null,
    nivel_anterior: alert.nivel_anterior ?? null,
    nivel: alert.nivel,
    probabilidade: alert.probabilidade,
    gatilho: alert.gatilho ?? null,
    leituras: alert.leituras ?? null,
  };
}

// Um episodio no topico historico: os campos que o EpisodeHistory mostra.
export function historyEntry(ep) {
  return {
    id: ep.id,
    crianca: ep.crianca,
    fonte: protocolSource(ep.fonte),
    inicio: ep.inicio,
    fim: ep.fim ?? null,
    duracao_s: Number.isFinite(ep.duracao_s) ? ep.duracao_s : null,
    encerramento: ep.encerramento ?? null, // null = em andamento
    nivel_maximo: ep.nivel_maximo,
    probabilidade_maxima: ep.probabilidade_maxima,
    gatilho: compactTrigger(ep.gatilho),
    avaliacao_cuidador: ep.avaliacao_cuidador,
    observacao: ep.observacao ?? '',
    avaliacao_origem: ep.avaliacao_origem ?? null,
    avaliacao_em: ep.avaliacao_em ?? null,
    visto_pelo_cuidador_em: ep.visto_pelo_cuidador_em ?? null,
  };
}

// puzzleband/<id>/historico (QoS 1, retain). `episodes` mais recente primeiro.
export function buildHistoryMessage(episodes, { childId, timestamp }) {
  return {
    origem: SITE_ORIGIN,
    timestamp,
    crianca: childId ?? null,
    total: episodes.length,
    episodios: episodes.slice(0, HISTORY_TOPIC_LIMIT).map(historyEntry),
  };
}

// Muda quando um episodio abre, fecha, muda de nivel maximo/gatilho ou e
// avaliado/visto - mas NAO a cada segundo de duracao. O site republica o
// historico quando a assinatura muda.
export function historySignature(episodes) {
  return episodes
    .slice(0, HISTORY_TOPIC_LIMIT)
    .map((ep) => [
      ep.id,
      ep.encerramento ?? '',
      ep.nivel_maximo,
      ep.gatilho?.tipo ?? '',
      ep.avaliacao_cuidador,
      ep.observacao ?? '',
      ep.avaliacao_origem ?? '',
      ep.avaliacao_em ?? '',
      ep.visto_pelo_cuidador_em ?? '',
    ].join('|'))
    .join('\n');
}

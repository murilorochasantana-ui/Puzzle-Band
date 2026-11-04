// Validacao das mensagens MQTT recebidas. Mensagens malformadas viram null
// (o chamador descarta) - nunca lancam excecao pra nao quebrar a tela.
// Formatos e topicos: docs/mqtt.md.

import { OBSERVATION_MAX_LENGTH } from '../model/episodes.js';

// Origem que o site coloca nas mensagens que ele publica. Uma mensagem com
// esta origem chegando de volta e eco do proprio site: e ignorada (evita laco).
export const SITE_ORIGIN = 'site';

// Campos numericos que model/predict.js (computeFeatures) usa de cada leitura.
const NUMERIC_FIELDS = [
  'bpm', 'eda_uS', 'gyro_mag_dps', 'hrv_ms', 'accel_mag_g',
  'regularidade', 'luz_lux', 'ruido_db', 'idade',
];

function parseObject(text) {
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    return null;
  }
  if (data === null || typeof data !== 'object' || Array.isArray(data)) return null;
  return data;
}

// Timestamp ISO valido ou null (quem chama usa "agora" no lugar).
function optionalTimestamp(value) {
  if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) return null;
  return value;
}

const nonEmptyString = (value) => typeof value === 'string' && value.trim() !== '';

export function parseReading(text) {
  const data = parseObject(text);
  if (!data) return null;
  if (typeof data.timestamp !== 'string' || Number.isNaN(Date.parse(data.timestamp))) return null;

  const reading = { timestamp: data.timestamp };
  for (const field of NUMERIC_FIELDS) {
    if (typeof data[field] !== 'number' || !Number.isFinite(data[field])) return null;
    reading[field] = data[field];
  }
  return reading;
}

// Status de presenca e texto puro: "online" ou "offline". Vale para a
// pulseira (puzzleband/<id>/status) e para o app (puzzleband/<id>/app/status).
export function parseOnlineStatus(text) {
  const value = text.trim().toLowerCase();
  return value === 'online' || value === 'offline' ? value : null;
}

export const parseBandStatus = parseOnlineStatus;
export const parseAppStatus = parseOnlineStatus;

// puzzleband/<id>/avaliacao (publicado pelo app):
//   { episodio_id, avaliacao: "confirmado" | "descartado", observacao?, origem: "app", timestamp }
const APP_EVALUATIONS = ['confirmado', 'descartado'];

export function parseEvaluation(text) {
  const data = parseObject(text);
  if (!data || data.origem === SITE_ORIGIN) return null;
  if (!nonEmptyString(data.episodio_id) || !APP_EVALUATIONS.includes(data.avaliacao)) return null;

  const result = {
    episodio_id: data.episodio_id,
    avaliacao: data.avaliacao,
    origem: nonEmptyString(data.origem) ? data.origem : 'app',
    timestamp: optionalTimestamp(data.timestamp),
  };
  if (data.observacao !== undefined && data.observacao !== null) {
    if (typeof data.observacao !== 'string') return null;
    result.observacao = data.observacao.slice(0, OBSERVATION_MAX_LENGTH);
  }
  return result;
}

// puzzleband/<id>/ack (publicado pelo app no "Estou ciente"):
//   { episodio_id, timestamp }
export function parseAck(text) {
  const data = parseObject(text);
  if (!data || data.origem === SITE_ORIGIN) return null;
  if (!nonEmptyString(data.episodio_id)) return null;
  return { episodio_id: data.episodio_id, timestamp: optionalTimestamp(data.timestamp) };
}

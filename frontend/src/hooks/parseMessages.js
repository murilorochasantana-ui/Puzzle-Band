// Validacao das mensagens MQTT recebidas. Mensagens malformadas viram null
// (o chamador descarta) - nunca lancam excecao pra nao quebrar a tela nem a
// pulseira. Formatos e topicos: docs/mqtt.md.
//
// Quem usa:
//   pulseira (simulator/borda.js): parseAck, parseEvaluation, parseControl e
//     parseHistory (para recuperar o historico da mensagem retida ao iniciar);
//   site (painel, hooks/useBandLink.js): parseReading, parseState,
//     parseAlert, parseHistory e os status online/offline.

import { EVALUATIONS, OBSERVATION_MAX_LENGTH } from '../model/episodes.js';
import { CONTROL_LIMITS } from '../model/simulate.js';

// Origem de quem publica. A pulseira poe "pulseira" em estado, alertas e
// historico; o painel do site poe "site" em avaliacao e controle; o app poe
// "app" em avaliacao e ack.
export const BAND_ORIGIN = 'pulseira';
export const SITE_ORIGIN = 'site';
export const APP_ORIGIN = 'app';

const TIERS = ['baixo_risco', 'atencao', 'alto_risco'];

// Campos numericos que model/predict.js (computeFeatures) usa de cada leitura.
const NUMERIC_FIELDS = [
  'bpm', 'eda_uS', 'gyro_mag_dps', 'hrv_ms', 'accel_mag_g',
  'regularidade', 'luz_lux', 'ruido_db', 'idade',
];

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);

function parseObject(text) {
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    return null;
  }
  return isObject(data) ? data : null;
}

// Timestamp ISO valido ou null (quem chama usa "agora" no lugar).
function optionalTimestamp(value) {
  if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) return null;
  return value;
}

const nonEmptyString = (value) => typeof value === 'string' && value.trim() !== '';
const optionalString = (value) => (typeof value === 'string' ? value : null);
const optionalNumber = (value) => (typeof value === 'number' && Number.isFinite(value) ? value : null);
const optionalTier = (value) => (TIERS.includes(value) ? value : null);

// Gatilho resumido ({ tipo, texto }) ou null
function optionalTrigger(value) {
  if (!isObject(value)) return null;
  return { tipo: optionalString(value.tipo), texto: optionalString(value.texto) ?? '' };
}

// ---------------------------------------------------------------------------
// Pulseira -> site (o site so mostra)
// ---------------------------------------------------------------------------

// puzzleband/<id>/leituras: leitura bruta dos sensores, 1x/s
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

// puzzleband/<id>/estado (pulseira, 1x/s, retain). Mesma exigencia do app:
// sem `nivel` valido a mensagem e descartada; o resto vira null se vier errado.
export function parseState(text) {
  const data = parseObject(text);
  if (!data || !TIERS.includes(data.nivel)) return null;
  const ep = data.episodio;
  return {
    timestamp: optionalTimestamp(data.timestamp),
    fonte: optionalString(data.fonte),
    crianca: optionalString(data.crianca),
    nivel: data.nivel,
    probabilidade: optionalNumber(data.probabilidade),
    media_bpm_5min: optionalNumber(data.media_bpm_5min),
    gatilho: optionalTrigger(data.gatilho),
    episodio: isObject(ep) && nonEmptyString(ep.id)
      ? {
        id: ep.id,
        inicio: optionalTimestamp(ep.inicio),
        nivel_maximo: optionalTier(ep.nivel_maximo),
        visto_pelo_cuidador_em: optionalTimestamp(ep.visto_pelo_cuidador_em),
      }
      : null,
  };
}

// puzzleband/<id>/alertas (pulseira, QoS 1, na mudanca de nivel)
export function parseAlert(text) {
  const data = parseObject(text);
  if (!data || !TIERS.includes(data.nivel)) return null;
  return {
    timestamp: optionalTimestamp(data.timestamp),
    fonte: optionalString(data.fonte),
    episodio_id: nonEmptyString(data.episodio_id) ? data.episodio_id : null,
    nivel_anterior: optionalTier(data.nivel_anterior),
    nivel: data.nivel,
    probabilidade: optionalNumber(data.probabilidade),
    gatilho: optionalTrigger(data.gatilho),
  };
}

// Um episodio do topico historico (o formato de historyEntry em
// buildMessages.js). Sem id, inicio ou nivel_maximo validos o app pula o
// episodio; aqui tambem.
function parseHistoryEntry(raw) {
  if (!isObject(raw) || !nonEmptyString(raw.id) || !optionalTimestamp(raw.inicio) || !TIERS.includes(raw.nivel_maximo)) {
    return null;
  }
  return {
    id: raw.id,
    crianca: optionalString(raw.crianca),
    fonte: optionalString(raw.fonte),
    inicio: raw.inicio,
    fim: optionalTimestamp(raw.fim),
    duracao_s: optionalNumber(raw.duracao_s),
    encerramento: optionalString(raw.encerramento),
    nivel_maximo: raw.nivel_maximo,
    probabilidade_maxima: optionalNumber(raw.probabilidade_maxima) ?? 0,
    gatilho: optionalTrigger(raw.gatilho),
    avaliacao_cuidador: EVALUATIONS.includes(raw.avaliacao_cuidador) ? raw.avaliacao_cuidador : 'pendente',
    observacao: typeof raw.observacao === 'string' ? raw.observacao.slice(0, OBSERVATION_MAX_LENGTH) : '',
    avaliacao_origem: optionalString(raw.avaliacao_origem),
    avaliacao_em: optionalTimestamp(raw.avaliacao_em),
    visto_pelo_cuidador_em: optionalTimestamp(raw.visto_pelo_cuidador_em),
  };
}

// puzzleband/<id>/historico (pulseira, QoS 1, retain): a lista inteira (os
// 50 mais recentes). Episodios invalidos sao pulados, como no app.
export function parseHistory(text) {
  const data = parseObject(text);
  if (!data || !Array.isArray(data.episodios)) return null;
  const episodios = data.episodios.map(parseHistoryEntry).filter(Boolean);
  return {
    timestamp: optionalTimestamp(data.timestamp),
    crianca: optionalString(data.crianca),
    total: Number.isInteger(data.total) && data.total >= episodios.length ? data.total : episodios.length,
    episodios,
  };
}

// ---------------------------------------------------------------------------
// App / painel do site -> pulseira (a pulseira aplica no historico)
// ---------------------------------------------------------------------------

// puzzleband/<id>/avaliacao:
//   { episodio_id, avaliacao: "confirmado" | "descartado" | "pendente", observacao?, origem: "app" | "site", timestamp }
// O app manda "confirmado"/"descartado"; o painel do site tambem manda
// "pendente" para desfazer uma avaliacao. Sem origem, vale "app".
const EVALUATION_ORIGINS = [APP_ORIGIN, SITE_ORIGIN];

export function parseEvaluation(text) {
  const data = parseObject(text);
  if (!data) return null;
  const origem = data.origem ?? APP_ORIGIN;
  if (!EVALUATION_ORIGINS.includes(origem)) return null;
  if (!nonEmptyString(data.episodio_id) || !EVALUATIONS.includes(data.avaliacao)) return null;

  const result = {
    episodio_id: data.episodio_id,
    avaliacao: data.avaliacao,
    origem,
    timestamp: optionalTimestamp(data.timestamp),
  };
  if (data.observacao !== undefined && data.observacao !== null) {
    if (typeof data.observacao !== 'string') return null;
    result.observacao = data.observacao.slice(0, OBSERVATION_MAX_LENGTH);
  }
  return result;
}

// puzzleband/<id>/ack (publicado pelo app no "Estou ciente"):
//   { episodio_id, timestamp, origem: "app" }
// Descarta o que tem origem "pulseira" (a pulseira nunca publica ack: seria eco).
export function parseAck(text) {
  const data = parseObject(text);
  if (!data || data.origem === BAND_ORIGIN) return null;
  if (!nonEmptyString(data.episodio_id)) return null;
  return { episodio_id: data.episodio_id, timestamp: optionalTimestamp(data.timestamp) };
}

// puzzleband/<id>/controle (painel do site -> pulseira no modo controle):
//   { bpm, eda, hrv, movimento, regularidade, luz, ruido, idade, origem: "site", timestamp }
// Todos os valores sao opcionais. Cada um e conferido sozinho contra
// CONTROL_LIMITS (model/simulate.js): valido entra em `valores`; tipo errado
// ou fora da faixa vai para `ignorados` e os outros continuam valendo.
// Campos desconhecidos sao ignorados em silencio. null = nao e um objeto JSON.
export function parseControl(text) {
  const data = parseObject(text);
  if (!data) return null;
  const valores = {};
  const ignorados = [];
  for (const [campo, faixa] of Object.entries(CONTROL_LIMITS)) {
    if (!(campo in data)) continue;
    const valor = data[campo];
    const ok = typeof valor === 'number' && Number.isFinite(valor)
      && valor >= faixa.min && valor <= faixa.max
      && (!faixa.inteiro || Number.isInteger(valor));
    if (ok) valores[campo] = valor;
    else ignorados.push(campo);
  }
  return { valores, ignorados };
}

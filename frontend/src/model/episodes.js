// Historico de episodios (ver docs/historico.md). Funcoes puras, sem React:
// o dashboard usa via hooks/useEpisodeMonitor.js, e os testes/simulador
// podem usar direto em Node.
//
// Episodio: comeca quando o nivel sai de baixo_risco; termina quando volta
// para baixo_risco e PERMANECE assim por EPISODE_END_CALM_S (histerese, para
// uma oscilacao curta nao partir um episodio em varios).

import { analyzeTrigger, reviewTrigger, BASELINE_WINDOW_S, ANALYSIS_WINDOW_S, SAMPLE_PERIOD_S } from './trigger.js';

export const EPISODE_END_CALM_S = 30;
export const HISTORY_STORAGE_KEY = 'puzzleband_historico';
export const HISTORY_LIMIT = 200;
export const OBSERVATION_MAX_LENGTH = 200;
export const EVALUATIONS = ['pendente', 'confirmado', 'descartado'];

const CALM_TIER = 'baixo_risco';
const TIER_RANK = { baixo_risco: 0, atencao: 1, alto_risco: 2 };
// O gatilho precisa da linha de base (5 min) + janela de analise (60 s)
const SIGNAL_MEMORY = Math.ceil((BASELINE_WINDOW_S + ANALYSIS_WINDOW_S) / SAMPLE_PERIOD_S) + 1;

const round3 = (v) => Math.round(v * 1000) / 1000;

// ---------------------------------------------------------------------------
// Rastreador (uma leitura por vez)
// ---------------------------------------------------------------------------

export function createMonitor({ childId, source }) {
  return {
    crianca: childId || 'simulada',
    fonte: source,
    nextT: 0,
    history: [],
    prevTier: CALM_TIER,
    open: null,
  };
}

// Processa UMA leitura ja classificada pelo modelo. Devolve o novo estado,
// o episodio criado/alterado nesta leitura (ou null) e a mudanca de nivel
// (ou null) - usada para publicar alertas no MQTT.
export function stepMonitor(monitor, { reading, tier, probability }) {
  const t = monitor.nextT;
  const history = [...monitor.history, { t, reading, tier }];
  if (history.length > SIGNAL_MEMORY) history.splice(0, history.length - SIGNAL_MEMORY);

  const tierChange = tier !== monitor.prevTier
    ? { de: monitor.prevTier, para: tier, reading, probability }
    : null;
  const isAlert = tier !== CALM_TIER;
  const prob = Number.isFinite(probability) ? round3(probability) : 0;

  let open = monitor.open;
  let episode = null;

  if (!open) {
    if (isAlert) {
      episode = {
        id: `ep_${Date.parse(reading.timestamp) || 0}_${t}`,
        crianca: monitor.crianca,
        fonte: monitor.fonte,
        inicio: reading.timestamp,
        fim: null,
        duracao_s: SAMPLE_PERIOD_S,
        encerramento: null,
        nivel_maximo: tier,
        probabilidade_maxima: prob,
        gatilho: analyzeTrigger(history, history.length - 1),
        avaliacao_cuidador: 'pendente',
        observacao: '',
        ultima_leitura: reading.timestamp,
      };
      open = { tStart: t, calmSince: null, episode };
    }
  } else {
    const prev = open.episode;
    let calmSince = open.calmSince;
    if (isAlert) calmSince = null;
    else if (!calmSince) calmSince = { t, timestamp: reading.timestamp };

    const endT = calmSince ? calmSince.t : t + SAMPLE_PERIOD_S;
    episode = {
      ...prev,
      gatilho: reviewTrigger(prev.gatilho, history),
      nivel_maximo: TIER_RANK[tier] > TIER_RANK[prev.nivel_maximo] ? tier : prev.nivel_maximo,
      probabilidade_maxima: Math.max(prev.probabilidade_maxima, prob),
      duracao_s: endT - open.tStart,
      ultima_leitura: reading.timestamp,
    };

    if (calmSince && t - calmSince.t + SAMPLE_PERIOD_S >= EPISODE_END_CALM_S) {
      // fim = instante em que voltou para baixo_risco (nao o fim da histerese)
      episode.fim = calmSince.timestamp;
      episode.encerramento = 'normalizou';
      open = null;
    } else {
      open = { ...open, calmSince, episode };
    }
  }

  return {
    monitor: { ...monitor, nextT: t + SAMPLE_PERIOD_S, history, prevTier: tier, open },
    episode,
    tierChange,
  };
}

// Monitoramento interrompido (buffer reiniciado, troca de fonte, pagina
// fechada): fecha o episodio aberto com o que se sabe ate aqui.
export function closeOpenEpisode(monitor) {
  if (!monitor?.open) return null;
  const { episode, calmSince } = monitor.open;
  return {
    ...episode,
    fim: calmSince ? calmSince.timestamp : episode.ultima_leitura,
    encerramento: 'interrompido',
  };
}

const ALERT_TIERS = new Set(['atencao', 'alto_risco']);

// Processa as leituras NOVAS de um buffer deslizante (o do dashboard, com no
// maximo 300 leituras): tudo depois de `lastReading`. Se o buffer foi
// esvaziado ou trocado, o episodio aberto e fechado como interrompido.
// `classify(readings, i)` devolve { tier, probability } (ver classify.js).
// Retorna o novo estado, os episodios alterados e os alertas a publicar
// (mudanca de nivel PARA atencao/alto_risco, com o gatilho do episodio).
export function ingestReadings(monitor, lastReading, readings, classify) {
  let current = monitor;
  const changed = [];
  const alerts = [];
  const restart = () => {
    const closed = closeOpenEpisode(current);
    if (closed) changed.push(closed);
    current = createMonitor({ childId: current.crianca, source: current.fonte });
  };

  if (!readings.length) {
    if (lastReading) restart();
    return { monitor: current, lastReading: null, changed, alerts };
  }

  let start = 0;
  if (lastReading) {
    const idx = readings.lastIndexOf(lastReading);
    if (idx === -1) restart();
    else start = idx + 1;
  }

  for (let i = start; i < readings.length; i += 1) {
    const reading = readings[i];
    const { tier, probability } = classify(readings, i);
    const step = stepMonitor(current, { reading, tier, probability });
    current = step.monitor;
    if (step.episode) changed.push(step.episode);

    const change = step.tierChange;
    if (change && ALERT_TIERS.has(change.para) && Number.isFinite(probability)) {
      const open = current.open?.episode;
      alerts.push({
        nivel_anterior: change.de,
        nivel: change.para,
        probabilidade: Number(probability.toFixed(3)),
        leituras: reading,
        episodio_id: open?.id ?? null,
        gatilho: open?.gatilho ?? null,
      });
    }
  }

  return { monitor: current, lastReading: readings[readings.length - 1], changed, alerts };
}

// ---------------------------------------------------------------------------
// Lista de episodios (mais recente primeiro)
// ---------------------------------------------------------------------------

// Campos que so o cuidador altera (no site ou pelo app via MQTT): o
// rastreador nao os conhece, entao numa atualizacao eles sempre vem da lista.
//   avaliacao_origem         'site' | 'app' (quem avaliou por ultimo)
//   avaliacao_em             quando avaliou (ISO)
//   visto_pelo_cuidador_em   quando o cuidador tocou "Estou ciente" no app (ISO)
export const CAREGIVER_FIELDS = [
  'avaliacao_cuidador', 'observacao', 'avaliacao_origem', 'avaliacao_em', 'visto_pelo_cuidador_em',
];

// Insere ou atualiza, preservando os campos do cuidador.
export function upsertEpisode(list, episode, limit = HISTORY_LIMIT) {
  const idx = list.findIndex((e) => e.id === episode.id);
  if (idx === -1) return [episode, ...list].slice(0, limit);
  const existing = list[idx];
  const next = [...list];
  const merged = { ...episode };
  for (const field of CAREGIVER_FIELDS) {
    if (field in existing) merged[field] = existing[field];
  }
  next[idx] = merged;
  return next;
}

export function updateEpisode(list, id, changes) {
  const patch = { ...changes };
  if ('avaliacao_cuidador' in patch && !EVALUATIONS.includes(patch.avaliacao_cuidador)) {
    patch.avaliacao_cuidador = 'pendente';
  }
  if ('observacao' in patch) {
    patch.observacao = String(patch.observacao ?? '').slice(0, OBSERVATION_MAX_LENGTH);
  }
  return list.map((e) => (e.id === id ? { ...e, ...patch } : e));
}

// ---------------------------------------------------------------------------
// Persistencia (localStorage ou qualquer objeto com getItem/setItem)
// ---------------------------------------------------------------------------

function normalizeEpisode(raw) {
  if (!raw || typeof raw !== 'object' || typeof raw.id !== 'string' || typeof raw.inicio !== 'string') return null;
  const ep = {
    ...raw,
    avaliacao_cuidador: EVALUATIONS.includes(raw.avaliacao_cuidador) ? raw.avaliacao_cuidador : 'pendente',
    observacao: typeof raw.observacao === 'string' ? raw.observacao.slice(0, OBSERVATION_MAX_LENGTH) : '',
  };
  // Ficou "em andamento" quando a pagina foi fechada: marca como interrompido
  if (!ep.encerramento) {
    ep.encerramento = 'interrompido';
    ep.fim = ep.fim ?? ep.ultima_leitura ?? ep.inicio;
  }
  return ep;
}

export function loadEpisodes(storage) {
  if (!storage) return { episodes: [], ok: false };
  try {
    const raw = storage.getItem(HISTORY_STORAGE_KEY);
    if (!raw) return { episodes: [], ok: true };
    const data = JSON.parse(raw);
    if (!Array.isArray(data)) return { episodes: [], ok: false };
    const episodes = data
      .map(normalizeEpisode)
      .filter(Boolean)
      .sort((a, b) => Date.parse(b.inicio) - Date.parse(a.inicio))
      .slice(0, HISTORY_LIMIT);
    return { episodes, ok: true };
  } catch {
    return { episodes: [], ok: false };
  }
}

export function saveEpisodes(storage, episodes) {
  if (!storage) return false;
  try {
    storage.setItem(HISTORY_STORAGE_KEY, JSON.stringify(episodes.slice(0, HISTORY_LIMIT)));
    return true;
  } catch {
    return false;
  }
}

// Store minimo (subscribe/getSnapshot, formato do useSyncExternalStore do
// React): toda atualizacao ja grava no storage. Se a gravacao falhar, a
// lista continua valendo em memoria e storageOk vira false.
export function createEpisodeStore(storage) {
  let snapshot = { episodes: loadEpisodes(storage).episodes, storageOk: true };
  const listeners = new Set();
  return {
    getSnapshot: () => snapshot,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    update(updater) {
      const episodes = updater(snapshot.episodes);
      if (episodes === snapshot.episodes) return;
      snapshot = { episodes, storageOk: saveEpisodes(storage, episodes) };
      listeners.forEach((listener) => listener());
    },
  };
}

// ---------------------------------------------------------------------------
// Resumo de padroes por crianca
// ---------------------------------------------------------------------------

const TRIGGER_GROUPS = {
  ruido: ['ruido', 'ruido_e_luminosidade'],
  luminosidade: ['luminosidade', 'ruido_e_luminosidade'],
  nenhum_ambiental: ['nenhum_ambiental'],
};

export function summarizeByChild(episodes) {
  const groups = new Map();
  for (const ep of episodes) {
    if (!groups.has(ep.crianca)) groups.set(ep.crianca, []);
    groups.get(ep.crianca).push(ep);
  }
  return [...groups.entries()].map(([crianca, list]) => {
    const finished = list.filter((e) => e.encerramento === 'normalizou' && Number.isFinite(e.duracao_s));
    const gatilhos = {};
    for (const [group, tipos] of Object.entries(TRIGGER_GROUPS)) {
      const matching = list.filter((e) => tipos.includes(e.gatilho?.tipo));
      gatilhos[group] = {
        total: matching.length,
        confirmados: matching.filter((e) => e.avaliacao_cuidador === 'confirmado').length,
      };
    }
    const count = (value) => list.filter((e) => e.avaliacao_cuidador === value).length;
    return {
      crianca,
      total: list.length,
      em_andamento: list.filter((e) => !e.encerramento).length,
      duracao_media_s: finished.length
        ? Math.round(finished.reduce((sum, e) => sum + e.duracao_s, 0) / finished.length)
        : null,
      gatilhos,
      avaliacao: { confirmado: count('confirmado'), descartado: count('descartado'), pendente: count('pendente') },
    };
  });
}

// ---------------------------------------------------------------------------
// Exportacao CSV (padrao do Excel em portugues: ";" e virgula decimal)
// ---------------------------------------------------------------------------

const pad = (n) => String(n).padStart(2, '0');

// Data/hora LOCAL "AAAA-MM-DD HH:MM:SS" (o Excel reconhece como data)
export function formatLocalDateTime(iso) {
  const d = new Date(iso);
  if (!iso || Number.isNaN(d.getTime())) return '';
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

const csvNumber = (v, digits = 0) => (Number.isFinite(v) ? v.toFixed(digits).replace('.', ',') : '');

function csvText(value) {
  let s = value === null || value === undefined ? '' : String(value);
  // evita que o Excel interprete texto livre como formula
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  if (/[";\r\n]/.test(s)) s = `"${s.replace(/"/g, '""')}"`;
  return s;
}

export const CSV_COLUMNS = [
  'id', 'crianca', 'fonte', 'inicio', 'fim', 'duracao_s', 'encerramento',
  'nivel_maximo', 'probabilidade_maxima',
  'gatilho_tipo', 'gatilho_texto', 'baseline_confiavel', 'fisiologia_sinal',
  'ruido_status', 'ruido_linha_base_db', 'ruido_pico_db', 'ruido_antecedencia_s',
  'luz_status', 'luz_linha_base_lux', 'luz_pico_lux', 'luz_variacao_pct', 'luz_antecedencia_s',
  'avaliacao_cuidador', 'observacao',
];

function csvRow(ep) {
  const g = ep.gatilho;
  const ruido = g?.sinais?.ruido;
  const luz = g?.sinais?.luminosidade;
  let baseline = '';
  if (g) baseline = g.baseline_confiavel ? 'sim' : 'nao';
  return [
    csvText(ep.id),
    csvText(ep.crianca),
    csvText(ep.fonte),
    formatLocalDateTime(ep.inicio),
    formatLocalDateTime(ep.fim),
    csvNumber(ep.duracao_s),
    csvText(ep.encerramento ?? 'em_andamento'),
    csvText(ep.nivel_maximo),
    csvNumber(ep.probabilidade_maxima, 3),
    csvText(g?.tipo),
    csvText(g?.texto),
    baseline,
    csvText(g?.fisiologia?.sinal ?? (g ? 'nao_detectada' : '')),
    csvText(ruido?.status),
    csvNumber(ruido?.linha_de_base, 1),
    csvNumber(ruido?.valor_pico, 1),
    csvNumber(ruido?.antecedencia_s),
    csvText(luz?.status),
    csvNumber(luz?.linha_de_base),
    csvNumber(luz?.valor_pico),
    csvNumber(luz?.variacao_pct),
    csvNumber(luz?.antecedencia_s),
    csvText(ep.avaliacao_cuidador),
    csvText(ep.observacao),
  ].join(';');
}

// BOM no inicio para o Excel abrir os acentos em UTF-8.
export function episodesToCsv(episodes) {
  const lines = [CSV_COLUMNS.join(';'), ...episodes.map(csvRow)];
  return `﻿${lines.join('\r\n')}\r\n`;
}

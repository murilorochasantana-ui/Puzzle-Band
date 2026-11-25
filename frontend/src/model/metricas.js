// Metricas dos sinais por episodio (ver docs/historico.md, "Metricas por
// episodio"). Funcoes puras: quem chama e o rastreador de episodios
// (episodes.js, stepMonitor), que roda na pulseira (simulator/borda.js).
//
// Tres janelas por episodio, para cada sinal de METRIC_SIGNALS:
//   antes        os BEFORE_WINDOW_S segundos antes do inicio (media), tirados
//                da memoria de sinais do rastreador no instante em que o
//                episodio abre;
//   durante      do inicio ate o comeco dos 30 s calmos finais (media,
//                minimo e maximo), calculado leitura a leitura com somas e
//                contagens: nao depende do buffer de 300 leituras, entao vale
//                para episodios de mais de 5 min;
//   recuperacao  os 30 s calmos que encerram o episodio (media).
// Um trecho calmo que termina com outra subida (menos de 30 s) volta para o
// "durante": so o trecho calmo que fecha o episodio e "recuperacao".

export const METRIC_SIGNALS = ['bpm', 'hrv_ms', 'eda_uS', 'gyro_mag_dps', 'luz_lux', 'ruido_db'];
export const BEFORE_WINDOW_S = 120;
export const METRIC_PHASES = ['antes', 'durante', 'recuperacao'];

const round2 = (v) => Math.round(v * 100) / 100;

// Acumulador: quantas leituras entraram e, por sinal, soma, contagem,
// minimo e maximo (so valores numericos finitos contam).
export function emptyAccumulator() {
  const sinais = {};
  for (const s of METRIC_SIGNALS) sinais[s] = { soma: 0, n: 0, min: null, max: null };
  return { n: 0, sinais };
}

export function addReading(acc, reading) {
  const sinais = {};
  for (const s of METRIC_SIGNALS) {
    const cur = acc.sinais[s];
    const v = reading?.[s];
    sinais[s] = Number.isFinite(v)
      ? {
        soma: cur.soma + v,
        n: cur.n + 1,
        min: cur.min === null ? v : Math.min(cur.min, v),
        max: cur.max === null ? v : Math.max(cur.max, v),
      }
      : cur;
  }
  return { n: acc.n + 1, sinais };
}

export function mergeAccumulators(a, b) {
  if (!b.n) return a;
  if (!a.n) return b;
  const sinais = {};
  for (const s of METRIC_SIGNALS) {
    const x = a.sinais[s];
    const y = b.sinais[s];
    const mins = [x.min, y.min].filter((v) => v !== null);
    const maxs = [x.max, y.max].filter((v) => v !== null);
    sinais[s] = {
      soma: x.soma + y.soma,
      n: x.n + y.n,
      min: mins.length ? Math.min(...mins) : null,
      max: maxs.length ? Math.max(...maxs) : null,
    };
  }
  return { n: a.n + b.n, sinais };
}

export function accumulate(readings) {
  return readings.reduce(addReading, emptyAccumulator());
}

// Acumulador -> janela publicada: { n_leituras, <sinal>: { media, n[, min, max] } | null }.
// Sinal sem nenhuma leitura valida na janela = null.
export function summarizeWindow(acc, { minMax = false } = {}) {
  const out = { n_leituras: acc.n };
  for (const s of METRIC_SIGNALS) {
    const { soma, n, min, max } = acc.sinais[s];
    if (!n) {
      out[s] = null;
      continue;
    }
    out[s] = minMax
      ? { media: round2(soma / n), min: round2(min), max: round2(max), n }
      : { media: round2(soma / n), n };
  }
  return out;
}

// Janela "antes": as leituras da memoria do rastreador (entradas { t, reading })
// com t em [tStart - BEFORE_WINDOW_S, tStart). Pode ter menos de 120 (a pulseira
// acabou de ligar): o n_leituras mostra quantas entraram.
export function beforeAccumulator(history, tStart) {
  return accumulate(history
    .filter((h) => h.t < tStart && h.t >= tStart - BEFORE_WINDOW_S)
    .map((h) => h.reading));
}

// Estado das metricas de um episodio aberto: { antes, durante, calma }.
// `calma` e o trecho calmo atual (ainda pode voltar para o "durante").
export function startMetrics(history, tStart, firstReading) {
  return {
    antes: beforeAccumulator(history, tStart),
    durante: addReading(emptyAccumulator(), firstReading),
    calma: emptyAccumulator(),
  };
}

// Uma leitura nova no episodio aberto. `calm`: a leitura e de baixo_risco.
export function stepMetrics(state, reading, calm) {
  if (calm) return { ...state, calma: addReading(state.calma, reading) };
  return {
    ...state,
    durante: addReading(mergeAccumulators(state.durante, state.calma), reading),
    calma: emptyAccumulator(),
  };
}

// Campo `metricas` do episodio. Com o episodio aberto, a "recuperacao" e o
// trecho calmo em curso (parcial); num episodio interrompido, o que havia.
export function buildMetrics(state) {
  return {
    antes: summarizeWindow(state.antes),
    durante: summarizeWindow(state.durante, { minMax: true }),
    recuperacao: summarizeWindow(state.calma),
  };
}

// Validacao de um `metricas` recebido (topico historico): devolve o objeto
// limpo ou null. Episodio sem metricas (versao antiga) continua valido.
export function parseMetrics(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  const out = {};
  let any = false;
  for (const fase of METRIC_PHASES) {
    const w = raw[fase];
    if (!w || typeof w !== 'object' || Array.isArray(w)) {
      out[fase] = null;
      continue;
    }
    const janela = { n_leituras: Number.isInteger(w.n_leituras) && w.n_leituras >= 0 ? w.n_leituras : 0 };
    for (const s of METRIC_SIGNALS) {
      const v = w[s];
      if (!v || typeof v !== 'object' || num(v.media) === null) {
        janela[s] = null;
        continue;
      }
      const sinal = { media: v.media, n: Number.isInteger(v.n) && v.n >= 0 ? v.n : 0 };
      if (fase === 'durante') {
        sinal.min = num(v.min);
        sinal.max = num(v.max);
      }
      janela[s] = sinal;
    }
    out[fase] = janela;
    any = true;
  }
  return any ? out : null;
}

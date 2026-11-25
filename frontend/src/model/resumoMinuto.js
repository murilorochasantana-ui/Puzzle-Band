// Resumo de cada minuto dos sinais (ver docs/mqtt.md, "resumo_minuto").
// Funcoes puras: quem usa e a pulseira (simulator/borda.js), que publica um
// resumo por minuto fechado em puzzleband/<id>/resumo_minuto para o app
// montar o relatorio (medias do dia, por hora e a cobertura).
//
// O minuto e o da leitura (UTC, pelo timestamp dela), nao o do relogio de
// quem recebe. A pulseira guarda os resumos das ultimas 24 h na memoria, para
// reenviar ao app o que ele perdeu sem internet (o broker nao guarda: o EMQX
// Serverless expira a sessao em 2 h e a fila em 1000 mensagens).

import { addReading, emptyAccumulator, summarizeWindow } from './metricas.js';

export const MINUTE_MS = 60_000;
export const MINUTE_SUMMARY_MEMORY_MIN = 24 * 60; // 24 h de resumos na memoria

const TIER_RANK = { baixo_risco: 0, atencao: 1, alto_risco: 2 };

const minuteOf = (iso) => {
  const ms = Date.parse(iso);
  return Number.isFinite(ms) ? Math.floor(ms / MINUTE_MS) * MINUTE_MS : null;
};

// Resumo publicado de um minuto:
//   { minuto, nivel_maximo, n_leituras, bpm: { media, n } | null, hrv_ms, eda_uS, gyro_mag_dps, luz_lux, ruido_db }
function finish(current) {
  return {
    minuto: new Date(current.minuto).toISOString(),
    nivel_maximo: current.nivel,
    ...summarizeWindow(current.acc),
  };
}

// Acumula as leituras (com o nivel do modelo naquela leitura) e devolve o
// resumo do minuto que FECHOU (a primeira leitura de um minuto novo fecha o
// anterior). Leitura de um minuto anterior ao atual (fora de ordem) e ignorada.
export function createMinuteSummarizer({ memoryMinutes = MINUTE_SUMMARY_MEMORY_MIN } = {}) {
  let current = null;
  let recent = []; // resumos fechados, do mais antigo para o mais novo

  function remember(summary) {
    recent = [...recent.filter((r) => r.minuto !== summary.minuto), summary];
    const limit = Date.parse(summary.minuto) - (memoryMinutes - 1) * MINUTE_MS;
    recent = recent.filter((r) => Date.parse(r.minuto) >= limit);
    return summary;
  }

  return {
    add(reading, tier) {
      const minuto = minuteOf(reading?.timestamp);
      if (minuto === null) return null;
      let closed = null;
      if (current && minuto < current.minuto) return null;
      if (current && minuto > current.minuto) {
        closed = remember(finish(current));
        current = null;
      }
      if (!current) current = { minuto, nivel: 'baixo_risco', acc: emptyAccumulator() };
      current.acc = addReading(current.acc, reading);
      if ((TIER_RANK[tier] ?? 0) > TIER_RANK[current.nivel]) current.nivel = tier;
      return closed;
    },

    // Pulseira desligando: fecha o minuto parcial (o app substitui pelo
    // valor mais novo se ele vier de novo).
    flush() {
      if (!current) return null;
      const closed = remember(finish(current));
      current = null;
      return closed;
    },

    // Resumos fechados com minuto >= sinceMs (ms desde 1970), mais antigo primeiro.
    since(sinceMs = -Infinity) {
      return recent.filter((r) => Date.parse(r.minuto) >= sinceMs);
    },

    clear() {
      current = null;
      recent = [];
    },
  };
}

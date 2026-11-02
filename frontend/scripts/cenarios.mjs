// Teste de ponta a ponta do gatilho com o MODELO REAL: gera leituras com o
// mesmo gerador do simulador manual (src/model/simulate.js), mantem o mesmo
// buffer deslizante do App.jsx (300 leituras) e passa pelo mesmo caminho do
// dashboard: ingestReadings -> classifyAt (Random Forest) -> episodios +
// gatilho. Os "alertas" sao o que seria publicado em puzzleband/<id>/alertas.
//
// Os cenarios reproduzem os do simulador de linha de comando descritos no
// README (crise_ruido, crise_sem_gatilho) e acrescentam dois de controle.
//
//   node scripts/cenarios.mjs              # relatorio com 20 sementes por cenario
//   node scripts/cenarios.mjs --sementes 50
//
// O Math.random e trocado por um gerador com semente durante a simulacao,
// entao o resultado e reprodutivel.

import { pathToFileURL } from 'node:url';
import { generateReading } from '../src/model/simulate.js';
import { classifyAt } from '../src/model/classify.js';
import { createMonitor, ingestReadings, upsertEpisode } from '../src/model/episodes.js';

const MAX_BUFFER = 300; // mesmo limite do App.jsx

const CALM = {
  bpmTarget: 80, edaTarget: 4, hrvTarget: 55, gyroAction: 'repouso', movimentoRepetitivo: false,
  luzTarget: 300, ruidoTarget: 45, idade: 8,
};
const CRISIS = { bpmTarget: 135, edaTarget: 9, hrvTarget: 25 };

export const CALM_S = 120; // linha de base confiavel antes do cenario
const TOTAL_S = 300;
const T_PHYSIO = CALM_S + 12; // fisiologia comeca a subir
const T_RECOVER = CALM_S + 90; // tudo volta ao normal

const ramp = (t, t0, dur, from, to) => {
  if (t <= t0) return from;
  if (t >= t0 + dur) return to;
  return from + ((to - from) * (t - t0)) / dur;
};

// Alvos dos "controles" em funcao do tempo, como alguem mexendo nos sliders
function physiology(t) {
  if (t >= T_RECOVER) {
    return {
      bpmTarget: ramp(t, T_RECOVER, 15, CRISIS.bpmTarget, CALM.bpmTarget),
      edaTarget: ramp(t, T_RECOVER, 15, CRISIS.edaTarget, CALM.edaTarget),
      hrvTarget: ramp(t, T_RECOVER, 15, CRISIS.hrvTarget, CALM.hrvTarget),
    };
  }
  return {
    bpmTarget: ramp(t, T_PHYSIO, 8, CALM.bpmTarget, CRISIS.bpmTarget),
    edaTarget: ramp(t, T_PHYSIO, 8, CALM.edaTarget, CRISIS.edaTarget),
    hrvTarget: ramp(t, T_PHYSIO, 8, CALM.hrvTarget, CRISIS.hrvTarget),
  };
}

const during = (t, from, to) => t >= from && t < to;

export const SCENARIOS = {
  crise_ruido: {
    descricao: 'ruído sobe (45 → 88 dB) ~12 s antes de BPM/EDA subirem e a HRV cair',
    esperado: 'ruido',
    controls: (t) => ({ ...physiology(t), ruidoTarget: during(t, CALM_S, T_RECOVER) ? ramp(t, CALM_S, 3, 45, 88) : 45 }),
  },
  crise_sem_gatilho: {
    descricao: 'sinais fisiológicos sobem, luz e ruído ficam normais',
    esperado: 'nenhum_ambiental',
    controls: (t) => physiology(t),
  },
  crise_luz: {
    descricao: '(controle) luz sobe de 300 para 950 lux ~12 s antes da fisiologia',
    esperado: 'luminosidade',
    controls: (t) => ({ ...physiology(t), luzTarget: during(t, CALM_S, T_RECOVER) ? 950 : 300 }),
  },
  ruido_depois: {
    descricao: '(controle) ruído só sobe ~30 s DEPOIS da fisiologia (ex.: a criança gritando)',
    esperado: 'nenhum_ambiental',
    controls: (t) => ({ ...physiology(t), ruidoTarget: during(t, T_PHYSIO + 30, T_RECOVER) ? 88 : 45 }),
  },
};

// mulberry32: gerador pseudoaleatorio pequeno e com semente
function seeded(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let x = a;
    x = Math.imul(x ^ (x >>> 15), x | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}

const T0 = Date.parse('2026-11-02T13:00:00Z');

// speed: leituras por "tick", como os botoes 1x/2x/4x do simulador manual
export function runScenario(name, seed = 1, { speed = 1 } = {}) {
  const scenario = SCENARIOS[name];
  const originalRandom = Math.random;
  Math.random = seeded(seed);
  try {
    let buffer = [];
    let monitor = createMonitor({ childId: 'simulada', source: 'manual' });
    let lastReading = null;
    let episodes = [];
    const alerts = [];
    for (let t = 0; t < TOTAL_S; t += speed) {
      const next = [...buffer];
      for (let k = 0; k < speed && t + k < TOTAL_S; k += 1) {
        const ts = new Date(T0 + (t + k) * 1000).toISOString();
        next.push(generateReading({ ...CALM, ...scenario.controls(t + k), timestamp: ts }));
      }
      buffer = next.length > MAX_BUFFER ? next.slice(next.length - MAX_BUFFER) : next;

      const result = ingestReadings(monitor, lastReading, buffer, classifyAt);
      monitor = result.monitor;
      lastReading = result.lastReading;
      for (const ep of result.changed) episodes = upsertEpisode(episodes, ep);
      alerts.push(...result.alerts);
    }
    const episode = episodes[episodes.length - 1] ?? null; // o primeiro episodio do cenario
    const firstAlertT = alerts.length ? (Date.parse(alerts[0].leituras.timestamp) - T0) / 1000 : null;
    return { name, seed, esperado: scenario.esperado, episodes, episode, alerts, firstAlertT };
  } finally {
    Math.random = originalRandom;
  }
}

function report(seeds) {
  console.log(`Cenários de ponta a ponta (simulate.js + Random Forest + gatilho), ${seeds} sementes cada`);
  console.log(`Linha do tempo: ${CALM_S} s calmos -> cenário -> fisiologia sobe em t=${T_PHYSIO}s -> volta ao normal em t=${T_RECOVER}s\n`);
  let allOk = true;
  for (const [name, scenario] of Object.entries(SCENARIOS)) {
    const runs = Array.from({ length: seeds }, (_, i) => runScenario(name, i + 1));
    const hits = runs.filter((r) => r.episode?.gatilho?.tipo === scenario.esperado).length;
    const counts = {};
    for (const r of runs) {
      const key = r.episode?.gatilho?.tipo ?? 'sem_episodio';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    const nEpisodes = runs.map((r) => r.episodes.length);
    const leads = runs
      .map((r) => r.episode?.gatilho?.sinais?.[name === 'crise_luz' ? 'luminosidade' : 'ruido']?.antecedencia_s)
      .filter((v) => Number.isFinite(v));
    const example = runs[0].episode;
    allOk &&= hits === seeds;

    console.log(`${name}: ${scenario.descricao}`);
    console.log(`  esperado: ${scenario.esperado} | acertos: ${hits}/${seeds} | distribuição: ${JSON.stringify(counts)}`);
    console.log(`  episódios por execução: ${Math.min(...nEpisodes)}-${Math.max(...nEpisodes)} | 1º alerta do modelo em t=${runs[0].firstAlertT}s (semente 1)`);
    if (leads.length) console.log(`  antecedência do sinal ambiental (s): min ${Math.min(...leads)}, max ${Math.max(...leads)}`);
    if (example) {
      console.log(`  exemplo (semente 1): nível máx. ${example.nivel_maximo}, prob. máx. ${Math.round(example.probabilidade_maxima * 100)}%, duração ${example.duracao_s}s`);
      console.log(`  texto: "${example.gatilho.texto}"`);
    }
    console.log('');
  }
  return allOk;
}

const isMain = Boolean(process.argv[1]) && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  const idx = process.argv.indexOf('--sementes');
  const seeds = idx > -1 ? Number(process.argv[idx + 1]) || 20 : 20;
  process.exitCode = report(seeds) ? 0 : 1;
}

#!/usr/bin/env node
// Diagnostico do alarme falso no exercicio (docs/modelo.md, "Estudo:
// exercicio x crise"). So mede: roda o MESMO processador da pulseira
// (simulator/borda.js -> classify.js -> predict.js + forest.json) e grava,
// segundo a segundo, as leituras, a probabilidade, o nivel e as features.
//
//   node model/diagnostico_exercicio.mjs curvas <pasta>
//     cenario oficial "exercicio": roteiro nominal (--uma-vez, seed 1) e o
//     2o ciclo do laco (com variacao) das seeds 2 e 3 -> <pasta>/curva_*.csv
//   node model/diagnostico_exercicio.mjs parecido-com-dataset <pasta> [--sementes 60]
//     exercicio montado a mao com o BPM calmo e a forma da subida do dataset
//     v4 (~92 bpm, curva cosseno de 30-50 s), contra o do simulador (78 bpm,
//     rampa reta de 40 s). NAO altera o cenario oficial. -> <pasta>/parecido.json
//   node model/diagnostico_exercicio.mjs features <pasta> [--sementes 20]
//     features de todos os segundos do exercicio oficial (laco, 3 ciclos) ->
//     <pasta>/features_simulador.csv (comparacao com o dataset no Python)

import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { computeFeatures, FEATURE_HISTORY } from '../frontend/src/model/predict.js';
import { generateReading } from '../frontend/src/model/simulate.js';
import { createEdgeProcessor } from '../simulator/borda.js';
import { CALMO, calmTargets, programTicks, seeded, withRandom } from '../simulator/scenarios.js';

const T0 = Date.parse('2026-01-01T12:00:00Z');
const FEATURES = [
  'bpm_mean_long', 'bpm_slope_long', 'bpm_jerk', 'eda_mean_long', 'eda_slope_long', 'gyro_mean_long',
  'hrv_mean_long', 'hrv_slope_long', 'accel_mean_long', 'regularidade_mean_long',
];
const SINAIS = ['bpm', 'eda_uS', 'hrv_ms', 'gyro_mag_dps', 'accel_mag_g', 'regularidade', 'luz_lux', 'ruido_db'];

// Roda uma sequencia de { t, alvos, fase } e devolve uma linha por segundo
function rodar(ticks, seed) {
  return withRandom(seeded(seed), () => {
    const processor = createEdgeProcessor({ childId: 'DIAG', source: 'pulseira' });
    const linhas = [];
    for (const tick of ticks) {
      const leitura = generateReading({ ...tick.alvos, timestamp: new Date(T0 + tick.t * 1000).toISOString() });
      const r = processor.ingest(leitura);
      const buf = processor.readings();
      const f = computeFeatures(buf.slice(-FEATURE_HISTORY)) ?? {};
      linhas.push({
        t: tick.t, fase: tick.fase, ...Object.fromEntries(SINAIS.map((k) => [k, leitura[k]])),
        prob: r.probability ?? '', nivel: r.tier, episodio: processor.openEpisode() ? 1 : 0,
        alerta: r.alerts.length ? r.alerts[0].nivel : '',
        ...Object.fromEntries(FEATURES.map((k) => [k, f[k] ?? ''])),
      });
    }
    return { linhas, episodios: processor.episodes() };
  });
}

const csv = (linhas) => {
  const cols = Object.keys(linhas[0]);
  return [cols.join(','), ...linhas.map((l) => cols.map((c) => (typeof l[c] === 'string' && l[c].includes(',') ? `"${l[c]}"` : l[c])).join(','))].join('\n');
};

// --- curvas do cenario oficial ---------------------------------------------
function curvas(pasta) {
  const casos = [
    { nome: 'nominal', seed: 1, ticks: [...programTicks({ cenario: 'exercicio', umaVez: true, seed: 1 })], ciclo: 1 },
    { nome: 'seed2', seed: 2, ticks: [...programTicks({ cenario: 'exercicio', ciclos: 2, seed: 2 })], ciclo: 2 },
    { nome: 'seed3', seed: 3, ticks: [...programTicks({ cenario: 'exercicio', ciclos: 2, seed: 3 })], ciclo: 2 },
  ];
  const resumo = [];
  for (const c of casos) {
    const { linhas } = rodar(c.ticks, c.seed);
    const ciclo = c.ticks.find((t) => t.ciclo.numero === c.ciclo).ciclo;
    // recorte: 120 s antes do trecho ativo ate 120 s depois
    const ini = ciclo.tInicio - 120;
    const fim = ciclo.tFim + 120;
    const recorte = linhas.filter((l) => l.t >= ini && l.t <= fim).map((l) => ({ ...l, t_rel: l.t - ciclo.tInicio }));
    writeFileSync(join(pasta, `curva_${c.nome}.csv`), csv(recorte));
    const comProb = recorte.filter((l) => l.prob !== '');
    const pico = comProb.reduce((a, b) => (b.prob > a.prob ? b : a));
    const primeiro = recorte.find((l) => l.nivel !== 'baixo_risco');
    resumo.push({
      caso: c.nome, resumo: ciclo.roteiro.resumo.join(' · '),
      pico: { prob: pico.prob, t_rel: pico.t_rel, fase: pico.fase },
      primeiroAlerta: primeiro ? { t_rel: primeiro.t_rel, nivel: primeiro.nivel, fase: primeiro.fase } : null,
      segundosAtencao: recorte.filter((l) => l.nivel === 'atencao').length,
      segundosAlto: recorte.filter((l) => l.nivel === 'alto_risco').length,
    });
  }
  writeFileSync(join(pasta, 'curvas_resumo.json'), JSON.stringify(resumo, null, 1));
  console.log(JSON.stringify(resumo, null, 1));
}

// --- exercicio "parecido com o dataset" -----------------------------------
// envelope 0..1: base calma, sobe em `up` s (reta ou cosseno), fica `hold`,
// desce em `down` s, cauda calma
const cosseno = (x) => 0.5 - 0.5 * Math.cos(Math.PI * x);
function envelope(t, { inicio, up, hold, down, forma }) {
  const f = forma === 'cosseno' ? cosseno : (x) => x;
  if (t < inicio) return 0;
  if (t < inicio + up) return f((t - inicio) / up);
  if (t < inicio + up + hold) return 1;
  if (t < inicio + up + hold + down) return 1 - f((t - inicio - up - hold) / down);
  return 0;
}

// mesmas mudancas do cenario oficial (EXERCISE do scenarios.js: gyro +107,
// bpm +38, eda +2,6, hrv -13), so mudando o BPM calmo e a forma da subida
function exercicioMontado({ bpmCalmo, forma, up, down }) {
  const env = { inicio: 120, up, hold: 120, down, forma };
  const total = env.inicio + up + env.hold + down + 90;
  const calm = calmTargets(8);
  const ticks = [];
  for (let t = 0; t < total; t += 1) {
    const e = envelope(t, env);
    ticks.push({
      t,
      fase: e === 0 ? 'calmo' : 'exercicio',
      alvos: {
        ...calm,
        bpmTarget: bpmCalmo + 38 * e,
        edaTarget: CALMO.eda + 2.6 * e,
        hrvTarget: CALMO.hrv - 13 * e,
        gyroBase: CALMO.gyro + 107 * e,
      },
    });
  }
  return ticks;
}

function parecido(pasta, sementes) {
  const variantes = [
    { nome: 'simulador (78 bpm, reta 40 s)', bpmCalmo: 78, forma: 'reta', up: 40, down: 40 },
    { nome: '78 bpm, cosseno 40 s', bpmCalmo: 78, forma: 'cosseno', up: 40, down: 40 },
    { nome: '92 bpm, reta 40 s', bpmCalmo: 92, forma: 'reta', up: 40, down: 40 },
    { nome: '92 bpm, cosseno 30 s', bpmCalmo: 92, forma: 'cosseno', up: 30, down: 30 },
    { nome: '92 bpm, cosseno 40 s', bpmCalmo: 92, forma: 'cosseno', up: 40, down: 40 },
    { nome: '92 bpm, cosseno 50 s', bpmCalmo: 92, forma: 'cosseno', up: 50, down: 50 },
    { nome: '85 bpm, cosseno 40 s', bpmCalmo: 85, forma: 'cosseno', up: 40, down: 40 },
    { nome: '100 bpm, cosseno 40 s', bpmCalmo: 100, forma: 'cosseno', up: 40, down: 40 },
  ];
  const out = [];
  for (const v of variantes) {
    const ticks = exercicioMontado(v);
    let comEpisodio = 0;
    let comAlto = 0;
    let picos = [];
    let calmoComAlerta = 0;
    for (let s = 1; s <= sementes; s += 1) {
      const { linhas, episodios } = rodar(ticks, s);
      if (episodios.length) comEpisodio += 1;
      if (episodios.some((ep) => ep.nivel_maximo === 'alto_risco')) comAlto += 1;
      const ex = linhas.filter((l) => l.t >= 120 && l.prob !== '');
      picos.push(Math.max(...ex.map((l) => l.prob)));
      // o proprio calmo (antes do exercicio) ja alarma?
      if (linhas.some((l) => l.t < 120 && l.nivel !== 'baixo_risco')) calmoComAlerta += 1;
    }
    picos = picos.sort((a, b) => a - b);
    const r = {
      variante: v.nome, sementes, comEpisodio, comAlto, calmoComAlerta,
      picoMediano: picos[Math.floor(picos.length / 2)], picoMin: picos[0], picoMax: picos[picos.length - 1],
    };
    out.push(r);
    console.log(`${r.variante}: episodio em ${comEpisodio}/${sementes} (alto ${comAlto}), calmo com alerta ${calmoComAlerta}, `
      + `pico mediano ${r.picoMediano.toFixed(2)} (${r.picoMin.toFixed(2)}–${r.picoMax.toFixed(2)})`);
  }
  writeFileSync(join(pasta, 'parecido.json'), JSON.stringify(out, null, 1));
}

// --- features do exercicio oficial, para comparar com o dataset -----------
function features(pasta, sementes) {
  const todas = [];
  for (let s = 1; s <= sementes; s += 1) {
    const ticks = [...programTicks({ cenario: 'exercicio', ciclos: 3, seed: s })];
    const { linhas } = rodar(ticks, s);
    ticks.forEach((tick, i) => {
      const c = tick.ciclo;
      const rel = tick.t - c.tInicio;
      const r = c.roteiro;
      let trecho = 'pausa';
      if (rel >= 0 && tick.t <= c.tFim) {
        const up = r.fases[2][0] - r.fases[1][0];
        const hold = r.fases[3][0] - r.fases[2][0];
        trecho = rel < 60 ? 'inicio_60s' : rel < up + hold ? 'plato' : 'descida';
      }
      if (tick.t < c.tInicio && c.numero === 1) trecho = 'calmo';
      todas.push({ seed: s, ciclo: c.numero, trecho, ...linhas[i] });
    });
  }
  writeFileSync(join(pasta, 'features_simulador.csv'), csv(todas.filter((l) => l.prob !== '')));
  console.log(`features_simulador.csv: ${todas.length} linhas`);
}

const [modo, pasta, ...resto] = process.argv.slice(2);
const iS = resto.indexOf('--sementes');
const sementes = iS >= 0 ? Number(resto[iS + 1]) : null;
if (!modo || !pasta) {
  console.error('Uso: node model/diagnostico_exercicio.mjs curvas|parecido-com-dataset|features <pasta> [--sementes N]');
  process.exit(1);
}
mkdirSync(pasta, { recursive: true });
if (modo === 'curvas') curvas(pasta);
else if (modo === 'parecido-com-dataset') parecido(pasta, sementes ?? 60);
else if (modo === 'features') features(pasta, sementes ?? 20);
else throw new Error(`modo desconhecido: ${modo}`);

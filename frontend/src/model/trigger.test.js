// Testes da indicacao de gatilho (node:test, sem dependencias).
// Rode com: npm test   (dentro de frontend/)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { analyzeTrigger, reviewTrigger, computeEnvironmentalBaseline, TRIGGER_CONFIG } from './trigger.js';

// Ruido deterministico em (-1, 1): os testes nao podem depender de Math.random
const jitter = (t, seed) => {
  const x = Math.sin(t * 12.9898 + seed * 78.233) * 43758.5453;
  return (x - Math.floor(x)) * 2 - 1;
};

// Rampa linear de `from` para `to` comecando em t0 e durando `dur` segundos
const ramp = (t, t0, dur, from, to) => {
  if (t <= t0) return from;
  if (t >= t0 + dur) return to;
  return from + ((to - from) * (t - t0)) / dur;
};

const T0 = Date.parse('2026-11-02T13:00:00Z');

// Historico sintetico de n segundos. Cada sinal e uma funcao de t; o nivel
// do modelo (tier) e dado explicitamente, para testar so a regra do gatilho.
function buildHistory(n, { bpm = () => 80, eda = () => 4, ruido = () => 45, luz = () => 300, alertFrom = Infinity } = {}) {
  return Array.from({ length: n }, (_, t) => ({
    t,
    tier: t >= alertFrom ? 'atencao' : 'baixo_risco',
    reading: {
      timestamp: new Date(T0 + t * 1000).toISOString(),
      bpm: Math.round(bpm(t) + 2 * jitter(t, 1)),
      eda_uS: eda(t) + 0.3 * jitter(t, 2),
      ruido_db: ruido(t) + 2 * jitter(t, 3),
      luz_lux: Math.max(5, Math.round(luz(t) + 15 * jitter(t, 4))),
      hrv_ms: 55,
      gyro_mag_dps: 5,
      accel_mag_g: 2,
      regularidade: 0.1,
      idade: 8,
    },
  }));
}

// Fisiologia subindo (BPM 80 -> 130, EDA 4 -> 9) a partir de tPhysio
const physioFrom = (tPhysio) => ({
  bpm: (t) => ramp(t, tPhysio, 5, 80, 130),
  eda: (t) => ramp(t, tPhysio, 5, 4, 9),
});

test('(a) ruido sobe ANTES da fisiologia -> "ruido"', () => {
  const history = buildHistory(200, {
    ...physioFrom(152),
    ruido: (t) => ramp(t, 140, 4, 45, 88),
    alertFrom: 170,
  });
  const result = analyzeTrigger(history, 170);

  assert.equal(result.tipo, 'ruido');
  assert.equal(result.baseline_confiavel, true);
  assert.equal(result.sinais.ruido.status, 'gatilho');
  assert.equal(result.sinais.luminosidade.status, 'estavel');
  assert.ok(Math.abs(result.linha_de_base.ruido_db - 45) < 2, `linha de base ${result.linha_de_base.ruido_db}`);
  assert.ok(result.sinais.ruido.valor_pico >= 86);
  const lead = result.sinais.ruido.antecedencia_s;
  assert.ok(lead >= 8 && lead <= 14, `antecedencia ${lead}s`);
  assert.ok(result.fisiologia.detectada);
  assert.match(result.texto, /^Provável gatilho: ruído \(45 → \d+ dB, cerca de \d+ s antes da alteração fisiológica\)\.$/);
});

test('(b) luz sobe antes da fisiologia -> "luminosidade"', () => {
  const history = buildHistory(200, {
    ...physioFrom(150),
    luz: (t) => (t >= 140 ? 900 : 300),
    alertFrom: 168,
  });
  const result = analyzeTrigger(history, 168);

  assert.equal(result.tipo, 'luminosidade');
  assert.equal(result.sinais.luminosidade.status, 'gatilho');
  assert.ok(result.sinais.luminosidade.criterios.includes('aumento'));
  assert.ok(result.sinais.luminosidade.variacao_pct >= 150);
  assert.equal(result.sinais.ruido.status, 'estavel');
  const lead = result.sinais.luminosidade.antecedencia_s;
  assert.ok(lead >= 9 && lead <= 12, `antecedencia ${lead}s`);
  assert.match(result.texto, /^Provável gatilho: luminosidade \(\d+ → \d+ lux, cerca de \d+ s antes da alteração fisiológica\)\.$/);
});

test('(b2) luz piscando (sem aumento medio) -> "luminosidade" por oscilacao', () => {
  const history = buildHistory(200, {
    ...physioFrom(150),
    luz: (t) => (t >= 135 && Math.floor(t / 2) % 2 === 0 ? 80 : 300),
    alertFrom: 168,
  });
  const result = analyzeTrigger(history, 168);

  assert.equal(result.tipo, 'luminosidade');
  assert.deepEqual(result.sinais.luminosidade.criterios, ['oscilacao']);
  assert.match(result.texto, /luminosidade \(oscilando entre \d+ e \d+ lux/);
});

test('(c) nada muda no ambiente -> "nenhum_ambiental"', () => {
  const history = buildHistory(200, { ...physioFrom(150), alertFrom: 168 });
  const result = analyzeTrigger(history, 168);

  assert.equal(result.tipo, 'nenhum_ambiental');
  assert.equal(result.sinais.ruido.status, 'estavel');
  assert.equal(result.sinais.luminosidade.status, 'estavel');
  assert.equal(
    result.texto,
    'Sem gatilho ambiental aparente: luz e ruído estáveis. A causa pode ser outra (social, rotina, desconforto físico).',
  );
});

test('(d) ruido sobe so 30 s DEPOIS da fisiologia -> nao conta como gatilho', () => {
  const history = buildHistory(200, {
    ...physioFrom(150),
    ruido: (t) => ramp(t, 180, 3, 45, 90),
    alertFrom: 165,
  });
  const result = analyzeTrigger(history, 190);

  assert.equal(result.tipo, 'nenhum_ambiental');
  assert.equal(result.sinais.ruido.status, 'possivel_consequencia');
  const lead = result.sinais.ruido.antecedencia_s;
  assert.ok(lead <= -27 && lead >= -33, `antecedencia ${lead}s`);
  assert.match(result.texto, /^Sem gatilho ambiental aparente\./);
  assert.match(result.texto, /possível consequência/);
  assert.doesNotMatch(result.texto, /Provável gatilho/);
});

test('(d2) mesmo caso, detectado na reavaliacao DURANTE o episodio', () => {
  const history = buildHistory(200, {
    ...physioFrom(150),
    ruido: (t) => ramp(t, 180, 3, 45, 90),
    alertFrom: 165,
  });
  const atAlert = analyzeTrigger(history.slice(0, 166), 165);
  assert.equal(atAlert.tipo, 'nenhum_ambiental');
  assert.equal(atAlert.sinais.ruido.status, 'estavel');

  // nada mudou ainda: devolve o mesmo objeto
  assert.equal(reviewTrigger(atAlert, history.slice(0, 175)), atAlert);

  const reviewed = reviewTrigger(atAlert, history);
  assert.notEqual(reviewed, atAlert);
  assert.equal(reviewed.atualizado_durante_episodio, true);
  assert.equal(reviewed.tipo, 'nenhum_ambiental');
  assert.equal(reviewed.sinais.ruido.status, 'possivel_consequencia');
  // linha de base e inicio fisiologico ficam congelados
  assert.deepEqual(reviewed.linha_de_base, atAlert.linha_de_base);
  assert.equal(reviewed.fisiologia.t_inicio_s, atAlert.fisiologia.t_inicio_s);
});

test('(e) ambiente barulhento constante (linha de base alta) -> "nenhum_ambiental"', () => {
  const history = buildHistory(200, { ...physioFrom(150), ruido: () => 85, alertFrom: 168 });
  const result = analyzeTrigger(history, 168);

  assert.ok(result.linha_de_base.ruido_db >= 83);
  assert.equal(result.tipo, 'nenhum_ambiental');
  assert.equal(result.sinais.ruido.status, 'estavel');
});

test('ruido ate 5 s depois da fisiologia ainda conta; 8 s depois nao', () => {
  const at = (tNoise) => analyzeTrigger(
    buildHistory(200, { ...physioFrom(150), ruido: (t) => (t >= tNoise ? 90 : 45), alertFrom: 168 }),
    168,
  );
  const within = at(155);
  assert.equal(within.tipo, 'ruido');
  assert.match(within.texto, /praticamente junto com a alteração fisiológica/);

  const late = at(159);
  assert.equal(late.tipo, 'nenhum_ambiental');
  assert.equal(late.sinais.ruido.status, 'possivel_consequencia');
});

test('ruido e luz antes da fisiologia -> "ruido_e_luminosidade"', () => {
  const history = buildHistory(200, {
    ...physioFrom(150),
    ruido: (t) => (t >= 138 ? 85 : 45),
    luz: (t) => (t >= 142 ? 1200 : 300),
    alertFrom: 168,
  });
  const result = analyzeTrigger(history, 168);
  assert.equal(result.tipo, 'ruido_e_luminosidade');
  assert.match(result.texto, /^Provável gatilho: ruído \(.+\) e luminosidade \(.+\)\.$/);
});

test('sala escura com sensor oscilando (5-30 lux) nao e "luz piscando"', () => {
  const history = buildHistory(200, { ...physioFrom(150), luz: () => 10, alertFrom: 168 });
  const result = analyzeTrigger(history, 168);
  assert.equal(result.sinais.luminosidade.status, 'estavel');
  assert.equal(result.tipo, 'nenhum_ambiental');
});

test('pico isolado de 1 leitura nao conta (precisa de MIN_RUN_S leituras)', () => {
  const history = buildHistory(200, { ...physioFrom(150), ruido: (t) => (t === 140 ? 95 : 45), alertFrom: 168 });
  assert.equal(analyzeTrigger(history, 168).tipo, 'nenhum_ambiental');
});

test('pouco tempo calmo antes do alerta -> usa as primeiras leituras e baseline_confiavel = false', () => {
  const history = buildHistory(80, { ...physioFrom(42), ruido: (t) => (t >= 30 ? 88 : 45), alertFrom: 55 });
  const result = analyzeTrigger(history, 55);
  assert.equal(result.baseline_confiavel, false);
  assert.equal(result.linha_de_base.amostras, TRIGGER_CONFIG.BASELINE_FALLBACK_S);
  assert.equal(result.tipo, 'ruido');
  assert.match(result.texto, /interpretar com cautela/);
});

test('linha de base usa so leituras baixo_risco dentro de 5 min', () => {
  const history = buildHistory(400, {
    ruido: (t) => (t < 50 ? 30 : 50), // leituras antigas (fora dos 5 min) nao entram
    alertFrom: 380,
  });
  const base = computeEnvironmentalBaseline(history, 380);
  assert.equal(base.confiavel, true);
  assert.equal(base.amostras, 300);
  assert.ok(Math.abs(base.ruido_db - 50) < 1.5, `ruido ${base.ruido_db}`);
});

test('limites sao configuraveis', () => {
  const history = buildHistory(200, { ...physioFrom(152), ruido: (t) => (t >= 140 ? 55 : 45), alertFrom: 170 });
  assert.equal(analyzeTrigger(history, 170).tipo, 'nenhum_ambiental'); // +10 dB < 15 dB
  assert.equal(analyzeTrigger(history, 170, { NOISE_RISE_DB: 8 }).tipo, 'ruido');
});

test('alerta sem BPM/EDA acima da margem usa o proprio alerta como referencia', () => {
  const history = buildHistory(200, { ruido: (t) => (t >= 150 ? 90 : 45), alertFrom: 168 });
  const result = analyzeTrigger(history, 168);
  assert.equal(result.fisiologia.detectada, false);
  assert.equal(result.tipo, 'ruido');
  assert.match(result.texto, /antes do alerta do modelo/);
});

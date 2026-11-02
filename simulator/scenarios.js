// Cenarios do simulador da pulseira.
//
// Cada sinal segue uma linha do tempo de pontos [t (s), valor]: entre dois
// pontos o valor muda em RAMPA linear (transicoes graduais de 20-40 s); antes
// do primeiro ponto vale o valor calmo e depois do ultimo o valor fica
// constante - por isso o simulador pode rodar sem fim (--duracao opcional).
// `duracao` e o tempo do roteiro de cada cenario (depois disso, tudo calmo).
//
// Os cenarios isolados comecam com BASELINE_S segundos calmos: a regra de
// gatilho provavel (frontend/src/model/trigger.js) precisa de >= 60 s de
// leituras calmas ANTES da janela de analise de 60 s para a linha de base ser
// confiavel. Nos cenarios com gatilho, o sinal ambiental comeca a subir antes
// da fisiologia, de modo que o CRUZAMENTO do limite da regra fique ~12 s antes
// do inicio da alteracao fisiologica (ver T_NOISE / T_LIGHT).
//
// As intensidades seguem o gerador do dataset v4 em que o modelo foi
// treinado (model/eda/10_generate_dataset_v4.py): crise = nivel "alto"
// (BPM +38, EDA +7, HRV -30), estereotipia = nivel "moderado" com agitacao
// motora regular, exercicio = "brincadeira_ativa" (BPM +38, EDA +2,6,
// giroscopio ~112, HRV cai 0,35 ms por bpm).
//
// Resultados esperados x obtidos: node verificar.js e docs/testes.md.

// Valores calmos (os mesmos padroes do simulador manual do dashboard)
export const CALMO = {
  bpm: 78, // bpm
  eda: 4, // uS
  hrv: 55, // ms
  gyro: 5, // dps (base "repouso" de simulate.js)
  reg: 0.08, // regularidade do movimento (0-1): livre/erratico
  luz: 300, // lux
  ruido: 45, // dB
};

export const BASELINE_S = 120;
const ENV_RAMP_S = 20;
const PHYSIO_RAMP_S = 30;
const RECOVERY_RAMP_S = 40;
const PLATEAU_S = 60;
// Depois que a fisiologia volta ao normal, o modelo ainda alerta por ~20-25 s
// (janelas de 30 s) e o episodio so fecha apos 30 s seguidos em baixo risco:
// por isso os cenarios terminam com pelo menos 90 s calmos.
const CALM_TAIL_S = 90;

// ---------------------------------------------------------------------------
// Blocos
// ---------------------------------------------------------------------------

// Sobe de `from` para `to` em `up` s, fica `hold` s e volta em `down` s.
// `from` = null significa "valor calmo do sinal".
const pulse = (t0, up, hold, down, from, to) => [
  [t0, from],
  [t0 + up, to],
  [t0 + up + hold, to],
  [t0 + up + hold + down, from],
];

// Junta varios pulsos do mesmo sinal (precisam estar em ordem e sem sobreposicao)
function sequence(...parts) {
  const points = parts.flat();
  for (let i = 1; i < points.length; i += 1) {
    if (points[i][0] < points[i - 1][0]) throw new Error('scenarios.js: pulsos sobrepostos');
  }
  return points;
}

// Resposta de estresse (nivel "alto", crianca parada): BPM e EDA sobem, HRV cai.
// Comeca em t0, sobe em 30 s, fica `hold` s e volta em `down` s.
function crisis(t0, { hold = PLATEAU_S, down = RECOVERY_RAMP_S } = {}) {
  const p = (key, delta) => pulse(t0, PHYSIO_RAMP_S, hold, down, null, CALMO[key] + delta);
  return { bpm: p('bpm', 38), eda: p('eda', 7), hrv: p('hrv', -30) };
}

// Atividade (exercicio / estereotipia): o dataset usa transicoes de 30-50 s
function activity(t0, { up, hold, down }, deltas) {
  const out = {};
  for (const [key, delta] of Object.entries(deltas)) {
    out[key] = pulse(t0, up, hold, down, null, key === 'reg' ? delta : CALMO[key] + delta);
  }
  return out;
}
// "brincadeira_ativa" do dataset; regularidade fica baixa (movimento livre)
const EXERCISE = { gyro: 107, bpm: 38, eda: 2.6, hrv: -13 };
// nivel "moderado" com agitacao regular (balancar o corpo); reg = valor absoluto
const STEREOTYPY = { gyro: 65, reg: 0.8, bpm: 26, eda: 4.3, hrv: -22 };

// Sinal ambiental: sobe em `ramp` s a partir de tStart, fica ate tEnd e volta em `ramp` s
const envPulse = (tStart, tEnd, to, ramp = ENV_RAMP_S) => pulse(tStart, ramp, tEnd - tStart - ramp, ramp, null, to);

// ---------------------------------------------------------------------------
// Linha do tempo dos cenarios isolados de crise
// ---------------------------------------------------------------------------

// A fisiologia passa da margem da regra (+5 bpm / +0,5 uS) ~2-3 s depois de
// comecar a subir.
const T_PHYSIO = BASELINE_S + 17;
// Ruido 45 -> 88 dB em 20 s: passa de +15 dB ~7 s depois de comecar a subir
const T_NOISE = T_PHYSIO - 17;
// Luz 300 -> 1200 lux em 20 s: passa de +50% em ~3 s
const T_LIGHT = T_PHYSIO - 12;
const T_PEAK = T_PHYSIO + PHYSIO_RAMP_S;
const T_RECOVERY = T_PEAK + PLATEAU_S;
const T_CALM = T_RECOVERY + RECOVERY_RAMP_S;
const CRISIS_DURATION = T_CALM + CALM_TAIL_S;

function crisisPhases(envStart, envLabel) {
  return [
    [0, 'baseline (calmo)'],
    ...(envLabel ? [[envStart, envLabel]] : []),
    [T_PHYSIO, 'crise: fisiologia subindo'],
    [T_PEAK, 'crise'],
    [T_RECOVERY, 'recuperação'],
    [T_CALM, 'calmo (recuperado)'],
  ];
}

// Atividade isolada: sobe em 40 s, fica 120 s, volta em 40 s
const ACT = { up: 40, hold: 120, down: 40 };
const T_ACT = BASELINE_S;
const T_ACT_PEAK = T_ACT + ACT.up;
const T_ACT_DOWN = T_ACT_PEAK + ACT.hold;
const T_ACT_CALM = T_ACT_DOWN + ACT.down;

// ruido_depois_da_crise: o ruido comeca a subir 25 s depois da fisiologia e
// cruza o limite (+15 dB) ~30 s depois do inicio da alteracao fisiologica
const T_SCREAM = T_PHYSIO + 25;

// crise_e_recuperacao: crise de ~2 min (30 s subindo + 90 s no pico)
const LONG_HOLD_S = 90;
const T_LONG_RECOVERY = T_PHYSIO + PHYSIO_RAMP_S + LONG_HOLD_S;
const T_LONG_CALM = T_LONG_RECOVERY + RECOVERY_RAMP_S;

// barulho_sem_crise: ambiente sobe em 30 s, fica 3 min, volta em 30 s
const NOISY = { up: 30, hold: 180 };
const T_NOISY_END = BASELINE_S + NOISY.up + NOISY.hold;

// ---------------------------------------------------------------------------
// demo: sequencia continua para a apresentacao (630 s = 10,5 min)
// ---------------------------------------------------------------------------

// Rampa de recuperacao mais curta (25 s) que nos cenarios isolados: com 90 s
// de recuperacao, o episodio da 1a crise precisa fechar (modelo volta ao
// baixo risco ~22 s depois da rampa + 30 s de confirmacao) antes da 2a crise.
const DEMO_RECOVERY_RAMP_S = 25;
export const DEMO_SEGMENTS = [
  { nome: 'calmo', inicio: 0, fim: 60 },
  { nome: 'exercício', inicio: 60, fim: 150 },
  { nome: 'calmo', inicio: 150, fim: 210 },
  { nome: 'crise com ruído', inicio: 210, fim: 330, gatilho: 'ruido' },
  { nome: 'recuperação', inicio: 330, fim: 420 },
  { nome: 'crise sem gatilho', inicio: 420, fim: 540, gatilho: 'nenhum_ambiental' },
  { nome: 'recuperação', inicio: 540, fim: 630 },
];
const DEMO_DURATION = 630;
const [, demoEx, , demoC1, demoR1, demoC2, demoR2] = DEMO_SEGMENTS;
const DEMO_EXERCISE = activity(demoEx.inicio, { up: 30, hold: 30, down: 30 }, EXERCISE);
// crise 1: ruido sobe no inicio do trecho; fisiologia 17 s depois (como em crise_ruido)
const demoPhysio1 = demoC1.inicio + 17;
const DEMO_CRISIS_1 = crisis(demoPhysio1, {
  hold: demoC1.fim - demoPhysio1 - PHYSIO_RAMP_S,
  down: DEMO_RECOVERY_RAMP_S,
});
const DEMO_CRISIS_2 = crisis(demoC2.inicio, {
  hold: demoC2.fim - demoC2.inicio - PHYSIO_RAMP_S,
  down: DEMO_RECOVERY_RAMP_S,
});

function demoPhases() {
  const n = DEMO_SEGMENTS.length;
  const label = (i, text) => `demo ${i}/${n} · ${text}`;
  return [
    [0, label(1, 'calmo')],
    [demoEx.inicio, label(2, 'exercício (acelerando)')],
    [demoEx.inicio + 30, label(2, 'exercício')],
    [demoEx.inicio + 60, label(2, 'exercício (desacelerando)')],
    [demoEx.fim, label(3, 'calmo')],
    [demoC1.inicio, label(4, 'crise com ruído: ruído subindo')],
    [demoPhysio1, label(4, 'crise com ruído: fisiologia subindo')],
    [demoPhysio1 + PHYSIO_RAMP_S, label(4, 'crise com ruído')],
    [demoR1.inicio, label(5, 'recuperação')],
    [demoC2.inicio, label(6, 'crise sem gatilho: fisiologia subindo')],
    [demoC2.inicio + PHYSIO_RAMP_S, label(6, 'crise sem gatilho')],
    [demoR2.inicio, label(7, 'recuperação')],
    [DEMO_DURATION, 'demo encerrada (calmo)'],
  ];
}

// ---------------------------------------------------------------------------
// Cenarios
// ---------------------------------------------------------------------------

export const SCENARIOS = {
  calmo: {
    descricao: 'Repouso: todos os sinais estáveis',
    duracao: 300,
    canais: {},
    fases: [[0, 'calmo']],
  },
  exercicio: {
    descricao: 'Atividade física: BPM, EDA e movimento sobem juntos, movimento irregular',
    duracao: T_ACT_CALM + CALM_TAIL_S,
    canais: activity(T_ACT, ACT, EXERCISE),
    fases: [
      [0, 'baseline (calmo)'],
      [T_ACT, 'começando a correr'],
      [T_ACT_PEAK, 'exercício (correndo/brincando)'],
      [T_ACT_DOWN, 'desacelerando'],
      [T_ACT_CALM, 'calmo (recuperado)'],
    ],
  },
  estereotipia: {
    descricao: 'Movimento repetitivo e regular (balançar o corpo) com sinais de estresse; ambiente estável',
    duracao: T_ACT_CALM + CALM_TAIL_S,
    canais: activity(T_ACT, ACT, STEREOTYPY),
    fases: [
      [0, 'baseline (calmo)'],
      [T_ACT, 'movimento repetitivo começando'],
      [T_ACT_PEAK, 'estereotipia'],
      [T_ACT_DOWN, 'acalmando'],
      [T_ACT_CALM, 'calmo (recuperado)'],
    ],
  },
  crise_ruido: {
    descricao: 'Ruído sobe (45 → 88 dB) ~12 s antes da fisiologia; depois BPM e EDA sobem e a HRV cai',
    duracao: CRISIS_DURATION,
    canais: { ruido: envPulse(T_NOISE, T_RECOVERY, 88), ...crisis(T_PHYSIO) },
    fases: crisisPhases(T_NOISE, 'ruído subindo'),
  },
  crise_luz: {
    descricao: 'Luz sobe forte (300 → 1200 lux, ex.: ginásio ou sol) ~12 s antes da fisiologia',
    duracao: CRISIS_DURATION,
    canais: { luz: envPulse(T_LIGHT, T_RECOVERY, 1200), ...crisis(T_PHYSIO) },
    fases: crisisPhases(T_LIGHT, 'luz subindo'),
  },
  crise_sem_gatilho: {
    descricao: 'A fisiologia sobe; luz e ruído ficam na linha de base',
    duracao: CRISIS_DURATION,
    canais: crisis(T_PHYSIO),
    fases: crisisPhases(null, null),
  },
  crise_ruido_e_luz: {
    descricao: 'Ruído (→ 88 dB) e luz (→ 1200 lux) sobem juntos ~12 s antes da fisiologia',
    duracao: CRISIS_DURATION,
    canais: {
      ruido: envPulse(T_NOISE, T_RECOVERY, 88),
      luz: envPulse(T_LIGHT, T_RECOVERY, 1200),
      ...crisis(T_PHYSIO),
    },
    fases: crisisPhases(T_NOISE, 'ruído e luz subindo'),
  },
  barulho_sem_crise: {
    descricao: 'Ruído alto (~85 dB) e luz forte (~1200 lux) por 3 min, mas a criança continua calma',
    duracao: T_NOISY_END + NOISY.up + CALM_TAIL_S,
    canais: {
      ruido: envPulse(BASELINE_S, T_NOISY_END, 85, NOISY.up),
      luz: envPulse(BASELINE_S, T_NOISY_END, 1200, NOISY.up),
    },
    fases: [
      [0, 'baseline (calmo)'],
      [BASELINE_S, 'ambiente ficando barulhento e claro'],
      [BASELINE_S + NOISY.up, 'barulho e luz forte, criança calma'],
      [T_NOISY_END, 'ambiente normalizando'],
      [T_NOISY_END + NOISY.up, 'calmo'],
    ],
  },
  ruido_depois_da_crise: {
    descricao: 'A fisiologia sobe primeiro; o ruído só sobe ~30 s depois (criança gritando)',
    duracao: CRISIS_DURATION,
    canais: { ruido: envPulse(T_SCREAM, T_RECOVERY, 88), ...crisis(T_PHYSIO) },
    fases: [
      [0, 'baseline (calmo)'],
      [T_PHYSIO, 'crise: fisiologia subindo'],
      [T_SCREAM, 'crise: criança gritando (ruído subindo)'],
      [T_SCREAM + ENV_RAMP_S, 'crise (com gritos)'],
      [T_RECOVERY, 'recuperação'],
      [T_CALM, 'calmo (recuperado)'],
    ],
  },
  crise_e_recuperacao: {
    descricao: 'Calmo → crise com ruído (~2 min) → volta gradual e ≥ 90 s calmo (episódio fecha)',
    duracao: T_LONG_CALM + 120,
    canais: {
      ruido: envPulse(T_NOISE, T_LONG_RECOVERY, 88),
      ...crisis(T_PHYSIO, { hold: LONG_HOLD_S }),
    },
    fases: [
      [0, 'baseline (calmo)'],
      [T_NOISE, 'ruído subindo'],
      [T_PHYSIO, 'crise: fisiologia subindo'],
      [T_PHYSIO + PHYSIO_RAMP_S, 'crise (~2 min)'],
      [T_LONG_RECOVERY, 'recuperação gradual'],
      [T_LONG_CALM, 'calmo (episódio fecha após 30 s em baixo risco)'],
    ],
  },
  demo: {
    descricao: 'Apresentação (10,5 min): calmo → exercício → calmo → crise com ruído → recuperação → crise sem gatilho → recuperação',
    duracao: DEMO_DURATION,
    canais: {
      gyro: DEMO_EXERCISE.gyro,
      bpm: sequence(DEMO_EXERCISE.bpm, DEMO_CRISIS_1.bpm, DEMO_CRISIS_2.bpm),
      eda: sequence(DEMO_EXERCISE.eda, DEMO_CRISIS_1.eda, DEMO_CRISIS_2.eda),
      hrv: sequence(DEMO_EXERCISE.hrv, DEMO_CRISIS_1.hrv, DEMO_CRISIS_2.hrv),
      ruido: envPulse(demoC1.inicio, demoR1.inicio, 88),
    },
    fases: demoPhases(),
  },
};

export const SCENARIO_NAMES = Object.keys(SCENARIOS);

// Valor de um sinal no instante t (rampa linear entre os pontos). Um ponto
// com valor null vale o valor calmo do sinal.
function valueAt(points, t, calmValue) {
  if (!points?.length) return calmValue;
  const v = (i) => points[i][1] ?? calmValue;
  if (t <= points[0][0]) return v(0);
  for (let i = 1; i < points.length; i += 1) {
    const [t1] = points[i];
    if (t <= t1) {
      const [t0] = points[i - 1];
      return t1 === t0 ? v(i) : v(i - 1) + ((v(i) - v(i - 1)) * (t - t0)) / (t1 - t0);
    }
  }
  return v(points.length - 1);
}

function phaseAt(phases, t) {
  let name = phases[0][1];
  for (const [start, label] of phases) if (t >= start) name = label;
  return name;
}

// Alvos para generateReading() de frontend/src/model/simulate.js no instante
// t (segundos desde o inicio do cenario) + nome da fase atual.
export function scenarioAt(name, t, { idade = 8 } = {}) {
  const scenario = SCENARIOS[name];
  if (!scenario) throw new Error(`Cenário desconhecido: ${name}`);
  const ch = (key) => valueAt(scenario.canais[key], t, CALMO[key]);
  return {
    alvos: {
      bpmTarget: ch('bpm'),
      edaTarget: ch('eda'),
      hrvTarget: ch('hrv'),
      gyroBase: ch('gyro'), // sobrescritas numericas previstas em simulate.js
      regularidadeBase: ch('reg'),
      luzTarget: ch('luz'),
      ruidoTarget: ch('ruido'),
      idade,
      gyroAction: 'repouso',
      movimentoRepetitivo: false,
    },
    fase: phaseAt(scenario.fases, t),
  };
}

// "0 s baseline (calmo) → 120 s ruído subindo → ..."
export function describeTimeline(name) {
  return SCENARIOS[name].fases.map(([t, label]) => `${t} s ${label}`).join(' → ');
}

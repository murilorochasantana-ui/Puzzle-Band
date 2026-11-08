// Cenarios do simulador da pulseira.
//
// Cada sinal segue uma linha do tempo de pontos [t (s), valor]: entre dois
// pontos o valor muda em RAMPA linear (transicoes graduais de 20-40 s); antes
// do primeiro ponto vale o valor calmo e depois do ultimo o valor fica
// constante.
//
// Cada cenario e uma funcao construir(v) da VARIACAO do ciclo `v`
// (intensidade do pico, duracao das fases, antecedencia do sinal ambiental).
// Com VARIACAO_NOMINAL ela devolve o roteiro original: o 1o ciclo do loop, o
// --uma-vez e o que as tabelas do docs/testes.md descrevem. programTicks(),
// no fim do arquivo, encadeia os ciclos em LOOP com uma pausa calma entre
// eles e monta o cenario eventos_aleatorios com os mesmos roteiros.
//
// Os cenarios isolados comecam com BASELINE_S segundos calmos: a regra de
// gatilho provavel (frontend/src/model/trigger.js) precisa de >= 60 s de
// leituras calmas ANTES da janela de analise de 60 s para a linha de base ser
// confiavel. Nos cenarios com gatilho, o sinal ambiental comeca a subir antes
// da fisiologia, de modo que o CRUZAMENTO do limite da regra fique ~12 s
// (8-15 s com variacao) antes do inicio da alteracao fisiologica.
//
// As intensidades seguem o gerador do dataset v4 em que o modelo foi
// treinado (model/gerar_dataset_v4.py): crise = nivel "alto"
// (BPM +38, EDA +7, HRV -30), estereotipia = nivel "moderado" com agitacao
// motora regular, exercicio = "brincadeira_ativa" (BPM +38, EDA +2,6,
// giroscopio ~112, HRV cai 0,35 ms por bpm).
//
// Resultados esperados x obtidos: node verificar.js e docs/testes.md.

// So leitura de um limite da regra (nao altera o trigger.js)
import { BASELINE_WINDOW_S } from '../frontend/src/model/trigger.js';

// Valores calmos (os mesmos de CALM_CONTROL, o estado calmo do modo controle)
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
// por isso os roteiros terminam com pelo menos 90 s calmos (e a pausa entre
// ciclos tem no minimo PAUSA_MIN_S).
const CALM_TAIL_S = 90;

// Antecedencia nominal (s) entre o sinal ambiental cruzar o limite da regra e
// o inicio da alteracao fisiologica. O ruido (45 -> 88 dB em 20 s) leva ~7 s
// para passar de +15 dB e a luz (300 -> 1200 lux) ~3 s para passar de +50%;
// a fisiologia passa da margem (+5 bpm / +0,5 uS) ~2-3 s depois de comecar a
// subir. Por isso o ruido comeca LEAD_S + 5 s antes da fisiologia e a luz,
// LEAD_S s antes.
const LEAD_S = 12;
const NOISE_EXTRA_LEAD_S = 5;

// Mudanca no pico, somada ao valor calmo
const CRISIS = { bpm: 38, eda: 7, hrv: -30 }; // nivel "alto" do dataset v4
const NOISE_RISE_DB = 43; // 45 -> 88 dB
const LIGHT_RISE_LUX = 900; // 300 -> 1200 lux
const NOISY_RISE_DB = 40; // barulho_sem_crise: 45 -> 85 dB
// Sinais da resposta de estresse (o nivel leve/moderada/alta so mexe nestes)
const STRESS_KEYS = new Set(['bpm', 'eda', 'hrv']);

const round2 = (x) => Math.round(x * 100) / 100;
const fmt = (x) => x.toFixed(2).replace('.', ',');

// ---------------------------------------------------------------------------
// Variacao entre ciclos
// ---------------------------------------------------------------------------

// pico          multiplica a mudanca de BPM/EDA/HRV (e do movimento, nas atividades)
// ambiente      multiplica a mudanca de luz/ruido
// nivel         intensidade da crise (eventos_aleatorios: leve/moderada/alta);
//               multiplica so a resposta de estresse (BPM, EDA, HRV)
// subida, plato, descida   multiplicam a duracao dessas fases
// antecedencia  s entre o ambiente cruzar o limite e a fisiologia comecar a mudar
export const VARIACAO_NOMINAL = Object.freeze({
  pico: 1, ambiente: 1, nivel: 1, subida: 1, plato: 1, descida: 1, antecedencia: LEAD_S,
});

// Limites do sorteio (cada cenario pode restringir com `limites`)
export const VARIACAO_LIMITES = Object.freeze({
  pico: [0.85, 1.15], // +-15%
  ambiente: [0.85, 1.15],
  duracao: [0.8, 1.2], // +-20% em cada fase
  antecedencia: [8, 15], // s (inteiro)
});

export function drawVariation(rng, limits = {}) {
  const lim = { ...VARIACAO_LIMITES, ...limits };
  const between = ([lo, hi]) => round2(lo + (hi - lo) * rng());
  const [aMin, aMax] = lim.antecedencia;
  return {
    pico: between(lim.pico),
    ambiente: between(lim.ambiente),
    nivel: 1,
    subida: between(lim.subida ?? lim.duracao),
    plato: between(lim.plato ?? lim.duracao),
    descida: between(lim.descida ?? lim.duracao),
    antecedencia: aMin + Math.floor(rng() * (aMax - aMin + 1)),
  };
}

// Duracao de uma fase com o fator sorteado para ela
const scaled = (v, key, base) => Math.max(1, Math.round(base * v[key]));

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

// Resposta de estresse (crianca parada): BPM e EDA sobem, HRV cai. Comeca em
// t0, sobe em `up` s, fica `hold` s e volta em `down` s.
function crisis(t0, v, { up = PHYSIO_RAMP_S, hold = PLATEAU_S, down = RECOVERY_RAMP_S } = {}) {
  const k = v.pico * v.nivel;
  const p = (key) => pulse(t0, up, hold, down, null, round2(CALMO[key] + CRISIS[key] * k));
  return { bpm: p('bpm'), eda: p('eda'), hrv: p('hrv') };
}

// Atividade (exercicio / estereotipia): o dataset usa transicoes de 30-50 s
function activity(t0, { up, hold, down }, deltas, v) {
  const out = {};
  for (const [key, delta] of Object.entries(deltas)) {
    const k = v.pico * (STRESS_KEYS.has(key) ? v.nivel : 1);
    out[key] = pulse(t0, up, hold, down, null, key === 'reg' ? delta : round2(CALMO[key] + delta * k));
  }
  return out;
}
// "brincadeira_ativa" do dataset; regularidade fica baixa (movimento livre)
const EXERCISE = { gyro: 107, bpm: 38, eda: 2.6, hrv: -13 };
// nivel "moderado" com agitacao regular (balancar o corpo); reg = valor absoluto
const STEREOTYPY = { gyro: 65, reg: 0.8, bpm: 26, eda: 4.3, hrv: -22 };

// Sinal ambiental: sobe em `ramp` s a partir de tStart, fica ate tEnd e volta em `ramp` s
const envPulse = (tStart, tEnd, to, ramp = ENV_RAMP_S) => pulse(tStart, ramp, tEnd - tStart - ramp, ramp, null, to);
const noiseTo = (v, rise = NOISE_RISE_DB) => round2(CALMO.ruido + rise * v.ambiente);
const lightTo = (v) => Math.round(CALMO.luz + LIGHT_RISE_LUX * v.ambiente);

const peakSummary = (v) => `pico ×${fmt(v.pico * v.nivel)}`;
const envSummary = (v) => [`ambiente ×${fmt(v.ambiente)}`, `antecedência ~${v.antecedencia} s`];

// ---------------------------------------------------------------------------
// Linha do tempo dos cenarios isolados de crise
// ---------------------------------------------------------------------------

// Com a antecedencia nominal, o ruido comeca exatamente no fim da linha de
// base (120 s), a luz em 125 s e a fisiologia em 137 s.
const T_PHYSIO = BASELINE_S + LEAD_S + NOISE_EXTRA_LEAD_S;

function crisisTimeline(v, holdBase = PLATEAU_S) {
  const up = scaled(v, 'subida', PHYSIO_RAMP_S);
  const hold = scaled(v, 'plato', holdBase);
  const down = scaled(v, 'descida', RECOVERY_RAMP_S);
  const tPhysio = T_PHYSIO;
  const tPeak = tPhysio + up;
  const tRecovery = tPeak + hold;
  return {
    up,
    hold,
    down,
    tPhysio,
    tPeak,
    tRecovery,
    tCalm: tRecovery + down,
    tNoise: tPhysio - v.antecedencia - NOISE_EXTRA_LEAD_S,
    tLight: tPhysio - v.antecedencia,
  };
}

const crisisSummary = (v, tl) => [peakSummary(v), `subida ${tl.up} s`, `platô ${tl.hold} s`, `descida ${tl.down} s`];

function crisisPhases(tl, envStart, envLabel) {
  return [
    [0, 'baseline (calmo)'],
    ...(envLabel ? [[envStart, envLabel]] : []),
    [tl.tPhysio, 'crise: fisiologia subindo'],
    [tl.tPeak, 'crise'],
    [tl.tRecovery, 'recuperação'],
    [tl.tCalm, 'calmo (recuperado)'],
  ];
}

// Roteiro de uma crise isolada com (ou sem) ruido e/ou luz subindo antes
function crisisScenario(v, { ruido = false, luz = false, envLabel = null } = {}) {
  const tl = crisisTimeline(v);
  const canais = { ...crisis(tl.tPhysio, v, tl) };
  if (ruido) canais.ruido = envPulse(tl.tNoise, tl.tRecovery, noiseTo(v));
  if (luz) canais.luz = envPulse(tl.tLight, tl.tRecovery, lightTo(v));
  const envStart = ruido ? tl.tNoise : tl.tLight;
  return {
    duracao: tl.tCalm + CALM_TAIL_S,
    canais,
    fases: crisisPhases(tl, envStart, envLabel),
    tFisiologia: tl.tPhysio,
    antecedencia: ruido || luz ? v.antecedencia : null,
    resumo: [...crisisSummary(v, tl), ...(ruido || luz ? envSummary(v) : [])],
  };
}

// Atividade isolada: sobe em 40 s, fica 120 s, volta em 40 s
const ACT = { up: 40, hold: 120, down: 40 };

function activityScenario(v, deltas, labels) {
  const a = { up: scaled(v, 'subida', ACT.up), hold: scaled(v, 'plato', ACT.hold), down: scaled(v, 'descida', ACT.down) };
  const tStart = BASELINE_S;
  const tPeak = tStart + a.up;
  const tDown = tPeak + a.hold;
  const tCalm = tDown + a.down;
  return {
    duracao: tCalm + CALM_TAIL_S,
    canais: activity(tStart, a, deltas, v),
    fases: [
      [0, 'baseline (calmo)'],
      [tStart, labels[0]],
      [tPeak, labels[1]],
      [tDown, labels[2]],
      [tCalm, 'calmo (recuperado)'],
    ],
    tFisiologia: tStart,
    antecedencia: null,
    resumo: [peakSummary(v), `subida ${a.up} s`, `platô ${a.hold} s`, `descida ${a.down} s`],
  };
}

// ---------------------------------------------------------------------------
// demo: sequencia continua para a apresentacao (630 s = 10,5 min no roteiro nominal)
// ---------------------------------------------------------------------------

// Rampa de recuperacao mais curta (25 s) que nos cenarios isolados: com 90 s
// de recuperacao, o episodio da 1a crise precisa fechar (modelo volta ao
// baixo risco ~22 s depois da rampa + 30 s de confirmacao) antes da 2a crise.
// Por isso a variacao nao mexe nela nem nos trechos de recuperacao (90 s).
const DEMO_RECOVERY_RAMP_S = 25;
const DEMO_CALM_S = 60;
const DEMO_RECOVERY_S = 90;
const DEMO_EXERCISE_S = 30; // subida, platô e descida do exercicio
const DEMO_HOLD_1_S = 73; // crise 1: 210-330 s (ruido 17 s antes + 30 s subindo + 73 s)
const DEMO_HOLD_2_S = 90; // crise 2: 420-540 s (30 s subindo + 90 s)

function demoScenario(v) {
  const ex = { up: scaled(v, 'subida', DEMO_EXERCISE_S), hold: scaled(v, 'plato', DEMO_EXERCISE_S), down: scaled(v, 'descida', DEMO_EXERCISE_S) };
  const up = scaled(v, 'subida', PHYSIO_RAMP_S);
  const hold1 = scaled(v, 'plato', DEMO_HOLD_1_S);
  const hold2 = scaled(v, 'plato', DEMO_HOLD_2_S);
  const lead = v.antecedencia + NOISE_EXTRA_LEAD_S; // ruido -> fisiologia (nominal 17 s)

  const segmentos = [];
  let t = 0;
  const seg = (nome, length, extra = {}) => {
    segmentos.push({ nome, inicio: t, fim: t + length, ...extra });
    t += length;
    return segmentos[segmentos.length - 1];
  };
  seg('calmo', DEMO_CALM_S);
  const sEx = seg('exercício', ex.up + ex.hold + ex.down);
  seg('calmo', DEMO_CALM_S);
  const c1 = seg('crise com ruído', lead + up + hold1, { gatilho: 'ruido' });
  const r1 = seg('recuperação', DEMO_RECOVERY_S);
  const c2 = seg('crise sem gatilho', up + hold2, { gatilho: 'nenhum_ambiental' });
  const r2 = seg('recuperação', DEMO_RECOVERY_S);

  const exercise = activity(sEx.inicio, ex, EXERCISE, v);
  const physio1 = c1.inicio + lead;
  const crisis1 = crisis(physio1, v, { up, hold: hold1, down: DEMO_RECOVERY_RAMP_S });
  const crisis2 = crisis(c2.inicio, v, { up, hold: hold2, down: DEMO_RECOVERY_RAMP_S });

  const n = segmentos.length;
  const label = (i, text) => `demo ${i}/${n} · ${text}`;
  return {
    duracao: r2.fim,
    canais: {
      gyro: exercise.gyro,
      bpm: sequence(exercise.bpm, crisis1.bpm, crisis2.bpm),
      eda: sequence(exercise.eda, crisis1.eda, crisis2.eda),
      hrv: sequence(exercise.hrv, crisis1.hrv, crisis2.hrv),
      ruido: envPulse(c1.inicio, r1.inicio, noiseTo(v)),
    },
    fases: [
      [0, label(1, 'calmo')],
      [sEx.inicio, label(2, 'exercício (acelerando)')],
      [sEx.inicio + ex.up, label(2, 'exercício')],
      [sEx.inicio + ex.up + ex.hold, label(2, 'exercício (desacelerando)')],
      [sEx.fim, label(3, 'calmo')],
      [c1.inicio, label(4, 'crise com ruído: ruído subindo')],
      [physio1, label(4, 'crise com ruído: fisiologia subindo')],
      [physio1 + up, label(4, 'crise com ruído')],
      [r1.inicio, label(5, 'recuperação')],
      [c2.inicio, label(6, 'crise sem gatilho: fisiologia subindo')],
      [c2.inicio + up, label(6, 'crise sem gatilho')],
      [r2.inicio, label(7, 'recuperação')],
      [r2.fim, 'demo encerrada (calmo)'],
    ],
    segmentos,
    tFisiologia: null, // duas crises: ver `segmentos`
    antecedencia: v.antecedencia,
    resumo: [peakSummary(v), `exercício ${ex.up}/${ex.hold}/${ex.down} s`, `crises: subida ${up} s, platô ${hold1} e ${hold2} s`, ...envSummary(v)],
  };
}

// ---------------------------------------------------------------------------
// Cenarios
// ---------------------------------------------------------------------------

// esperado.crise   ha crise real? (gabarito: crise_real)
// esperado.gatilho gatilho que a regra deve indicar (null = nao deve haver episodio)
export const SCENARIOS = {
  calmo: {
    descricao: 'Repouso: todos os sinais estáveis',
    esperado: { crise: false, gatilho: null },
    construir: () => ({ duracao: 300, canais: {}, fases: [[0, 'calmo']], tFisiologia: null, antecedencia: null, resumo: ['tudo calmo'] }),
  },
  exercicio: {
    descricao: 'Atividade física: BPM, EDA e movimento sobem juntos, movimento irregular',
    esperado: { crise: false, gatilho: null },
    construir: (v) => activityScenario(v, EXERCISE, ['começando a correr', 'exercício (correndo/brincando)', 'desacelerando']),
  },
  estereotipia: {
    descricao: 'Movimento repetitivo e regular (balançar o corpo) com sinais de estresse; ambiente estável',
    esperado: { crise: true, gatilho: 'nenhum_ambiental' },
    construir: (v) => activityScenario(v, STEREOTYPY, ['movimento repetitivo começando', 'estereotipia', 'acalmando']),
  },
  crise_ruido: {
    descricao: 'Ruído sobe (45 → 88 dB) ~12 s antes da fisiologia; depois BPM e EDA sobem e a HRV cai',
    esperado: { crise: true, gatilho: 'ruido' },
    construir: (v) => crisisScenario(v, { ruido: true, envLabel: 'ruído subindo' }),
  },
  crise_luz: {
    descricao: 'Luz sobe forte (300 → 1200 lux, ex.: ginásio ou sol) ~12 s antes da fisiologia',
    esperado: { crise: true, gatilho: 'luminosidade' },
    construir: (v) => crisisScenario(v, { luz: true, envLabel: 'luz subindo' }),
  },
  crise_sem_gatilho: {
    descricao: 'A fisiologia sobe; luz e ruído ficam na linha de base',
    esperado: { crise: true, gatilho: 'nenhum_ambiental' },
    construir: (v) => crisisScenario(v),
  },
  crise_ruido_e_luz: {
    descricao: 'Ruído (→ 88 dB) e luz (→ 1200 lux) sobem juntos ~12 s antes da fisiologia',
    esperado: { crise: true, gatilho: 'ruido_e_luminosidade' },
    construir: (v) => crisisScenario(v, { ruido: true, luz: true, envLabel: 'ruído e luz subindo' }),
  },
  barulho_sem_crise: {
    descricao: 'Ruído alto (~85 dB) e luz forte (~1200 lux) por 3 min, mas a criança continua calma',
    esperado: { crise: false, gatilho: null },
    // Com a crianca calma, o modelo fica em baixo_risco e essas leituras
    // barulhentas ENTRAM na linha de base de 5 min do trigger.js (mediana das
    // leituras calmas). Com 120-240 s de pausa, uma crise com ruido logo depois
    // nao via o ruido subir (linha de base ainda em ~85 dB). A pausa depois
    // deste roteiro dura pelo menos a janela da linha de base.
    pausaMinima: BASELINE_WINDOW_S,
    construir(v) {
      // ambiente sobe em 30 s, fica 3 min, volta em 30 s
      const up = scaled(v, 'subida', 30);
      const hold = scaled(v, 'plato', 180);
      const down = scaled(v, 'descida', 30);
      const tEnd = BASELINE_S + up + hold;
      return {
        duracao: tEnd + down + CALM_TAIL_S,
        canais: {
          ruido: pulse(BASELINE_S, up, hold, down, null, noiseTo(v, NOISY_RISE_DB)),
          luz: pulse(BASELINE_S, up, hold, down, null, lightTo(v)),
        },
        fases: [
          [0, 'baseline (calmo)'],
          [BASELINE_S, 'ambiente ficando barulhento e claro'],
          [BASELINE_S + up, 'barulho e luz forte, criança calma'],
          [tEnd, 'ambiente normalizando'],
          [tEnd + down, 'calmo'],
        ],
        tFisiologia: null,
        antecedencia: null,
        resumo: [`ambiente ×${fmt(v.ambiente)}`, `subida ${up} s`, `platô ${hold} s`, `descida ${down} s`],
      };
    },
  },
  ruido_depois_da_crise: {
    descricao: 'A fisiologia sobe primeiro; o ruído só sobe ~30 s depois (criança gritando)',
    esperado: { crise: true, gatilho: 'nenhum_ambiental' },
    construir(v) {
      // o ruido comeca a subir 25 s (+-20%) depois da fisiologia e cruza o
      // limite (+15 dB) ~30 s depois do inicio da alteracao fisiologica
      const tl = crisisTimeline(v);
      const tScream = tl.tPhysio + scaled(v, 'subida', 25);
      return {
        duracao: tl.tCalm + CALM_TAIL_S,
        canais: { ruido: envPulse(tScream, tl.tRecovery, noiseTo(v)), ...crisis(tl.tPhysio, v, tl) },
        fases: [
          [0, 'baseline (calmo)'],
          [tl.tPhysio, 'crise: fisiologia subindo'],
          [tScream, 'crise: criança gritando (ruído subindo)'],
          [tScream + ENV_RAMP_S, 'crise (com gritos)'],
          [tl.tRecovery, 'recuperação'],
          [tl.tCalm, 'calmo (recuperado)'],
        ],
        tFisiologia: tl.tPhysio,
        antecedencia: null,
        resumo: [...crisisSummary(v, tl), `gritos ${tScream - tl.tPhysio} s depois`, `ambiente ×${fmt(v.ambiente)}`],
      };
    },
  },
  crise_e_recuperacao: {
    descricao: 'Calmo → crise com ruído (~2 min) → volta gradual e ≥ 90 s calmo (episódio fecha)',
    esperado: { crise: true, gatilho: 'ruido' },
    construir(v) {
      // crise de ~2 min (30 s subindo + 90 s no pico)
      const tl = crisisTimeline(v, 90);
      return {
        duracao: tl.tCalm + 120,
        canais: { ruido: envPulse(tl.tNoise, tl.tRecovery, noiseTo(v)), ...crisis(tl.tPhysio, v, tl) },
        fases: [
          [0, 'baseline (calmo)'],
          [tl.tNoise, 'ruído subindo'],
          [tl.tPhysio, 'crise: fisiologia subindo'],
          [tl.tPeak, 'crise (~2 min)'],
          [tl.tRecovery, 'recuperação gradual'],
          [tl.tCalm, 'calmo (episódio fecha após 30 s em baixo risco)'],
        ],
        tFisiologia: tl.tPhysio,
        antecedencia: v.antecedencia,
        resumo: [...crisisSummary(v, tl), ...envSummary(v)],
      };
    },
  },
  demo: {
    descricao: 'Apresentação (10,5 min): calmo → exercício → calmo → crise com ruído → recuperação → crise sem gatilho → recuperação',
    esperado: { crise: true, gatilho: 'ruido+nenhum_ambiental' },
    construir: demoScenario,
  },
};

// ---------------------------------------------------------------------------
// eventos_aleatorios
// ---------------------------------------------------------------------------

export const EVENTOS_ALEATORIOS = 'eventos_aleatorios';
const RANDOM_DESCRIPTION = 'Sequência sem fim de eventos sorteados (crises de vários tipos, estereotipia, exercício, ambiente barulhento) com pausas calmas aleatórias';

// Tipo de evento -> roteiro reaproveitado
export const TIPOS_DE_EVENTO = Object.freeze({
  sonora: 'crise_ruido',
  visual: 'crise_luz',
  sobrecarga_sensorial: 'crise_ruido_e_luz',
  interna: 'crise_sem_gatilho',
  motora: 'estereotipia',
  consequencia: 'ruido_depois_da_crise',
  exercicio: 'exercicio', // sem crise real (pode gerar alerta falso: limitacao conhecida)
  ambiente_sem_crise: 'barulho_sem_crise', // sem crise real
});

// Pesos do sorteio (proporcionais; 0 desliga o tipo)
export const PESOS_EVENTOS = Object.freeze({
  sonora: 20,
  visual: 15,
  sobrecarga_sensorial: 15,
  interna: 15,
  motora: 10,
  consequencia: 10,
  exercicio: 10,
  ambiente_sem_crise: 5,
});

// O mesmo tipo sai no maximo MAX_REPETICOES vezes seguidas
export const MAX_REPETICOES = 2;

// Intensidade das crises: multiplica a mudanca de BPM/EDA e a queda de HRV do
// roteiro. "alta" = roteiro nominal (na crise, o nivel "alto" do dataset v4:
// BPM +38, EDA +7,1); "moderada" e "leve" seguem a proporcao dos niveis
// moderado (BPM +26, EDA +4,3 -> ~0,65) e leve (BPM +11, EDA +2,1 -> ~0,3) do
// mesmo dataset. Sorteio uniforme; a variacao de +-15% do pico vale por cima.
// Abaixo de ~0,25 o modelo passa a dar so "atencao" em parte das crises.
export const INTENSIDADES = Object.freeze({ leve: 0.3, moderada: 0.65, alta: 1 });

export const SCENARIO_NAMES = [...Object.keys(SCENARIOS), EVENTOS_ALEATORIOS];

export const scenarioDescription = (name) => (name === EVENTOS_ALEATORIOS ? RANDOM_DESCRIPTION : SCENARIOS[name]?.descricao);

function drawEventType(rng, history) {
  const last = history[history.length - 1];
  const blocked = history.length >= MAX_REPETICOES && history.slice(-MAX_REPETICOES).every((t) => t === last) ? last : null;
  const options = Object.entries(PESOS_EVENTOS).filter(([tipo, peso]) => tipo !== blocked && peso > 0);
  const total = options.reduce((sum, [, peso]) => sum + peso, 0);
  let r = rng() * total;
  for (const [tipo, peso] of options) {
    r -= peso;
    if (r < 0) return tipo;
  }
  return options[options.length - 1][0];
}

function drawIntensity(rng) {
  const names = Object.keys(INTENSIDADES);
  return names[Math.min(names.length - 1, Math.floor(rng() * names.length))];
}

// ---------------------------------------------------------------------------
// Roteiro montado
// ---------------------------------------------------------------------------

// Trecho ativo = do primeiro ao ultimo ponto de qualquer sinal (antes e
// depois, tudo calmo). Sem sinais (calmo): o roteiro inteiro.
function activeSpan(canais, duracao) {
  const series = Object.values(canais).filter((points) => points?.length);
  if (!series.length) return [0, duracao];
  return [Math.min(...series.map((p) => p[0][0])), Math.max(...series.map((p) => p[p.length - 1][0]))];
}

export function buildScenario(name, v = VARIACAO_NOMINAL) {
  const scenario = SCENARIOS[name];
  if (!scenario) throw new Error(`Cenário desconhecido: ${name}`);
  const roteiro = scenario.construir(v);
  const [inicioAtivo, fimAtivo] = activeSpan(roteiro.canais, roteiro.duracao);
  return { ...roteiro, inicioAtivo, fimAtivo };
}

const nominalCache = new Map();
export function nominalScenario(name) {
  if (!nominalCache.has(name)) nominalCache.set(name, buildScenario(name));
  return nominalCache.get(name);
}

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
// t (segundos desde o inicio do roteiro). roteiro = null: tudo calmo.
function targetsAt(roteiro, t, idade) {
  const ch = (key) => valueAt(roteiro?.canais[key], t, CALMO[key]);
  return {
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
  };
}

export const calmTargets = (idade = 8) => targetsAt(null, 0, idade);

// "0 s baseline (calmo) → 120 s ruído subindo → ..."
export function describeTimeline(name) {
  if (name === EVENTOS_ALEATORIOS) {
    const total = Object.values(PESOS_EVENTOS).reduce((a, b) => a + b, 0);
    return Object.entries(PESOS_EVENTOS)
      .map(([tipo, peso]) => `${tipo} ${Math.round((100 * peso) / total)}%`)
      .join(' · ');
  }
  return nominalScenario(name).fases.map(([t, label]) => `${t} s ${label}`).join(' → ');
}

// ---------------------------------------------------------------------------
// Sorteio reprodutivel
// ---------------------------------------------------------------------------

// mulberry32: gerador com semente (mesma semente = mesma sequencia)
export function seeded(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let x = a;
    x = Math.imul(x ^ (x >>> 15), x | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}

// Uma --seed gera duas sequencias independentes: o RUIDO DOS SENSORES usa a
// propria seed (como o verificar.js sempre fez) e o ROTEIRO (variacao, tipo e
// intensidade dos eventos, pausas) usa esta derivada.
export const routineSeed = (seed) => Math.imul((seed >>> 0) ^ 0x9e3779b9, 0x85ebca6b) >>> 0;

// Roda fn() com Math.random trocado por rng (o gerador de leituras do
// simulate.js usa Math.random)
export function withRandom(rng, fn) {
  const original = Math.random;
  Math.random = rng;
  try {
    return fn();
  } finally {
    Math.random = original;
  }
}

// ---------------------------------------------------------------------------
// Programa: ciclos em loop + pausa calma
// ---------------------------------------------------------------------------

export const PAUSA_PADRAO_S = 120;
// 30 s para o episodio anterior fechar + 60 s de linha de base calma
export const PAUSA_MIN_S = 90;

function newCycle({ numero, cenario, rng, tipos, seed }) {
  let nome = cenario;
  let tipo = cenario;
  let intensidade = null;
  let v = VARIACAO_NOMINAL;
  if (cenario === EVENTOS_ALEATORIOS) {
    tipo = drawEventType(rng, tipos);
    tipos.push(tipo);
    nome = TIPOS_DE_EVENTO[tipo];
    if (SCENARIOS[nome].esperado.crise) intensidade = drawIntensity(rng);
    v = { ...drawVariation(rng, SCENARIOS[nome].limites), nivel: intensidade ? INTENSIDADES[intensidade] : 1 };
  } else if (numero > 1) {
    v = drawVariation(rng, SCENARIOS[nome].limites);
  }
  const { esperado } = SCENARIOS[nome];
  return {
    numero,
    seed,
    cenario: nome,
    tipo,
    intensidade,
    criseReal: esperado.crise,
    gatilhoEsperado: esperado.gatilho,
    variacao: v,
    roteiro: buildScenario(nome, v),
  };
}

// Linha de destaque no inicio de cada ciclo
export function cycleBanner(ciclo, aleatorio) {
  if (!aleatorio) return `=== Ciclo ${ciclo.numero} · ${ciclo.cenario} ===`;
  const parts = [`Evento ${ciclo.numero}`, ciclo.tipo];
  if (ciclo.criseReal) parts.push(`intensidade ${ciclo.intensidade}`, `gatilho esperado: ${ciclo.gatilhoEsperado}`);
  else parts.push('sem crise real', 'esperado: sem episódio');
  return `=== ${parts.join(' · ')} ===`;
}

// "roteiro crise_luz · pico ×0,92 · subida 33 s · ..."
export function cycleDetails(ciclo) {
  if (ciclo.variacao === VARIACAO_NOMINAL) return `roteiro ${ciclo.cenario} nominal (sem variação)`;
  return [`roteiro ${ciclo.cenario}`, ...ciclo.roteiro.resumo].join(' · ');
}

// Gera, segundo a segundo, o que publicar. Cada item:
//   t            segundos desde o inicio
//   alvos, fase  alvos do generateReading e nome da fase atual
//   ciclo        ciclo atual (na pausa: o que acabou de terminar). Campos de
//                tempo absolutos: tInicio/tFim (trecho ativo, quando os sinais
//                comecam a mudar e voltam ao calmo), tFisiologia, pausaDepois
//   inicioCiclo  1a leitura do ciclo (log "=== Ciclo N ===")
//   inicioEvento / fimEvento   t === tInicio / t === tFim (gabarito)
//   ultimo       ultima leitura do programa (--uma-vez ou --ciclos)
//
// Ciclo 1 = linha de base calma do proprio roteiro + trecho ativo; a partir
// do 2o, so o trecho ativo, depois de `pausa` s calmos (a pausa substitui a
// linha de base e a cauda calma do roteiro). Fora do eventos_aleatorios, o
// 1o ciclo e o roteiro nominal e os seguintes variam (drawVariation). No
// eventos_aleatorios todo evento e sorteado e a pausa varia de `pausa` a
// 2 x `pausa` (padrao: 120-240 s). Um roteiro pode exigir pausa maior
// depois dele (pausaMinima). Depois do ultimo ciclo (--ciclos) vem uma
// pausa final, para o ultimo episodio fechar no site. umaVez: so o roteiro
// nominal, do inicio ao fim (com a cauda calma original), como antes do loop.
export function* programTicks({
  cenario, umaVez = false, ciclos = Infinity, pausa = PAUSA_PADRAO_S, seed = 1, idade = 8,
}) {
  const aleatorio = cenario === EVENTOS_ALEATORIOS;
  if (!aleatorio && !SCENARIOS[cenario]) throw new Error(`Cenário desconhecido: ${cenario}`);
  const once = umaVez && !aleatorio; // no eventos_aleatorios, --uma-vez = 1 evento
  const total = umaVez ? 1 : ciclos;
  const rng = seeded(routineSeed(seed));
  const tipos = [];
  const calm = calmTargets(idade);
  let t = 0;

  for (let numero = 1; numero <= total; numero += 1) {
    const ciclo = newCycle({ numero, cenario, rng, tipos, seed });
    const r = ciclo.roteiro;
    const t0 = numero === 1 ? 0 : t - r.inicioAtivo;
    Object.assign(ciclo, {
      t0,
      tInicio: t0 + r.inicioAtivo,
      tFim: t0 + r.fimAtivo,
      tFisiologia: r.tFisiologia === null ? null : t0 + r.tFisiologia,
      pausaDepois: null,
    });
    const tEnd = once ? t0 + r.duracao : ciclo.tFim;
    const tEventEnd = once ? Math.min(ciclo.tFim, tEnd - 1) : ciclo.tFim;
    const tCycleStart = t;
    for (; t < tEnd; t += 1) {
      yield {
        t,
        ciclo,
        alvos: targetsAt(r, t - t0, idade),
        fase: phaseAt(r.fases, t - t0),
        inicioCiclo: t === tCycleStart,
        inicioEvento: t === ciclo.tInicio,
        fimEvento: t === tEventEnd,
        ultimo: once && t === tEnd - 1,
      };
    }
    if (once) return;

    const drawn = aleatorio ? pausa + Math.floor(rng() * (pausa + 1)) : pausa;
    ciclo.pausaDepois = Math.max(drawn, SCENARIOS[ciclo.cenario].pausaMinima ?? 0);
    ciclo.pausaEstendida = ciclo.pausaDepois > drawn;
    const last = numero === total;
    const next = `${aleatorio ? 'evento' : 'ciclo'} ${numero + 1}`;
    const why = ciclo.pausaEstendida ? 'recuperação + linha de base do ambiente' : 'recuperação';
    const tPauseEnd = t + ciclo.pausaDepois;
    for (; t < tPauseEnd; t += 1) {
      const left = tPauseEnd - t;
      yield {
        t,
        ciclo,
        alvos: calm,
        fase: last ? `pausa calma final · encerra em ${left} s` : `pausa calma (${why}) · ${next} em ${left} s`,
        inicioCiclo: false,
        inicioEvento: false,
        fimEvento: t === ciclo.tFim,
        ultimo: last && t === tPauseEnd - 1,
      };
    }
  }
}

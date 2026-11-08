// Indicacao do PROVAVEL gatilho ambiental de um episodio (ver docs/gatilho.md).
//
// Isto e uma REGRA explicavel, separada do modelo: o Random Forest
// (predict.js) detecta a possivel crise; aqui so olhamos o que aconteceu com
// luz e ruido antes dela. Correlacao no tempo nao prova causa, por isso o
// texto gerado sempre fala em "provavel" e quem decide e o cuidador.
//
// Funcoes puras, sem React e sem importar o forest.json: servem a pulseira,
// aos testes em Node e ao simulador de linha de comando (simulator/).
//
// Historico de entrada: array (mais antiga -> mais recente) de
//   { t, reading, tier }
//   t       segundos de sinal, crescente (1 leitura = 1 s, mesma premissa do
//           predict.js: sensor a 1 Hz)
//   reading leitura no formato da pulseira/simulador (bpm, eda_uS, luz_lux, ruido_db, ...)
//   tier    nivel do modelo naquela leitura: baixo_risco | atencao | alto_risco

// ---------------------------------------------------------------------------
// Limites (configuraveis: toda funcao aceita um objeto `config` parcial que
// sobrescreve estes valores). Valores iniciais, a ajustar com dados reais.
// ---------------------------------------------------------------------------

export const SAMPLE_PERIOD_S = 1;

// Linha de base ambiental
export const BASELINE_WINDOW_S = 300; // janela movel de leituras calmas (5 min)
export const BASELINE_MIN_CALM_S = 60; // abaixo disso a linha de base nao e confiavel
export const BASELINE_FALLBACK_S = 20; // sem base confiavel: usa as primeiras leituras disponiveis

// Analise no momento do alerta
export const ANALYSIS_WINDOW_S = 60; // ultimos 60 s antes (e incluindo) o alerta
export const PHYSIO_TOLERANCE_S = 5; // ambiente pode comecar ate 5 s DEPOIS da fisiologia
export const MIN_RUN_S = 3; // sinal precisa ficar acima do limite por >= 3 leituras
export const RUN_GAP_TOLERANCE_S = 2; // buracos de ate 2 leituras nao quebram a sequencia

// Ruido
export const NOISE_RISE_DB = 15; // aumento sobre a linha de base
export const NOISE_ABSOLUTE_DB = 80; // ou cruzar este valor absoluto...
export const NOISE_MIN_RISE_DB = 5; // ...subindo pelo menos isto (evita oscilacao em volta de 80 dB)

// Luz
export const LIGHT_RISE_FRACTION = 0.5; // aumento de 50% sobre a linha de base
export const LIGHT_ABSOLUTE_LUX = 1000; // ou cruzar este valor absoluto
export const LIGHT_FLICKER_CV = 0.3; // desvio-padrao da janela > 30% da media = luz piscando / variacao brusca
export const LIGHT_MIN_CHANGE_LUX = 100; // mudanca minima em lux (em ambiente escuro, +50% de 10 lux nao e nada)
export const LIGHT_FLICKER_MIN_STD_LUX = 50; // idem para a oscilacao

// Inicio da alteracao fisiologica: mesma regra "acima da media + margem" do
// predict.js (streakAboveTrend(bpm, 5.0, 0.5)), mas com a media das leituras
// calmas ANTERIORES como referencia, para a propria subida nao puxar a media.
export const BPM_MIN_MARGIN = 5.0;
export const BPM_MARGIN_STD_FRACTION = 0.5;
export const EDA_MIN_MARGIN_US = 0.5;
export const EDA_MARGIN_STD_FRACTION = 0.5;
// O modelo pode alertar 2-3 s depois do inicio da subida; a sequencia que
// ainda esta em curso no instante do alerta foi cortada pela janela, entao
// basta ter este minimo (em vez de MIN_RUN_S) para contar.
export const PHYSIO_MIN_TRAILING_S = 2;

export const TRIGGER_CONFIG = Object.freeze({
  SAMPLE_PERIOD_S,
  BASELINE_WINDOW_S,
  BASELINE_MIN_CALM_S,
  BASELINE_FALLBACK_S,
  ANALYSIS_WINDOW_S,
  PHYSIO_TOLERANCE_S,
  MIN_RUN_S,
  RUN_GAP_TOLERANCE_S,
  NOISE_RISE_DB,
  NOISE_ABSOLUTE_DB,
  NOISE_MIN_RISE_DB,
  LIGHT_RISE_FRACTION,
  LIGHT_ABSOLUTE_LUX,
  LIGHT_FLICKER_CV,
  LIGHT_MIN_CHANGE_LUX,
  LIGHT_FLICKER_MIN_STD_LUX,
  BPM_MIN_MARGIN,
  BPM_MARGIN_STD_FRACTION,
  EDA_MIN_MARGIN_US,
  EDA_MARGIN_STD_FRACTION,
  PHYSIO_MIN_TRAILING_S,
});

const CALM_TIER = 'baixo_risco';

const withDefaults = (config) => (config ? { ...TRIGGER_CONFIG, ...config } : TRIGGER_CONFIG);

// ---------------------------------------------------------------------------
// Estatistica basica
// ---------------------------------------------------------------------------

const mean = (arr) => (arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : 0);

const std = (arr) => {
  if (arr.length < 2) return 0;
  const avg = mean(arr);
  return Math.sqrt(mean(arr.map((v) => (v - avg) ** 2)));
};

export function median(values) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

const round = (v, digits = 0) => {
  if (v === null || v === undefined || !Number.isFinite(v)) return null;
  const f = 10 ** digits;
  return Math.round(v * f) / f;
};

// Sequencias de leituras "acima do limite". Buracos curtos (ate maxGap
// leituras) nao quebram a sequencia - um sensor real oscila. Uma sequencia so
// conta se tiver pelo menos minRun leituras acima do limite.
function findRuns(flags, minRun, maxGap) {
  const runs = [];
  let start = -1;
  let last = -1;
  let count = 0;
  const close = () => {
    if (start >= 0 && count >= minRun) runs.push({ start, end: last, count });
  };
  for (let i = 0; i < flags.length; i += 1) {
    if (!flags[i]) continue;
    if (start >= 0 && i - last - 1 <= maxGap) {
      last = i;
      count += 1;
    } else {
      close();
      start = i;
      last = i;
      count = 1;
    }
  }
  close();
  return runs;
}

const minRunReadings = (cfg) => Math.max(1, Math.round(cfg.MIN_RUN_S / cfg.SAMPLE_PERIOD_S));
const maxGapReadings = (cfg) => Math.max(0, Math.round(cfg.RUN_GAP_TOLERANCE_S / cfg.SAMPLE_PERIOD_S));

// ---------------------------------------------------------------------------
// 1. Linha de base
// ---------------------------------------------------------------------------

// Mediana de ruido e luz (e referencia de BPM/EDA) das leituras baixo_risco
// dos ultimos BASELINE_WINDOW_S segundos ANTES de `tEnd` (exclusivo). Com
// menos de BASELINE_MIN_CALM_S de leituras calmas, usa as primeiras leituras
// disponiveis do historico e marca confiavel = false.
export function computeBaseline(history, tEnd, config) {
  const cfg = withDefaults(config);
  const calm = history.filter(
    (e) => e.t < tEnd && e.t >= tEnd - cfg.BASELINE_WINDOW_S && e.tier === CALM_TIER,
  );

  let source = calm;
  let confiavel = calm.length * cfg.SAMPLE_PERIOD_S >= cfg.BASELINE_MIN_CALM_S;
  if (!confiavel) {
    const t0 = history.length ? history[0].t : 0;
    source = history.filter((e) => e.t < t0 + cfg.BASELINE_FALLBACK_S);
  }
  if (!source.length) return null;

  const bpm = source.map((e) => e.reading.bpm);
  const eda = source.map((e) => e.reading.eda_uS);
  return {
    ruido_db: median(source.map((e) => e.reading.ruido_db)),
    luz_lux: median(source.map((e) => e.reading.luz_lux)),
    bpm: median(bpm),
    bpm_std: std(bpm),
    eda_uS: median(eda),
    eda_std: std(eda),
    amostras: source.length,
    confiavel,
  };
}

// So a parte ambiental, no formato exposto no resultado.
export function computeEnvironmentalBaseline(history, tEnd, config) {
  const base = computeBaseline(history, tEnd, config);
  if (!base) return null;
  return {
    ruido_db: round(base.ruido_db, 1),
    luz_lux: round(base.luz_lux),
    amostras: base.amostras,
    confiavel: base.confiavel,
  };
}

// ---------------------------------------------------------------------------
// 2a. Inicio da alteracao fisiologica
// ---------------------------------------------------------------------------

// Inicio da ULTIMA sequencia acima do limite que ainda esta em curso no fim
// da janela (a subida que levou ao alerta). Retorna t ou null.
function sustainedRiseStart(windowEntries, getValue, threshold, cfg) {
  const flags = windowEntries.map((e) => getValue(e.reading) > threshold);
  const trailingMin = Math.max(1, Math.round(cfg.PHYSIO_MIN_TRAILING_S / cfg.SAMPLE_PERIOD_S));
  const runs = findRuns(flags, Math.min(trailingMin, minRunReadings(cfg)), maxGapReadings(cfg));
  const lastRun = runs[runs.length - 1];
  if (!lastRun || lastRun.end < windowEntries.length - 1 - maxGapReadings(cfg)) return null;
  return windowEntries[lastRun.start].t;
}

export function findPhysiologicalOnset(windowEntries, baseline, config) {
  const cfg = withDefaults(config);
  if (!windowEntries.length || !baseline) {
    return { detectada: false, sinal: null, t_inicio_s: null };
  }
  const bpmThreshold = baseline.bpm + Math.max(cfg.BPM_MIN_MARGIN, cfg.BPM_MARGIN_STD_FRACTION * baseline.bpm_std);
  const edaThreshold = baseline.eda_uS + Math.max(cfg.EDA_MIN_MARGIN_US, cfg.EDA_MARGIN_STD_FRACTION * baseline.eda_std);

  const tBpm = sustainedRiseStart(windowEntries, (r) => r.bpm, bpmThreshold, cfg);
  const tEda = sustainedRiseStart(windowEntries, (r) => r.eda_uS, edaThreshold, cfg);

  if (tBpm === null && tEda === null) {
    // O modelo pode alertar por HRV, regularidade do movimento etc. sem
    // BPM/EDA cruzarem a margem: a referencia passa a ser o proprio alerta.
    return { detectada: false, sinal: null, t_inicio_s: windowEntries[windowEntries.length - 1].t };
  }
  let sinal = 'bpm_e_eda';
  if (tEda === null || (tBpm !== null && tBpm < tEda)) sinal = 'bpm';
  else if (tBpm === null || tEda < tBpm) sinal = 'eda';
  const candidates = [tBpm, tEda].filter((v) => v !== null);
  return { detectada: true, sinal, t_inicio_s: Math.min(...candidates) };
}

// ---------------------------------------------------------------------------
// 2b. Sinais ambientais
// ---------------------------------------------------------------------------

function stableDetail(windowEntries, base, field, digits) {
  const values = windowEntries.map((e) => e.reading[field]);
  const peak = values.length ? Math.max(...values) : null;
  const detail = {
    status: 'estavel',
    criterios: [],
    linha_de_base: round(base, digits),
    valor_pico: round(peak, digits),
    variacao: peak === null ? null : round(peak - base, digits),
    antecedencia_s: null,
    t_cruzamento_s: null,
  };
  if (field === 'luz_lux') {
    detail.variacao_pct = peak !== null && base > 0 ? round(((peak - base) / base) * 100) : null;
  }
  return detail;
}

export function analyzeNoise(windowEntries, baselineDb, config) {
  const cfg = withDefaults(config);
  const base = baselineDb;
  const isRise = (v) => v - base >= cfg.NOISE_RISE_DB;
  // O limite absoluto so conta se houve CRUZAMENTO: num ambiente que ja e
  // barulhento o tempo todo (linha de base >= 80 dB) ele nao diz nada.
  const isAbsolute = (v) => base < cfg.NOISE_ABSOLUTE_DB && v >= cfg.NOISE_ABSOLUTE_DB && v - base >= cfg.NOISE_MIN_RISE_DB;

  const values = windowEntries.map((e) => e.reading.ruido_db);
  const flags = values.map((v) => isRise(v) || isAbsolute(v));
  const runs = findRuns(flags, minRunReadings(cfg), maxGapReadings(cfg));
  if (!runs.length) return stableDetail(windowEntries, base, 'ruido_db', 1);

  const first = runs[0];
  const after = values.slice(first.start);
  const peak = Math.max(...after);
  const criterios = [];
  if (after.some(isRise)) criterios.push('aumento');
  if (after.some(isAbsolute)) criterios.push('absoluto');
  return {
    status: 'detectado',
    criterios,
    linha_de_base: round(base, 1),
    valor_pico: round(peak, 1),
    variacao: round(peak - base, 1),
    antecedencia_s: null,
    t_cruzamento_s: windowEntries[first.start].t,
    desde_inicio_da_janela: first.start === 0,
  };
}

export function analyzeLight(windowEntries, baselineLux, config) {
  const cfg = withDefaults(config);
  const base = baselineLux;
  const minRun = minRunReadings(cfg);
  const maxGap = maxGapReadings(cfg);

  const values = windowEntries.map((e) => e.reading.luz_lux);
  const isRise = (v) => v - base >= Math.max(cfg.LIGHT_RISE_FRACTION * base, cfg.LIGHT_MIN_CHANGE_LUX);
  const isAbsolute = (v) => base < cfg.LIGHT_ABSOLUTE_LUX && v >= cfg.LIGHT_ABSOLUTE_LUX && v - base >= cfg.LIGHT_MIN_CHANGE_LUX;
  const riseRuns = findRuns(values.map((v) => isRise(v) || isAbsolute(v)), minRun, maxGap);

  // Variacao brusca / luz piscando: desvio-padrao da janela > 30% da media.
  // O instante de inicio e a primeira sequencia de leituras que se afastam
  // da linha de base (para cima OU para baixo) mais do que esses 30%.
  const windowStd = std(values);
  const windowMean = mean(values);
  const flicker = values.length >= minRun
    && windowStd > cfg.LIGHT_FLICKER_CV * windowMean
    && windowStd >= cfg.LIGHT_FLICKER_MIN_STD_LUX;
  const deviation = Math.max(cfg.LIGHT_FLICKER_CV * base, cfg.LIGHT_MIN_CHANGE_LUX);
  const flickerRuns = flicker ? findRuns(values.map((v) => Math.abs(v - base) >= deviation), minRun, maxGap) : [];

  const starts = [riseRuns[0]?.start, flickerRuns[0]?.start].filter((v) => v !== undefined);
  if (!starts.length) return stableDetail(windowEntries, base, 'luz_lux', 0);

  const startIdx = Math.min(...starts);
  const after = values.slice(startIdx);
  // "Pico" = leitura mais distante da linha de base (pode ser um apagao)
  const peak = after.reduce((best, v) => (Math.abs(v - base) > Math.abs(best - base) ? v : best), after[0]);
  const criterios = [];
  if (after.some(isRise)) criterios.push('aumento');
  if (after.some(isAbsolute)) criterios.push('absoluto');
  if (flickerRuns.length) criterios.push('oscilacao');
  return {
    status: 'detectado',
    criterios,
    linha_de_base: round(base),
    valor_pico: round(peak),
    variacao: round(peak - base),
    variacao_pct: base > 0 ? round(((peak - base) / base) * 100) : null,
    faixa_lux: [round(Math.min(...after)), round(Math.max(...after))],
    oscilacao_cv: windowMean > 0 ? round(windowStd / windowMean, 2) : null,
    antecedencia_s: null,
    t_cruzamento_s: windowEntries[startIdx].t,
    desde_inicio_da_janela: startIdx === 0,
  };
}

// Ordem temporal: o ambiente so e gatilho se comecou ANTES da fisiologia ou
// no maximo PHYSIO_TOLERANCE_S depois. Se comecou bem depois, e mais provavel
// que seja consequencia da crise (ex.: a crianca gritando eleva o ruido).
function classify(detail, tPhysio, cfg) {
  if (detail.status === 'estavel') return detail;
  const lead = tPhysio - detail.t_cruzamento_s;
  return {
    ...detail,
    status: -lead <= cfg.PHYSIO_TOLERANCE_S ? 'gatilho' : 'possivel_consequencia',
    antecedencia_s: round(lead),
  };
}

// ---------------------------------------------------------------------------
// Texto pronto (sempre "provavel", nunca afirma causa)
// ---------------------------------------------------------------------------

const SIGNAL_NAMES = { ruido: 'ruído', luminosidade: 'luminosidade' };
const NONE_CAUSE = 'A causa pode ser outra (social, rotina, desconforto físico).';

function valuesText(key, d) {
  if (key === 'ruido') return `${Math.round(d.linha_de_base)} → ${Math.round(d.valor_pico)} dB`;
  if (d.criterios.includes('oscilacao') && !d.criterios.includes('aumento') && !d.criterios.includes('absoluto')) {
    return `oscilando entre ${d.faixa_lux[0]} e ${d.faixa_lux[1]} lux`;
  }
  return `${d.linha_de_base} → ${d.valor_pico} lux`;
}

function timingText(d, physioDetected) {
  const ref = physioDetected ? 'da alteração fisiológica' : 'do alerta do modelo';
  const lead = d.antecedencia_s;
  if (lead >= 3) return `${d.desde_inicio_da_janela ? 'pelo menos' : 'cerca de'} ${lead} s antes ${ref}`;
  // de 2 s antes ate PHYSIO_TOLERANCE_S depois: praticamente simultaneo
  if (d.status === 'gatilho') {
    return `praticamente junto ${physioDetected ? 'com a alteração fisiológica' : 'com o alerta do modelo'}`;
  }
  return `só cerca de ${-lead} s depois ${ref}`;
}

export function describeTrigger(result) {
  const entries = Object.entries(result.sinais);
  const triggers = entries.filter(([, d]) => d.status === 'gatilho');
  const consequences = entries.filter(([, d]) => d.status === 'possivel_consequencia');
  const physio = result.fisiologia.detectada;
  const part = ([key, d]) => `${SIGNAL_NAMES[key]} (${valuesText(key, d)}, ${timingText(d, physio)})`;

  const sentences = [];
  if (triggers.length) {
    sentences.push(`Provável gatilho: ${triggers.map(part).join(' e ')}.`);
    if (consequences.length) {
      sentences.push(`Mudança em ${consequences.map(part).join(' e ')}: possível consequência, não conta como gatilho.`);
    }
  } else if (consequences.length) {
    sentences.push('Sem gatilho ambiental aparente.');
    sentences.push(`Mudança em ${consequences.map(part).join(' e ')}: possível consequência, não gatilho.`);
    sentences.push(NONE_CAUSE);
  } else {
    sentences.push(`Sem gatilho ambiental aparente: luz e ruído estáveis. ${NONE_CAUSE}`);
  }
  if (!result.baseline_confiavel) {
    sentences.push('Linha de base ambiental ainda curta (menos de 60 s de leituras calmas): interpretar com cautela.');
  }
  return sentences.join(' ');
}

function buildResult({ baseline, physio, sinais, tWindowStart, tAlert, updated }) {
  const isTrigger = (key) => sinais[key].status === 'gatilho';
  let tipo = 'nenhum_ambiental';
  if (isTrigger('ruido') && isTrigger('luminosidade')) tipo = 'ruido_e_luminosidade';
  else if (isTrigger('ruido')) tipo = 'ruido';
  else if (isTrigger('luminosidade')) tipo = 'luminosidade';

  const result = {
    tipo,
    texto: '',
    baseline_confiavel: baseline.confiavel,
    linha_de_base: {
      ruido_db: round(baseline.ruido_db, 1),
      luz_lux: round(baseline.luz_lux),
      amostras: baseline.amostras,
    },
    fisiologia: {
      detectada: physio.detectada,
      sinal: physio.sinal,
      t_inicio_s: physio.t_inicio_s,
      antes_do_alerta_s: round(tAlert - physio.t_inicio_s),
    },
    sinais,
    t_inicio_janela_s: tWindowStart,
    t_alerta_s: tAlert,
    atualizado_durante_episodio: updated,
  };
  result.texto = describeTrigger(result);
  return result;
}

const entriesBetween = (history, tFrom, tTo) => history.filter((e) => e.t >= tFrom && e.t <= tTo);

// ---------------------------------------------------------------------------
// API principal
// ---------------------------------------------------------------------------

// Analise no instante do alerta (history[alertPos], normalmente a leitura em
// que o nivel saiu de baixo_risco). Olha os ultimos ANALYSIS_WINDOW_S
// segundos e compara com a linha de base das leituras calmas ANTERIORES a
// essa janela - assim o proprio gatilho nao contamina a referencia.
export function analyzeTrigger(history, alertPos = history.length - 1, config) {
  const cfg = withDefaults(config);
  const alert = history[alertPos];
  if (!alert) return null;
  const tAlert = alert.t;
  const tWindowStart = tAlert - cfg.ANALYSIS_WINDOW_S + cfg.SAMPLE_PERIOD_S;
  const windowEntries = entriesBetween(history, tWindowStart, tAlert);

  const baseline = computeBaseline(history, tWindowStart, cfg);
  const physio = findPhysiologicalOnset(windowEntries, baseline, cfg);
  const sinais = {
    ruido: classify(analyzeNoise(windowEntries, baseline.ruido_db, cfg), physio.t_inicio_s, cfg),
    luminosidade: classify(analyzeLight(windowEntries, baseline.luz_lux, cfg), physio.t_inicio_s, cfg),
  };
  return buildResult({ baseline, physio, sinais, tWindowStart, tAlert, updated: false });
}

// Reavaliacao durante o episodio: linha de base e inicio fisiologico ficam
// congelados (calculados no inicio); so os sinais que estavam estaveis sao
// reanalisados, da janela original ate a leitura mais recente. Devolve o
// MESMO objeto se nada mudou (facilita comparar por referencia).
export function reviewTrigger(previous, history, config) {
  if (!previous || !history.length) return previous;
  const cfg = withDefaults(config);
  const pending = Object.entries(previous.sinais).filter(([, d]) => d.status === 'estavel');
  if (!pending.length) return previous;

  const tNow = history[history.length - 1].t;
  if (tNow <= previous.t_alerta_s) return previous;
  const windowEntries = entriesBetween(history, previous.t_inicio_janela_s, tNow);
  const tPhysio = previous.fisiologia.t_inicio_s;
  const analyzers = {
    ruido: () => analyzeNoise(windowEntries, previous.linha_de_base.ruido_db, cfg),
    luminosidade: () => analyzeLight(windowEntries, previous.linha_de_base.luz_lux, cfg),
  };

  let changed = false;
  const sinais = { ...previous.sinais };
  for (const [key] of pending) {
    const detail = analyzers[key]();
    if (detail.status === 'estavel') continue;
    sinais[key] = classify(detail, tPhysio, cfg);
    changed = true;
  }
  if (!changed) return previous;

  return buildResult({
    baseline: { ...previous.linha_de_base, confiavel: previous.baseline_confiavel },
    physio: previous.fisiologia,
    sinais,
    tWindowStart: previous.t_inicio_janela_s,
    tAlert: previous.t_alerta_s,
    updated: true,
  });
}

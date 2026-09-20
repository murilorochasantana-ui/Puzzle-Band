import forest from './forest.json';

const SHORT_WINDOW = forest.shortWindow; // 5s
const LONG_WINDOW = forest.longWindow; // 30s
const MIN_HISTORY = LONG_WINDOW + 1; // precisa de t-30 disponivel

const mean = (arr) => arr.reduce((a, b) => a + b, 0) / arr.length;
const std = (arr, avg) => Math.sqrt(mean(arr.map((v) => (v - avg) ** 2)));

// Streak: quantos segundos CONSECUTIVOS, olhando pra tras a partir do
// ultimo elemento da janela, o valor ficou acima da media da janela + uma
// margem - mesma logica de model/features.py (_rolling_streak_above_trend).
function streakAboveTrend(windowValues, minMargin, marginFracStd) {
  const avg = mean(windowValues);
  const margin = Math.max(minMargin, marginFracStd * std(windowValues, avg));
  const threshold = avg + margin;
  let streak = 0;
  for (let i = windowValues.length - 1; i >= 0; i -= 1) {
    if (windowValues[i] <= threshold) break;
    streak += 1;
  }
  return streak;
}

// Recebe o historico de leituras (mais antiga -> mais recente) e calcula as
// mesmas features usadas no treino em Python (model/features.py). Retorna
// null se ainda nao ha janela suficiente (equivalente ao dropna() do treino).
export function computeFeatures(history) {
  const n = history.length;
  if (n < MIN_HISTORY) return null;

  const cur = history[n - 1];
  const last30 = history.slice(n - LONG_WINDOW, n);
  const bpm30 = last30.map((r) => r.bpm);
  const eda30 = last30.map((r) => r.eda_uS);
  const gyro30 = last30.map((r) => r.gyro_mag_dps);
  const hrv30 = last30.map((r) => r.hrv_ms);
  const accel30 = last30.map((r) => r.accel_mag_g);
  const reg30 = last30.map((r) => r.regularidade);
  const luz30 = last30.map((r) => r.luz_lux);
  const ruido30 = last30.map((r) => r.ruido_db);

  const lagShort = history[n - 1 - SHORT_WINDOW];
  const lagLong = history[n - 1 - LONG_WINDOW];

  const bpmSlopeShort = (cur.bpm - lagShort.bpm) / SHORT_WINDOW;
  const bpmSlopeLong = (cur.bpm - lagLong.bpm) / LONG_WINDOW;

  return {
    bpm: cur.bpm,
    bpm_mean_long: mean(bpm30),
    bpm_slope_short: bpmSlopeShort,
    bpm_slope_long: bpmSlopeLong,
    bpm_jerk: bpmSlopeShort - bpmSlopeLong,
    bpm_tempo_elevado: streakAboveTrend(bpm30, 5.0, 0.5),

    eda: cur.eda_uS,
    eda_mean_long: mean(eda30),
    eda_slope_long: (cur.eda_uS - lagLong.eda_uS) / LONG_WINDOW,

    gyro_mag: cur.gyro_mag_dps,
    gyro_mean_long: mean(gyro30),
    gyro_slope_long: (cur.gyro_mag_dps - lagLong.gyro_mag_dps) / LONG_WINDOW,

    hrv: cur.hrv_ms,
    hrv_mean_long: mean(hrv30),
    hrv_slope_long: (cur.hrv_ms - lagLong.hrv_ms) / LONG_WINDOW,

    accel_mag: cur.accel_mag_g,
    accel_mean_long: mean(accel30),
    regularidade_mean_long: mean(reg30),

    luz: cur.luz_lux,
    luz_mean_long: mean(luz30),
    ruido: cur.ruido_db,
    ruido_mean_long: mean(ruido30),
    ruido_slope_long: (cur.ruido_db - lagLong.ruido_db) / LONG_WINDOW,

    idade: cur.idade,
  };
}

function walkTree(node, vector) {
  let current = node;
  while (!current.leaf) {
    current = vector[current.feature] <= current.threshold ? current.left : current.right;
  }
  return current.proba;
}

// Media das probabilidades de cada arvore da floresta (bagging), igual ao
// RandomForestClassifier.predict_proba do scikit-learn.
export function predictCrisisProbability(featuresDict) {
  const vector = forest.featureColumns.map((name) => featuresDict[name]);
  let sum = 0;
  for (const tree of forest.trees) {
    sum += walkTree(tree, vector);
  }
  return sum / forest.trees.length;
}

// Faixas calibradas a partir da distribuicao real de probabilidade do
// modelo no dataset v4 (validacao cruzada por crianca, 24 features):
//   nenhum:   mediana 0.16, 90º percentil 0.48
//   leve:     mediana 0.81 (10º percentil 0.31 - casos sutis ficam baixos)
//   moderado: mediana 0.95   alto: mediana 0.97
export function riskTierFromProbability(p) {
  if (p >= 0.7) return 'alto_risco';
  if (p >= 0.4) return 'atencao';
  return 'baixo_risco';
}

export const MIN_HISTORY_REQUIRED = MIN_HISTORY;

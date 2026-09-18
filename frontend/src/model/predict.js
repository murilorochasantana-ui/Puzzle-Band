import forest from './forest.json';

const SHORT_WINDOW = forest.shortWindow; // 5s
const LONG_WINDOW = forest.longWindow; // 30s
const MIN_HISTORY = LONG_WINDOW + 1; // precisa de t-30 disponivel

const mean = (arr) => arr.reduce((a, b) => a + b, 0) / arr.length;

// Recebe o historico de leituras (mais antiga -> mais recente) e calcula as
// mesmas features usadas no treino em Python (model/features.py). Retorna
// null se ainda nao ha janela suficiente (equivalente ao dropna() do treino).
export function computeFeatures(history) {
  const n = history.length;
  if (n < MIN_HISTORY) return null;

  const cur = history[n - 1];
  const last30 = history.slice(n - LONG_WINDOW, n);
  const bpmMeanLong = mean(last30.map((r) => r.bpm));
  const edaMeanLong = mean(last30.map((r) => r.eda_uS));
  const gyroMeanLong = mean(last30.map((r) => r.gyro_mag_dps));

  const lagShort = history[n - 1 - SHORT_WINDOW];
  const lagLong = history[n - 1 - LONG_WINDOW];

  const bpmSlopeShort = (cur.bpm - lagShort.bpm) / SHORT_WINDOW;
  const bpmSlopeLong = (cur.bpm - lagLong.bpm) / LONG_WINDOW;

  return {
    bpm: cur.bpm,
    bpm_mean_long: bpmMeanLong,
    bpm_slope_short: bpmSlopeShort,
    bpm_slope_long: bpmSlopeLong,
    bpm_jerk: bpmSlopeShort - bpmSlopeLong,
    eda: cur.eda_uS,
    eda_mean_long: edaMeanLong,
    eda_slope_long: (cur.eda_uS - lagLong.eda_uS) / LONG_WINDOW,
    gyro_mag: cur.gyro_mag_dps,
    gyro_mean_long: gyroMeanLong,
    gyro_slope_long: (cur.gyro_mag_dps - lagLong.gyro_mag_dps) / LONG_WINDOW,
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
// modelo no dataset v3 (validacao cruzada por crianca):
//   nenhum:   mediana 0.21, 90º percentil 0.49
//   leve:     mediana 0.70 (dataset v3 tem sobreposicao deliberada com
//             exercicio intenso, entao "leve" fica mais dificil de
//             separar de "nenhum" do que no dataset anterior)
//   moderado: mediana 0.96   alto: mediana 0.98
// moderado e alto ficam quase indistinguiveis so pela probabilidade binaria,
// por isso o dashboard usa 3 faixas de risco (nao os 4 rotulos originais).
export function riskTierFromProbability(p) {
  if (p >= 0.75) return 'alto_risco';
  if (p >= 0.45) return 'atencao';
  return 'baixo_risco';
}

export const MIN_HISTORY_REQUIRED = MIN_HISTORY;

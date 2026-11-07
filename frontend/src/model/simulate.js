// Gera leituras sinteticas ao vivo a partir de valores-alvo, sem depender do
// dataset. Quem gera e a pulseira simulada (simulator/): nos cenarios e no
// modo controle (alvos enviados pelo painel do site). As magnitudes-base de cada acao do giroscopio foram
// calibradas pelas medias observadas no dataset original, so como ponto de
// partida realista - o ruido por leitura reproduz a variabilidade alta que
// os sensores reais (e o dataset) mostram mesmo dentro de uma mesma
// atividade.

export const GYRO_ACTIONS = [
  { id: 'repouso', label: 'Repouso (parado)', base: 5 },
  { id: 'andando', label: 'Andando', base: 45 },
  { id: 'brincando', label: 'Brincando', base: 110 },
  { id: 'correndo', label: 'Correndo', base: 180 },
  { id: 'agitado', label: 'Agitado / estereotipia intensa', base: 250 },
];

const gyroBaseFor = (actionId) => GYRO_ACTIONS.find((a) => a.id === actionId)?.base ?? 5;

const clamp = (v, min, max) => Math.min(max, Math.max(min, v));

// Uma leitura por "segundo simulado", com ruido em torno dos alvos atuais.
// `movimentoRepetitivo` controla o indice de regularidade do acelerometro,
// INDEPENDENTE da intensidade do giroscopio - da pra simular tanto
// "correr com amigos" (movimento intenso, IRREGULAR) quanto uma
// estereotipia motora (intensidade qualquer, mas bem REGULAR/periodica).
//
// `gyroBase` e `regularidadeBase` sao sobrescritas OPCIONAIS (numericas) de
// gyroAction / movimentoRepetitivo, usadas pela pulseira simulada
// (simulator/) pra fazer rampas graduais nos cenarios e no modo controle.
export function generateReading({
  bpmTarget, edaTarget, gyroAction, idade, timestamp,
  hrvTarget, movimentoRepetitivo, luzTarget, ruidoTarget,
  gyroBase: gyroBaseOverride, regularidadeBase,
}) {
  const bpm = Math.round(clamp(bpmTarget + (Math.random() - 0.5) * 4, 40, 200));
  const eda_uS = Number(clamp(edaTarget + (Math.random() - 0.5) * 0.6, 1, 20).toFixed(2));

  const gyroBase = gyroBaseOverride ?? gyroBaseFor(gyroAction);
  const gyro_mag_dps = Number(clamp(gyroBase * (0.4 + Math.random() * 1.3), 0.05, 950).toFixed(2));

  const hrv_ms = Number(clamp(hrvTarget + (Math.random() - 0.5) * 4, 8, 120).toFixed(1));

  const accel_mag_g = Number(clamp(gyro_mag_dps * 0.55 * (0.5 + Math.random() * 1.1), 0.02, 20).toFixed(2));
  const regBase = regularidadeBase ?? (movimentoRepetitivo ? 0.8 : 0.08);
  const regularidade = Number(clamp(regBase + (Math.random() - 0.5) * 0.2, 0, 1).toFixed(2));

  const luz_lux = Number(clamp(luzTarget + (Math.random() - 0.5) * 30, 5, 2000).toFixed(0));
  const ruido_db = Number(clamp(ruidoTarget + (Math.random() - 0.5) * 4, 20, 110).toFixed(1));

  return {
    timestamp, bpm, eda_uS, gyro_mag_dps, idade,
    hrv_ms, accel_mag_g, regularidade, luz_lux, ruido_db,
  };
}

// ---------------------------------------------------------------------------
// Controle da pulseira (topico puzzleband/<id>/controle): valores-alvo que o
// painel do site envia para a pulseira no modo "controle" (npm run controle,
// em simulator/). As faixas sao as dos controles do painel; a pulseira ignora
// o valor que vier fora delas (hooks/parseMessages.js, parseControl).
// ---------------------------------------------------------------------------

export const CONTROL_LIMITS = Object.freeze({
  bpm: Object.freeze({ min: 50, max: 190 }),
  eda: Object.freeze({ min: 1, max: 16 }), // uS
  hrv: Object.freeze({ min: 10, max: 90 }), // ms
  movimento: Object.freeze({ min: 0, max: 250 }), // dps: intensidade-base do giroscopio (GYRO_ACTIONS)
  regularidade: Object.freeze({ min: 0, max: 1 }), // regularidade do movimento
  luz: Object.freeze({ min: 0, max: 1000 }), // lux
  ruido: Object.freeze({ min: 20, max: 100 }), // dB
  idade: Object.freeze({ min: 5, max: 12, inteiro: true }), // anos
});

// Regularidade do movimento nos dois botoes do painel (os mesmos valores que
// generateReading usa para movimentoRepetitivo false/true)
export const REGULARIDADE = Object.freeze({ livre: 0.08, repetitivo: 0.8 });

// Estado calmo: os padroes do painel e de simulator/scenarios.js (CALMO)
export const CALM_CONTROL = Object.freeze({
  bpm: 78, eda: 4, hrv: 55, movimento: 5, regularidade: REGULARIDADE.livre, luz: 300, ruido: 45, idade: 8,
});

// Valores do controle -> argumentos de generateReading (mesmo ruido de
// sempre). O movimento e a regularidade vao como numeros (gyroBase e
// regularidadeBase) para a pulseira poder fazer rampas entre eles.
export function controlTargets(control) {
  return {
    bpmTarget: control.bpm,
    edaTarget: control.eda,
    hrvTarget: control.hrv,
    gyroAction: 'repouso',
    gyroBase: control.movimento,
    movimentoRepetitivo: false,
    regularidadeBase: control.regularidade,
    luzTarget: control.luz,
    ruidoTarget: control.ruido,
    idade: control.idade,
  };
}

"""
Calibracao individual da crianca SIMULADA (estudo "exercicio x crise", E2d;
docs/modelo.md). Gera uma sessao de calibracao com o mesmo gerador de
leituras da pulseira (frontend/src/model/simulate.js): CAL_CALMO_S segundos
calmos e depois exercicio (subida de 40 s e platô), com os valores calmos e
o exercicio do simulator/scenarios.js. Calcula a linha de base e os
coeficientes com a MESMA funcao do estudo (estudo_exercicio.calibracao_de) e
grava o forest.json com o campo "calibracao" (lido pelo predict.js).

Roda (da raiz): python model/calibrar_simulador.py <forest.json> <saida.json> [--seed 7]
"""
import argparse
import json
import subprocess
import sys
from io import StringIO
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from estudo_exercicio import CAL_ATIVO_S, CAL_CALMO_S, JANELA_S, base_da_janela, calibracao_de  # noqa: E402
from features import build_features  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent

GERAR = """
import { generateReading } from '../frontend/src/model/simulate.js';
import { calmTargets, CALMO, seeded, withRandom } from '../simulator/scenarios.js';
const [calmoS, ativoS, seed] = process.argv.slice(2).map(Number);
const calm = calmTargets(8);
const SUBIDA = 40;
const linhas = ['timestamp,atividade,batimento_cardiaco_bpm,nivel_suor_uS,giroscopio_magnitude_dps,hrv_rmssd_ms,'
  + 'acelerometro_magnitude_g,movimento_regularidade,luminosidade_lux,ruido_db,idade'];
withRandom(seeded(seed), () => {
  for (let t = 0; t < calmoS + SUBIDA + ativoS; t += 1) {
    const e = t < calmoS ? 0 : Math.min(1, (t - calmoS) / SUBIDA); // exercicio do scenarios.js
    const r = generateReading({ ...calm, bpmTarget: CALMO.bpm + 38 * e, edaTarget: CALMO.eda + 2.6 * e,
      hrvTarget: CALMO.hrv - 13 * e, gyroBase: CALMO.gyro + 107 * e, timestamp: new Date(t * 1000).toISOString() });
    linhas.push([r.timestamp, t < calmoS ? 'calmo' : 'brincadeira_ativa', r.bpm, r.eda_uS, r.gyro_mag_dps, r.hrv_ms,
      r.accel_mag_g, r.regularidade, r.luz_lux, r.ruido_db, r.idade].join(','));
  }
});
console.log(linhas.join('\\n'));
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('forest')
    ap.add_argument('saida')
    ap.add_argument('--seed', type=int, default=7)
    ap.add_argument('--janela', action='store_true',
                    help='so a linha de base dos primeiros JANELA_S s (sem rotulo; coeficientes globais do forest.json)')
    args = ap.parse_args()
    script = ROOT / 'model' / '_gerar_calibracao.mjs'
    script.write_text(GERAR, encoding='utf-8')
    try:
        csv = subprocess.run(['node', str(script), str(CAL_CALMO_S), str(CAL_ATIVO_S), str(args.seed)], cwd=ROOT,
                             capture_output=True, text=True, check=True).stdout
    finally:
        script.unlink()
    cru = pd.read_csv(StringIO(csv))
    cru['timestamp'] = pd.to_datetime(cru['timestamp'])
    cru['id_crianca'] = 'SIM'
    cru['estresse'] = 0
    cru['nivel_estresse'] = 'nenhum'
    feats = build_features(cru).merge(cru[['timestamp', 'atividade']], on='timestamp')
    cal = base_da_janela(cru, JANELA_S) if args.janela else calibracao_de(feats, cru)
    forest = json.load(open(args.forest))
    forest['calibracao'] = cal
    with open(args.saida, 'w') as f:
        json.dump(forest, f, separators=(',', ':'))
    print(json.dumps(cal, indent=1))


if __name__ == '__main__':
    main()

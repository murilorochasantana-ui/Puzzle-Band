"""
Gerador do dataset MASSIVO do Puzzle Band - pronto pra treinamento manual.

Reaproveita a mesma logica fisiologica do gerador v3 (onset subito vs
gradual, estresse desacoplado do movimento) importando o script
08_generate_dataset_v3.py como modulo, mas com bem mais criancas e sessoes
mais longas, e ja EXPORTA TODAS AS FEATURES calculadas (medias moveis,
inclinacoes curta/longa, jerk) junto com os dados brutos - nao so os sinais
crus. A ideia e entregar uma tabela pronta: uma linha = um segundo, com
todas as colunas que um treino de modelo precisaria, sem nenhum passo de
pre-processamento extra.

Roda: python3 model/eda/09_generate_massive_dataset.py
"""
import importlib.util
import sys
from pathlib import Path

import numpy as np
import pandas as pd

HERE = Path(__file__).parent
MODEL_DIR = HERE.parent

# importa 08_generate_dataset_v3.py como modulo (nome comeca com digito,
# entao nao da pra fazer "import 08_generate...")
spec = importlib.util.spec_from_file_location('gen_v3', HERE / '08_generate_dataset_v3.py')
gen_v3 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen_v3)

sys.path.insert(0, str(MODEL_DIR))
from features import LONG_WINDOW, SHORT_WINDOW  # noqa: E402

OUT_DIR = MODEL_DIR.parent / 'data/raw/massive'
N_CHILDREN = 40
SESSION_SECONDS = 10800  # 3h por crianca (vs 2.5h do dataset v3)
CHILDREN_PER_FILE = 10   # 40 criancas -> 4 arquivos

AGE_CHOICES = list(range(5, 13))


def build_activity_features(df_child):
    """Mesmas features de model/features.py, calculadas aqui direto (sem
    dropna) pra manter todas as linhas no arquivo, com NaN nas primeiras
    ~30 linhas de cada crianca (onde a janela longa ainda nao tem historico
    suficiente) - fica explicito no dado, em vez de sumir silenciosamente."""
    bpm = df_child['batimento_cardiaco_bpm']
    eda = df_child['nivel_suor_uS']
    gyro = df_child['giroscopio_magnitude_dps']

    out = pd.DataFrame(index=df_child.index)
    out['bpm_mean_long'] = bpm.rolling(LONG_WINDOW, min_periods=LONG_WINDOW).mean()
    bpm_lag_short = bpm.shift(SHORT_WINDOW)
    bpm_lag_long = bpm.shift(LONG_WINDOW)
    out['bpm_slope_short'] = (bpm - bpm_lag_short) / SHORT_WINDOW
    out['bpm_slope_long'] = (bpm - bpm_lag_long) / LONG_WINDOW
    out['bpm_jerk'] = out['bpm_slope_short'] - out['bpm_slope_long']

    out['eda_mean_long'] = eda.rolling(LONG_WINDOW, min_periods=LONG_WINDOW).mean()
    eda_lag_long = eda.shift(LONG_WINDOW)
    out['eda_slope_long'] = (eda - eda_lag_long) / LONG_WINDOW

    out['gyro_mean_long'] = gyro.rolling(LONG_WINDOW, min_periods=LONG_WINDOW).mean()
    gyro_lag_long = gyro.shift(LONG_WINDOW)
    out['gyro_slope_long'] = (gyro - gyro_lag_long) / LONG_WINDOW

    return out


def generate_all_children(rng):
    rows = []
    for i in range(N_CHILDREN):
        cid = f'C{i+1:03d}'
        idade = int(rng.choice(AGE_CHOICES))
        child_rng = np.random.default_rng(rng.integers(0, 2**31 - 1))

        baseline_bpm = float(np.clip(child_rng.normal(92, 8), 70, 115))
        baseline_eda = float(np.clip(child_rng.normal(3.9, 0.8), 2.2, 6.0))

        bpm_off, eda_off, gyro_off, activity_label = gen_v3.build_activity_track(SESSION_SECONDS, child_rng)

        estresse = np.zeros(SESSION_SECONDS, dtype=int)
        nivel = np.full(SESSION_SECONDS, 'nenhum', dtype=object)

        episodes = gen_v3.inject_stress_episodes(
            bpm_off, eda_off, gyro_off, estresse, nivel, child_rng,
            required_levels=gen_v3.LEVELS,
        )

        bpm = baseline_bpm + bpm_off + child_rng.normal(0, 2.2, SESSION_SECONDS)
        eda = baseline_eda + eda_off + child_rng.normal(0, 0.25, SESSION_SECONDS)
        gyro_mag = np.clip(gyro_off * (0.4 + child_rng.random(SESSION_SECONDS) * 1.3), 0.05, 950)

        bpm = np.clip(np.round(bpm), 50, 190).astype(int)
        eda = np.round(np.clip(eda, 1.0, 20.0), 2)
        gyro_mag = np.round(gyro_mag, 2)

        theta = child_rng.uniform(0, np.pi, SESSION_SECONDS)
        phi = child_rng.uniform(0, 2 * np.pi, SESSION_SECONDS)
        gx = np.round(gyro_mag * np.sin(theta) * np.cos(phi), 2)
        gy = np.round(gyro_mag * np.sin(theta) * np.sin(phi), 2)
        gz = np.round(gyro_mag * np.cos(theta), 2)
        gyro_mag_recomputed = np.round(np.sqrt(gx**2 + gy**2 + gz**2), 2)

        timestamps = pd.date_range(gen_v3.START_TS, periods=SESSION_SECONDS, freq='s')

        child_df = pd.DataFrame({
            'timestamp': timestamps,
            'id_crianca': cid,
            'idade': idade,
            'atividade': activity_label,
            'batimento_cardiaco_bpm': bpm,
            'nivel_suor_uS': eda,
            'giroscopio_x_dps': gx,
            'giroscopio_y_dps': gy,
            'giroscopio_z_dps': gz,
            'giroscopio_magnitude_dps': gyro_mag_recomputed,
            'estresse': estresse,
            'nivel_estresse': nivel,
        })

        feats = build_activity_features(child_df)
        child_df = pd.concat([child_df, feats], axis=1)

        rows.append(child_df)

        n_sudden = sum(1 for e in episodes if e[5])
        print(f'{cid}: idade={idade} baseline_bpm={baseline_bpm:.1f} baseline_eda={baseline_eda:.2f} '
              f'episodios={len(episodes)} (subitos={n_sudden}, graduais={len(episodes)-n_sudden})')

    return rows


def main():
    rng = np.random.default_rng(2026)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    child_dfs = generate_all_children(rng)

    column_order = [
        'timestamp', 'id_crianca', 'idade', 'atividade',
        'batimento_cardiaco_bpm', 'nivel_suor_uS',
        'giroscopio_x_dps', 'giroscopio_y_dps', 'giroscopio_z_dps', 'giroscopio_magnitude_dps',
        'bpm_mean_long', 'bpm_slope_short', 'bpm_slope_long', 'bpm_jerk',
        'eda_mean_long', 'eda_slope_long',
        'gyro_mean_long', 'gyro_slope_long',
        'estresse', 'nivel_estresse',
    ]

    n_files = (N_CHILDREN + CHILDREN_PER_FILE - 1) // CHILDREN_PER_FILE
    total_rows = 0
    for part in range(n_files):
        chunk = child_dfs[part * CHILDREN_PER_FILE:(part + 1) * CHILDREN_PER_FILE]
        part_df = pd.concat(chunk, ignore_index=True)[column_order]
        out_path = OUT_DIR / f'puzzle_band_features_parte{part+1}_de_{n_files}.csv'
        part_df.to_csv(out_path, index=False)
        total_rows += len(part_df)
        print(f'-> {out_path.name}: {len(part_df)} linhas, {part_df["id_crianca"].nunique()} criancas')

    print()
    print(f'Total: {total_rows} linhas, {N_CHILDREN} criancas, {n_files} arquivos em {OUT_DIR}')


if __name__ == '__main__':
    main()

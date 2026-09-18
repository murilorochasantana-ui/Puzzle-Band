"""
Preenche lacunas de cobertura no dataset original: garante que toda crianca
tenha ao menos um episodio de cada nivel_estresse (leve/moderado/alto),
inserindo episodios sinteticos dentro de trechos 'calmo' existentes.

Mantém intacto tudo que já validou bem na análise (linha do tempo,
contiguidade dos episódios, baseline por criança) — só completa o que faltava.
"""
import numpy as np
import pandas as pd

rng = np.random.default_rng(42)

SRC = '/home/user/puzzle-band/data/raw/dataset_pulseira_TEA_estresse.xlsx'
OUT = '/home/user/puzzle-band/data/raw/dataset_pulseira_TEA_estresse_v2.xlsx'

df = pd.read_excel(SRC, sheet_name='Dados').reset_index(drop=True)

LEVELS = ['leve', 'moderado', 'alto']

# alvo (media/desvio) por nivel, medido no dataset original inteiro
level_stats = df.groupby('nivel_estresse')[
    ['batimento_cardiaco_bpm', 'nivel_suor_uS', 'giroscopio_magnitude_dps']
].agg(['mean', 'std'])

global_calm_bpm = df.loc[df['estresse'] == 0, 'batimento_cardiaco_bpm'].mean()
global_calm_eda = df.loc[df['estresse'] == 0, 'nivel_suor_uS'].mean()

EPISODE_LEN = 150  # segundos (~mediana dos episodios reais: 154s)
RAMP_FRAC = 0.25   # 25% subida, 50% platô, 25% descida
BUFFER = 60        # segundos de folga em torno de episodios existentes

def smooth_envelope(n, ramp_frac=RAMP_FRAC):
    ramp_n = max(1, int(n * ramp_frac))
    up = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, ramp_n))
    hold = np.ones(n - 2 * ramp_n)
    down = up[::-1]
    return np.concatenate([up, hold, down])[:n]

def find_free_stretch(sub_estresse, length, buffer, rng):
    """Acha um indice inicial (relativo ao bloco da crianca) de um trecho
    100% calmo (estresse==0), com folga de `buffer` segundos antes/depois
    de qualquer episodio existente."""
    n = len(sub_estresse)
    padded = np.zeros(n, dtype=bool)
    stressed_idx = np.where(sub_estresse == 1)[0]
    for i in stressed_idx:
        lo = max(0, i - buffer)
        hi = min(n, i + buffer + 1)
        padded[lo:hi] = True

    candidates = []
    run_start = None
    for i in range(n):
        if not padded[i]:
            if run_start is None:
                run_start = i
        else:
            if run_start is not None and i - run_start >= length:
                candidates.append((run_start, i))
            run_start = None
    if run_start is not None and n - run_start >= length:
        candidates.append((run_start, n))

    if not candidates:
        return None
    lo, hi = candidates[rng.integers(0, len(candidates))]
    start = rng.integers(lo, hi - length + 1)
    return start

added_log = []

for cid, block in df.groupby('id_crianca', sort=False):
    block_idx = block.index.to_numpy()
    present_levels = set(block.loc[block['nivel_estresse'] != 'nenhum', 'nivel_estresse'].unique())
    missing = [lvl for lvl in LEVELS if lvl not in present_levels]
    if not missing:
        continue

    child_calm_bpm = df.loc[block_idx, :].loc[df.loc[block_idx, 'estresse'] == 0, 'batimento_cardiaco_bpm'].mean()
    child_calm_eda = df.loc[block_idx, :].loc[df.loc[block_idx, 'estresse'] == 0, 'nivel_suor_uS'].mean()
    offset_bpm = child_calm_bpm - global_calm_bpm
    offset_eda = child_calm_eda - global_calm_eda

    estresse_local = df.loc[block_idx, 'estresse'].to_numpy().copy()

    for lvl in missing:
        start_local = find_free_stretch(estresse_local, EPISODE_LEN, BUFFER, rng)
        if start_local is None:
            print(f'  aviso: {cid} sem espaco livre p/ nivel {lvl}, pulando')
            continue

        global_idx = block_idx[start_local:start_local + EPISODE_LEN]
        env = smooth_envelope(len(global_idx))

        target_bpm = level_stats.loc[lvl, ('batimento_cardiaco_bpm', 'mean')] + offset_bpm
        target_eda = level_stats.loc[lvl, ('nivel_suor_uS', 'mean')] + offset_eda
        target_gyro = level_stats.loc[lvl, ('giroscopio_magnitude_dps', 'mean')]

        base_bpm = child_calm_bpm
        base_eda = child_calm_eda
        base_gyro = df.loc[global_idx, 'giroscopio_magnitude_dps'].mean()

        noise_bpm = rng.normal(0, 2.0, len(global_idx))
        noise_eda = rng.normal(0, 0.3, len(global_idx))

        new_bpm = base_bpm + env * (target_bpm - base_bpm) + noise_bpm
        new_eda = base_eda + env * (target_eda - base_eda) + noise_eda
        new_mag = base_gyro + env * (target_gyro - base_gyro) + rng.normal(0, 3.0, len(global_idx))
        new_mag = np.clip(new_mag, 0.05, None)

        old_mag = df.loc[global_idx, 'giroscopio_magnitude_dps'].to_numpy()
        old_mag_safe = np.where(old_mag < 0.05, 0.05, old_mag)
        scale = new_mag / old_mag_safe

        df.loc[global_idx, 'batimento_cardiaco_bpm'] = np.round(new_bpm).astype(int).clip(55, 190)
        df.loc[global_idx, 'nivel_suor_uS'] = np.round(new_eda, 2).clip(1.0, 20.0)
        for axis in ['giroscopio_x_dps', 'giroscopio_y_dps', 'giroscopio_z_dps']:
            df.loc[global_idx, axis] = np.round(df.loc[global_idx, axis].to_numpy() * scale, 2)
        df.loc[global_idx, 'giroscopio_magnitude_dps'] = np.round(
            np.sqrt(
                df.loc[global_idx, 'giroscopio_x_dps'] ** 2
                + df.loc[global_idx, 'giroscopio_y_dps'] ** 2
                + df.loc[global_idx, 'giroscopio_z_dps'] ** 2
            ),
            2,
        )
        df.loc[global_idx, 'estresse'] = 1
        df.loc[global_idx, 'nivel_estresse'] = lvl

        estresse_local[start_local:start_local + EPISODE_LEN] = 1
        added_log.append((cid, lvl, len(global_idx)))

print('Episodios sinteticos adicionados:')
for cid, lvl, n in added_log:
    print(f'  {cid}: +{lvl} ({n}s)')

# ---- Reconstroi a aba Resumo ----
total = len(df)
n_stress = int((df['estresse'] == 1).sum())
level_counts = df['nivel_estresse'].value_counts()
cmp_calm = df.loc[df['estresse'] == 0, ['batimento_cardiaco_bpm', 'nivel_suor_uS', 'giroscopio_magnitude_dps']].mean()
cmp_stress = df.loc[df['estresse'] == 1, ['batimento_cardiaco_bpm', 'nivel_suor_uS', 'giroscopio_magnitude_dps']].mean()

resumo_rows = [
    ['Resumo - Pulseira de monitoramento de estresse (TEA) | dados sinteticos v2 (cobertura completa)', None, None],
    [None, None, None],
    ['Total de registros', total, None],
    ['Criancas simuladas', df['id_crianca'].nunique(), None],
    ['Faixa etaria', '5 a 12 anos', None],
    ['Frequencia de amostragem', '1 Hz (1 leitura/segundo)', None],
    ['Registros em estresse', n_stress, None],
    ['Prevalencia de estresse', f'{n_stress/total*100:.1f}%', None],
    [None, None, None],
    [None, None, None],
    ['Comparacao: calmo vs estresse (medias)', None, None],
    ['Sinal', 'Sem estresse', 'Em estresse'],
    ['Batimento cardiaco (bpm)', round(cmp_calm['batimento_cardiaco_bpm'], 1), round(cmp_stress['batimento_cardiaco_bpm'], 1)],
    ['Nivel de suor / EDA (uS)', round(cmp_calm['nivel_suor_uS'], 1), round(cmp_stress['nivel_suor_uS'], 1)],
    ['Giroscopio magnitude (dps)', round(cmp_calm['giroscopio_magnitude_dps'], 1), round(cmp_stress['giroscopio_magnitude_dps'], 1)],
    [None, None, None],
    [None, None, None],
    ['Registros por nivel de estresse', None, None],
    ['Nivel', 'Registros', None],
    ['nenhum', int(level_counts.get('nenhum', 0)), None],
    ['leve', int(level_counts.get('leve', 0)), None],
    ['moderado', int(level_counts.get('moderado', 0)), None],
    ['alto', int(level_counts.get('alto', 0)), None],
]
resumo_df = pd.DataFrame(resumo_rows)

dicionario = pd.read_excel(SRC, sheet_name='Dicionario', header=None)

with pd.ExcelWriter(OUT, engine='openpyxl') as writer:
    df.to_excel(writer, sheet_name='Dados', index=False)
    resumo_df.to_excel(writer, sheet_name='Resumo', index=False, header=False)
    dicionario.to_excel(writer, sheet_name='Dicionario', index=False, header=False)

print()
print('Salvo em', OUT)

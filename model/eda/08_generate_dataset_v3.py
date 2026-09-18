"""
Gerador do dataset v3 - PUZZLE BAND.

Diferenca central em relacao ao dataset original (e ao v2, que so corrigia
cobertura de severidade): este gerador constroi a dinamica temporal que
faltava e que o TCC pede explicitamente -

  - Atividade fisica (andar, brincar, correr) eleva BPM/EDA/giroscopio
    GRADUALMENTE e de forma ACOPLADA (rampa de 30-50s entre blocos).
  - Um episodio de estresse real sobe de forma DESACOPLADA do movimento
    (pode acontecer com a crianca parada) e, na maioria dos casos
    (70%), com onset SUBITO (5-15s) - so uma minoria (30%) e onset
    gradual (ansiedade que vai crescendo), pra manter realismo.
  - A recuperacao (decay) apos o pico e sempre mais lenta que a subida,
    como e fisiologicamente esperado (a resposta de estresse relaxa mais
    devagar do que dispara).

Isso torna a feature "bpm_jerk" (velocidade de subida curta vs tendencia
longa) finalmente aprendivel, o que nao acontecia nos datasets anteriores.

Mantem o mesmo schema de 12 colunas do dataset original, pra compatibilidade
com tudo que ja foi construido (model/features.py, dashboard etc).
"""
import numpy as np
import pandas as pd

rng = np.random.default_rng(7)

OUT = '/home/user/puzzle-band/data/raw/dataset_pulseira_TEA_estresse_v3.xlsx'

N_CHILDREN = 12
SESSION_SECONDS = 9000  # 2.5h, igual ao dataset original
START_TS = pd.Timestamp('2026-06-02 09:00:00')
AGES = [12, 9, 9, 6, 10, 8, 11, 7, 8, 11, 8, 5]

ACTIVITIES = ['calmo', 'atividade_leve', 'brincadeira_ativa']
# alvo de cada sinal por atividade, como OFFSET sobre o baseline calmo da propria crianca
ACTIVITY_OFFSETS = {
    'calmo': {'bpm': 0.0, 'eda': 0.0, 'gyro': 5.0},
    'atividade_leve': {'bpm': 15.0, 'eda': 1.1, 'gyro': 48.0},
    # eda deliberadamente alta o suficiente pra se sobrepor a episodios
    # "leve" de estresse (LEVEL_EDA_MEAN['leve']=5.95): exercicio intenso
    # de verdade tambem eleva EDA, nao so estresse. Isso forca o modelo a
    # nao poder confiar so no valor absoluto - precisa da dinamica de
    # subida (onset) e do acoplamento com o giroscopio pra decidir.
    'brincadeira_ativa': {'bpm': 38.0, 'eda': 2.6, 'gyro': 112.0},
}
ACTIVITY_TRANSITION_S = (30, 50)  # rampa entre blocos de atividade normal

LEVELS = ['leve', 'moderado', 'alto']
# incrementos ADITIVOS sobre o nivel de fundo no momento do episodio (nao
# alvos absolutos) - garante que estresse sempre SOBE a partir de onde a
# crianca estava, mesmo que o fundo ja fosse brincadeira_ativa elevada.
LEVEL_BPM_DELTA = {'leve': 11.0, 'moderado': 26.0, 'alto': 38.0}
LEVEL_EDA_DELTA = {'leve': 2.1, 'moderado': 4.3, 'alto': 7.1}
LEVEL_GYRO_MEAN = {'leve': 46.0, 'moderado': 101.0, 'alto': 138.0}

SUDDEN_ONSET_S = (5, 15)
GRADUAL_ONSET_S = (40, 90)
DECAY_S = (30, 60)           # recuperacao sempre mais lenta que a subida
HOLD_MIN_S = 20
P_SUDDEN = 0.7


def cosine_ramp(n):
    if n <= 0:
        return np.array([])
    return 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, n))


def build_activity_track(n_seconds, rng):
    """Sequencia de blocos de atividade normal (sem estresse), com rampas
    graduais de transicao entre blocos - gera bpm/eda/gyro 'de fundo' antes
    de qualquer episodio de estresse ser sobreposto."""
    bpm = np.zeros(n_seconds)
    eda = np.zeros(n_seconds)
    gyro = np.zeros(n_seconds)
    activity_label = np.empty(n_seconds, dtype=object)

    t = 0
    prev_offsets = ACTIVITY_OFFSETS['calmo']
    while t < n_seconds:
        block_len = int(rng.integers(120, 400))
        block_len = min(block_len, n_seconds - t)
        act = rng.choice(ACTIVITIES, p=[0.55, 0.25, 0.20])
        target_offsets = ACTIVITY_OFFSETS[act]

        trans_len = min(int(rng.integers(*ACTIVITY_TRANSITION_S)), block_len)
        env = cosine_ramp(trans_len)
        hold_len = block_len - trans_len

        for key, arr in (('bpm', bpm), ('eda', eda), ('gyro', gyro)):
            start_val = prev_offsets[key]
            end_val = target_offsets[key]
            ramp_vals = start_val + env * (end_val - start_val)
            arr[t:t + trans_len] = ramp_vals
            arr[t + trans_len:t + block_len] = end_val

        activity_label[t:t + block_len] = act
        t += block_len
        prev_offsets = target_offsets

    return bpm, eda, gyro, activity_label


def inject_stress_episodes(bpm_off, eda_off, gyro_off, estresse, nivel, rng,
                            required_levels):
    """Insere episodios de estresse (subitos ou graduais) sobre os offsets
    de atividade de fundo, garantindo que todos os niveis pedidos apareçam
    pelo menos uma vez."""
    n = len(bpm_off)
    used = np.zeros(n, dtype=bool)
    BUFFER = 60

    def find_slot(length):
        free = ~used
        candidates = []
        run_start = None
        for i in range(n):
            if free[i]:
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
        return int(rng.integers(lo, hi - length + 1))

    episodes = []

    # garante cobertura: 1 episodio de cada nivel pedido
    for lvl in required_levels:
        sudden = rng.random() < P_SUDDEN
        onset = int(rng.integers(*SUDDEN_ONSET_S)) if sudden else int(rng.integers(*GRADUAL_ONSET_S))
        decay = int(rng.integers(*DECAY_S))
        hold = int(rng.integers(HOLD_MIN_S, HOLD_MIN_S + 80))
        length = onset + hold + decay
        start = find_slot(length + BUFFER)
        if start is None:
            continue
        episodes.append((start, onset, hold, decay, lvl, sudden))
        used[max(0, start - BUFFER):min(n, start + length + BUFFER)] = True

    # episodios extras aleatorios pra dar volume realista (2 a 4 por crianca)
    for _ in range(int(rng.integers(2, 5))):
        lvl = rng.choice(LEVELS, p=[0.5, 0.35, 0.15])
        sudden = rng.random() < P_SUDDEN
        onset = int(rng.integers(*SUDDEN_ONSET_S)) if sudden else int(rng.integers(*GRADUAL_ONSET_S))
        decay = int(rng.integers(*DECAY_S))
        hold = int(rng.integers(HOLD_MIN_S, HOLD_MIN_S + 80))
        length = onset + hold + decay
        start = find_slot(length + BUFFER)
        if start is None:
            continue
        episodes.append((start, onset, hold, decay, lvl, sudden))
        used[max(0, start - BUFFER):min(n, start + length + BUFFER)] = True

    for start, onset, hold, decay, lvl, sudden in episodes:
        length = onset + hold + decay
        idx = np.arange(start, start + length)

        up = cosine_ramp(onset)
        down = cosine_ramp(decay)[::-1]
        env = np.concatenate([up, np.ones(hold), down])[:length]

        # jitter no incremento: episodios "leve" nem sempre sobem o mesmo
        # tanto - as vezes ficam mais brandos, sobrepondo de verdade a
        # faixa de exercicio intenso (isso e o que torna a dinamica de
        # subida (onset subito) necessaria pro modelo, nao so decorativa).
        bpm_delta_peak = max(3.0, LEVEL_BPM_DELTA[lvl] + rng.normal(0, 5))
        eda_delta_peak = max(0.5, LEVEL_EDA_DELTA[lvl] + rng.normal(0, 0.8))

        base_bpm_here = bpm_off[start]  # nivel de atividade de fundo no momento
        base_eda_here = eda_off[start]

        # estresse e SEMPRE um incremento sobre o que ja estava acontecendo
        # (nunca uma queda, mesmo se o fundo ja for brincadeira_ativa
        # elevada) - e por isso desacoplado do NIVEL de atividade, mas
        # continua sendo uma subida real em cima dele.
        bpm_off[idx] = base_bpm_here + env * bpm_delta_peak
        eda_off[idx] = base_eda_here + env * eda_delta_peak

        # giroscopio durante estresse: 50% fica "congelado" no nivel de
        # fundo (crise interna, parada), 50% tem uma agitacao parcial
        # ligada a severidade (mas sem igualar brincadeira vigorosa)
        if rng.random() < 0.5:
            pass  # gyro_off already at background level, no override
        else:
            gyro_peak = LEVEL_GYRO_MEAN[lvl] * rng.uniform(0.3, 0.9)
            base_gyro_here = gyro_off[start]
            gyro_off[idx] = base_gyro_here + env * (gyro_peak - base_gyro_here)

        estresse[idx] = 1
        nivel[idx] = lvl

    return episodes


def main():
    rows = []
    all_episode_log = []

    for i in range(N_CHILDREN):
        cid = f'C{i+1:02d}'
        idade = AGES[i]
        child_rng = np.random.default_rng(rng.integers(0, 2**31 - 1))

        baseline_bpm = float(np.clip(child_rng.normal(92, 8), 70, 115))
        baseline_eda = float(np.clip(child_rng.normal(3.9, 0.8), 2.2, 6.0))

        bpm_off, eda_off, gyro_off, activity_label = build_activity_track(SESSION_SECONDS, child_rng)

        estresse = np.zeros(SESSION_SECONDS, dtype=int)
        nivel = np.full(SESSION_SECONDS, 'nenhum', dtype=object)

        episodes = inject_stress_episodes(
            bpm_off, eda_off, gyro_off, estresse, nivel, child_rng,
            required_levels=LEVELS,
        )
        all_episode_log.append((cid, episodes))

        bpm = baseline_bpm + bpm_off + child_rng.normal(0, 2.2, SESSION_SECONDS)
        eda = baseline_eda + eda_off + child_rng.normal(0, 0.25, SESSION_SECONDS)
        gyro_mag = np.clip(gyro_off * (0.4 + child_rng.random(SESSION_SECONDS) * 1.3), 0.05, 950)

        bpm = np.clip(np.round(bpm), 50, 190).astype(int)
        eda = np.round(np.clip(eda, 1.0, 20.0), 2)
        gyro_mag = np.round(gyro_mag, 2)

        # decompoe a magnitude do giroscopio em x/y/z com direcao aleatoria
        theta = child_rng.uniform(0, np.pi, SESSION_SECONDS)
        phi = child_rng.uniform(0, 2 * np.pi, SESSION_SECONDS)
        gx = np.round(gyro_mag * np.sin(theta) * np.cos(phi), 2)
        gy = np.round(gyro_mag * np.sin(theta) * np.sin(phi), 2)
        gz = np.round(gyro_mag * np.cos(theta), 2)
        gyro_mag_recomputed = np.round(np.sqrt(gx**2 + gy**2 + gz**2), 2)

        timestamps = pd.date_range(START_TS, periods=SESSION_SECONDS, freq='s')

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
        rows.append(child_df)

        n_sudden = sum(1 for e in episodes if e[5])
        n_gradual = len(episodes) - n_sudden
        print(f'{cid}: baseline_bpm={baseline_bpm:.1f} baseline_eda={baseline_eda:.2f} '
              f'episodios={len(episodes)} (subitos={n_sudden}, graduais={n_gradual})')

    df = pd.concat(rows, ignore_index=True)

    total = len(df)
    n_stress = int((df['estresse'] == 1).sum())
    level_counts = df['nivel_estresse'].value_counts()
    cmp_calm = df.loc[df['estresse'] == 0, ['batimento_cardiaco_bpm', 'nivel_suor_uS', 'giroscopio_magnitude_dps']].mean()
    cmp_stress = df.loc[df['estresse'] == 1, ['batimento_cardiaco_bpm', 'nivel_suor_uS', 'giroscopio_magnitude_dps']].mean()

    resumo_rows = [
        ['Resumo - Pulseira de monitoramento de estresse (TEA) | dados sinteticos v3', None, None],
        ['Novidade da v3: episodios de estresse com onset subito (5-15s, maioria) vs', None, None],
        ['onset gradual (40-90s, minoria), desacoplados do nivel de atividade fisica.', None, None],
        [None, None, None],
        ['Total de registros', total, None],
        ['Criancas simuladas', df['id_crianca'].nunique(), None],
        ['Faixa etaria', '5 a 12 anos', None],
        ['Frequencia de amostragem', '1 Hz (1 leitura/segundo)', None],
        ['Registros em estresse', n_stress, None],
        ['Prevalencia de estresse', f'{n_stress/total*100:.1f}%', None],
        [None, None, None],
        ['Comparacao: calmo vs estresse (medias)', None, None],
        ['Sinal', 'Sem estresse', 'Em estresse'],
        ['Batimento cardiaco (bpm)', round(cmp_calm['batimento_cardiaco_bpm'], 1), round(cmp_stress['batimento_cardiaco_bpm'], 1)],
        ['Nivel de suor / EDA (uS)', round(cmp_calm['nivel_suor_uS'], 1), round(cmp_stress['nivel_suor_uS'], 1)],
        ['Giroscopio magnitude (dps)', round(cmp_calm['giroscopio_magnitude_dps'], 1), round(cmp_stress['giroscopio_magnitude_dps'], 1)],
        [None, None, None],
        ['Registros por nivel de estresse', None, None],
        ['Nivel', 'Registros', None],
        ['nenhum', int(level_counts.get('nenhum', 0)), None],
        ['leve', int(level_counts.get('leve', 0)), None],
        ['moderado', int(level_counts.get('moderado', 0)), None],
        ['alto', int(level_counts.get('alto', 0)), None],
    ]
    resumo_df = pd.DataFrame(resumo_rows)

    dicionario_rows = [
        ['Dicionario de dados', None, None],
        ['Coluna', 'Descricao', 'Unidade / valores'],
        ['timestamp', 'Data e hora da leitura', 'AAAA-MM-DD HH:MM:SS'],
        ['id_crianca', 'Identificador anonimo da crianca', 'C01 a C12'],
        ['idade', 'Idade da crianca', 'anos (5-12)'],
        ['atividade', 'Atividade fisica no momento', 'calmo / atividade_leve / brincadeira_ativa'],
        ['batimento_cardiaco_bpm', 'Frequencia cardiaca', 'batimentos por minuto'],
        ['nivel_suor_uS', 'Atividade eletrodermica (EDA / condutancia da pele)', 'microsiemens (uS)'],
        ['giroscopio_x_dps', 'Velocidade angular no eixo X', 'graus por segundo'],
        ['giroscopio_y_dps', 'Velocidade angular no eixo Y', 'graus por segundo'],
        ['giroscopio_z_dps', 'Velocidade angular no eixo Z', 'graus por segundo'],
        ['giroscopio_magnitude_dps', 'Magnitude do movimento = raiz(x^2+y^2+z^2)', 'graus por segundo'],
        ['estresse', 'Rotulo-alvo: indica episodio de estresse', '0 = nao / 1 = sim'],
        ['nivel_estresse', 'Intensidade do episodio de estresse', 'nenhum / leve / moderado / alto'],
        [None, None, None],
        ['Nota v3', 'Episodios de estresse tem onset subito (~70%, 5-15s) ou', 'gradual (~30%, 40-90s); giroscopio deliberadamente'],
        [None, 'desacoplado do BPM/EDA em boa parte dos episodios,', 'pra permitir crise sem movimento visivel.'],
    ]
    dicionario_df = pd.DataFrame(dicionario_rows)

    with pd.ExcelWriter(OUT, engine='openpyxl') as writer:
        df.to_excel(writer, sheet_name='Dados', index=False)
        resumo_df.to_excel(writer, sheet_name='Resumo', index=False, header=False)
        dicionario_df.to_excel(writer, sheet_name='Dicionario', index=False, header=False)

    print()
    print('Salvo em', OUT)
    print(f'Total: {total} registros, {n_stress} em estresse ({n_stress/total*100:.1f}%)')


if __name__ == '__main__':
    main()

"""
Gerador do dataset v4 - PUZZLE BAND.

Extensao do v3 (mesma dinamica de onset subito/gradual, estresse
desacoplado de movimento) com 4 grupos de sinais novos:

  - HRV (variabilidade da freq. cardiaca, RMSSD em ms) - cai um pouco com
    atividade fisica (acoplado ao offset de atividade), mas cai MUITO MAIS
    durante um episodio de estresse real - a resposta vagal e tipicamente
    mais rapida e mais forte que a simples proporcionalidade com o BPM.
  - Acelerometro (magnitude, g) + indice de regularidade do movimento
    (0-1) - a regularidade fica ALTA especificamente quando o episodio de
    estresse vem acompanhado de agitacao motora visivel (a mesma logica
    que ja decide se o giroscopio "congela" ou sobe durante um episodio),
    representando estereotipias (balanco, bater maos) - um sinal
    fisiologicamente distinto de "correr" (movimento alto, mas IRREGULAR).
    Como a amostragem e 1Hz, nao reconstruimos a forma de onda de alta
    frequencia (1-5Hz tipico de estereotipia) - simulamos direto o indice
    resumido, como um MPU6050 real reportaria apos analise a bordo.
  - Sensores ambientais (luminosidade em lux, ruido em dB) - contexto que,
    em cerca de 40% dos episodios, tem um pico coincidente (gatilho
    plausivel); nos outros 60% nao ha correlato ambiental (crise sem causa
    externa obvia, tao realista quanto a outra situacao).

O schema de bpm/eda/gyro (constantes, timing dos episodios) e o MESMO do
v3, propositalmente, pra manter tudo que ja foi validado.
"""
import numpy as np
import pandas as pd

rng = np.random.default_rng(11)

OUT = '/home/user/puzzle-band/data/raw/dataset_pulseira_TEA_estresse_v4.xlsx'

N_CHILDREN = 12
SESSION_SECONDS = 9000
START_TS = pd.Timestamp('2026-06-02 09:00:00')
AGES = [12, 9, 9, 6, 10, 8, 11, 7, 8, 11, 8, 5]

ACTIVITIES = ['calmo', 'atividade_leve', 'brincadeira_ativa']
ACTIVITY_OFFSETS = {
    'calmo': {'bpm': 0.0, 'eda': 0.0, 'gyro': 5.0},
    'atividade_leve': {'bpm': 15.0, 'eda': 1.1, 'gyro': 48.0},
    'brincadeira_ativa': {'bpm': 38.0, 'eda': 2.6, 'gyro': 112.0},
}
ACTIVITY_TRANSITION_S = (30, 50)

LEVELS = ['leve', 'moderado', 'alto']
LEVEL_BPM_DELTA = {'leve': 11.0, 'moderado': 26.0, 'alto': 38.0}
LEVEL_EDA_DELTA = {'leve': 2.1, 'moderado': 4.3, 'alto': 7.1}
LEVEL_GYRO_MEAN = {'leve': 46.0, 'moderado': 101.0, 'alto': 138.0}
# quanto a HRV cai (ms) ALEM do que a proporcionalidade com o BPM ja
# explicaria - e o "bonus" de queda especifico de estresse agudo
LEVEL_HRV_EXTRA_DROP = {'leve': 15.0, 'moderado': 22.0, 'alto': 30.0}

SUDDEN_ONSET_S = (5, 15)
GRADUAL_ONSET_S = (40, 90)
DECAY_S = (30, 60)
HOLD_MIN_S = 20
P_SUDDEN = 0.7
P_GYRO_BUMP = 0.5   # chance de agitacao motora visivel durante o episodio
P_AMBIENT_TRIGGER = 0.4  # chance de pico ambiental coincidente

HRV_ACTIVITY_COUPLING = 0.35  # quanto a HRV cai por bpm de atividade fisica


def cosine_ramp(n):
    if n <= 0:
        return np.array([])
    return 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, n))


def build_activity_track(n_seconds, rng):
    bpm = np.zeros(n_seconds)
    eda = np.zeros(n_seconds)
    gyro = np.zeros(n_seconds)
    activity_label = np.empty(n_seconds, dtype=object)

    t = 0
    prev_offsets = ACTIVITY_OFFSETS['calmo']
    while t < n_seconds:
        block_len = min(int(rng.integers(120, 400)), n_seconds - t)
        act = rng.choice(ACTIVITIES, p=[0.55, 0.25, 0.20])
        target_offsets = ACTIVITY_OFFSETS[act]

        trans_len = min(int(rng.integers(*ACTIVITY_TRANSITION_S)), block_len)
        env = cosine_ramp(trans_len)

        for key, arr in (('bpm', bpm), ('eda', eda), ('gyro', gyro)):
            start_val = prev_offsets[key]
            end_val = target_offsets[key]
            arr[t:t + trans_len] = start_val + env * (end_val - start_val)
            arr[t + trans_len:t + block_len] = end_val

        activity_label[t:t + block_len] = act
        t += block_len
        prev_offsets = target_offsets

    return bpm, eda, gyro, activity_label


def find_slot(used, length, rng):
    n = len(used)
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


def plan_episodes(n, rng, required_levels):
    """So decide TIMING e METADADOS dos episodios (sem aplicar aos sinais
    ainda) - assim todos os sensores usam exatamente a mesma janela."""
    used = np.zeros(n, dtype=bool)
    BUFFER = 60
    episodes = []

    def add_episode(lvl):
        sudden = rng.random() < P_SUDDEN
        onset = int(rng.integers(*SUDDEN_ONSET_S)) if sudden else int(rng.integers(*GRADUAL_ONSET_S))
        decay = int(rng.integers(*DECAY_S))
        hold = int(rng.integers(HOLD_MIN_S, HOLD_MIN_S + 80))
        length = onset + hold + decay
        start = find_slot(used, length + BUFFER, rng)
        if start is None:
            return
        gyro_bump = rng.random() < P_GYRO_BUMP
        ambient_trigger = rng.random() < P_AMBIENT_TRIGGER
        episodes.append({
            'start': start, 'onset': onset, 'hold': hold, 'decay': decay,
            'lvl': lvl, 'sudden': sudden, 'gyro_bump': gyro_bump,
            'ambient_trigger': ambient_trigger,
        })
        used[max(0, start - BUFFER):min(n, start + length + BUFFER)] = True

    for lvl in required_levels:
        add_episode(lvl)
    for _ in range(int(rng.integers(2, 5))):
        add_episode(rng.choice(LEVELS, p=[0.5, 0.35, 0.15]))

    return episodes


def main():
    rows = []

    for i in range(N_CHILDREN):
        cid = f'C{i+1:02d}'
        idade = AGES[i]
        child_rng = np.random.default_rng(rng.integers(0, 2**31 - 1))

        baseline_bpm = float(np.clip(child_rng.normal(92, 8), 70, 115))
        baseline_eda = float(np.clip(child_rng.normal(3.9, 0.8), 2.2, 6.0))
        baseline_hrv = float(np.clip(child_rng.normal(55, 12), 25, 90))
        baseline_luz = float(np.clip(child_rng.normal(320, 90), 80, 700))
        baseline_ruido = float(np.clip(child_rng.normal(45, 8), 25, 70))

        bpm_off, eda_off, gyro_off, activity_label = build_activity_track(SESSION_SECONDS, child_rng)
        bpm_off_activity_only = bpm_off.copy()  # antes de episodios - usado pra acoplar a HRV

        hrv_off = np.zeros(SESSION_SECONDS)
        accel_reg = np.zeros(SESSION_SECONDS)   # 0-1, indice de regularidade
        # trilha ambiental propria (independente de atividade fisica) -
        # bloco/rampa igual as outras, mas com offsets proprios de luz/ruido
        luz_off = np.zeros(SESSION_SECONDS)
        ruido_off = np.zeros(SESSION_SECONDS)
        t = 0
        prev_luz, prev_ruido = 0.0, 0.0
        while t < SESSION_SECONDS:
            block_len = min(int(child_rng.integers(200, 600)), SESSION_SECONDS - t)
            target_luz = float(child_rng.normal(0, 60))
            target_ruido = float(child_rng.normal(0, 6))
            trans_len = min(int(child_rng.integers(40, 80)), block_len)
            env = cosine_ramp(trans_len)
            luz_off[t:t + trans_len] = prev_luz + env * (target_luz - prev_luz)
            luz_off[t + trans_len:t + block_len] = target_luz
            ruido_off[t:t + trans_len] = prev_ruido + env * (target_ruido - prev_ruido)
            ruido_off[t + trans_len:t + block_len] = target_ruido
            t += block_len
            prev_luz, prev_ruido = target_luz, target_ruido

        estresse = np.zeros(SESSION_SECONDS, dtype=int)
        nivel = np.full(SESSION_SECONDS, 'nenhum', dtype=object)

        episodes = plan_episodes(SESSION_SECONDS, child_rng, LEVELS)

        for ep in episodes:
            start, onset, hold, decay = ep['start'], ep['onset'], ep['hold'], ep['decay']
            lvl, sudden = ep['lvl'], ep['sudden']
            length = onset + hold + decay
            idx = np.arange(start, start + length)

            up = cosine_ramp(onset)
            down = cosine_ramp(decay)[::-1]
            env = np.concatenate([up, np.ones(hold), down])[:length]

            bpm_delta_peak = max(3.0, LEVEL_BPM_DELTA[lvl] + child_rng.normal(0, 5))
            eda_delta_peak = max(0.5, LEVEL_EDA_DELTA[lvl] + child_rng.normal(0, 0.8))

            base_bpm_here = bpm_off[start]
            base_eda_here = eda_off[start]
            bpm_off[idx] = base_bpm_here + env * bpm_delta_peak
            eda_off[idx] = base_eda_here + env * eda_delta_peak

            # HRV: cai o "bonus" especifico de estresse, com a MESMA forma
            # temporal do episodio (onset subito/gradual, decay lento)
            hrv_extra = LEVEL_HRV_EXTRA_DROP[lvl] + child_rng.normal(0, 3)
            hrv_off[idx] += -env * max(2.0, hrv_extra)

            if ep['gyro_bump']:
                gyro_peak = LEVEL_GYRO_MEAN[lvl] * child_rng.uniform(0.3, 0.9)
                base_gyro_here = gyro_off[start]
                gyro_off[idx] = base_gyro_here + env * (gyro_peak - base_gyro_here)
                # agitacao motora visivel e tipicamente mais REGULAR
                # (estereotipia) do que movimento de brincadeira livre
                accel_reg[idx] = np.maximum(accel_reg[idx], env * child_rng.uniform(0.65, 0.95))

            if ep['ambient_trigger']:
                # pico ambiental coincidente (gatilho provavel) - comeca um
                # pouco antes do episodio e decai mais rapido
                trig_len = min(length, onset + 30)
                trig_env = cosine_ramp(trig_len)
                trig_idx = idx[:trig_len]
                luz_off[trig_idx] += trig_env * child_rng.uniform(200, 500)
                ruido_off[trig_idx] += trig_env * child_rng.uniform(15, 35)

            estresse[idx] = 1
            nivel[idx] = lvl

        # HRV: componente continuo ligado ao nivel de atividade fisica
        # (usa so o offset de ATIVIDADE, sem os episodios, pra nao dobrar
        # contagem - a queda especifica de estresse ja foi somada acima)
        hrv_off += -HRV_ACTIVITY_COUPLING * bpm_off_activity_only

        bpm = baseline_bpm + bpm_off + child_rng.normal(0, 2.2, SESSION_SECONDS)
        eda = baseline_eda + eda_off + child_rng.normal(0, 0.25, SESSION_SECONDS)
        gyro_mag = np.clip(gyro_off * (0.4 + child_rng.random(SESSION_SECONDS) * 1.3), 0.05, 950)
        hrv = np.clip(baseline_hrv + hrv_off + child_rng.normal(0, 3.0, SESSION_SECONDS), 8, 120)
        luz = np.clip(baseline_luz + luz_off + child_rng.normal(0, 15, SESSION_SECONDS), 5, 2000)
        ruido = np.clip(baseline_ruido + ruido_off + child_rng.normal(0, 2.0, SESSION_SECONDS), 20, 110)

        # acelerometro: correlacionado ao giroscopio (mesmo movimento
        # fisico), com ruido proprio e independente
        accel_mag = np.clip(gyro_mag * 0.55 * (0.5 + child_rng.random(SESSION_SECONDS) * 1.1), 0.02, 20)
        # fora de episodios com agitacao marcada, regularidade e baixa e
        # ruidosa (movimento livre nao e periodico)
        accel_reg = np.clip(accel_reg + child_rng.uniform(0, 0.15, SESSION_SECONDS), 0, 1)

        bpm = np.clip(np.round(bpm), 50, 190).astype(int)
        eda = np.round(np.clip(eda, 1.0, 20.0), 2)
        gyro_mag = np.round(gyro_mag, 2)
        hrv = np.round(hrv, 1)
        luz = np.round(luz, 0)
        ruido = np.round(ruido, 1)
        accel_mag = np.round(accel_mag, 2)
        accel_reg = np.round(accel_reg, 2)

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
            'hrv_rmssd_ms': hrv,
            'acelerometro_magnitude_g': accel_mag,
            'movimento_regularidade': accel_reg,
            'luminosidade_lux': luz,
            'ruido_db': ruido,
            'estresse': estresse,
            'nivel_estresse': nivel,
        })
        rows.append(child_df)

        n_sudden = sum(1 for e in episodes if e['sudden'])
        n_ambient = sum(1 for e in episodes if e['ambient_trigger'])
        print(f'{cid}: bpm0={baseline_bpm:.1f} hrv0={baseline_hrv:.1f} episodios={len(episodes)} '
              f'(subitos={n_sudden}, com gatilho ambiental={n_ambient})')

    df = pd.concat(rows, ignore_index=True)

    total = len(df)
    n_stress = int((df['estresse'] == 1).sum())
    level_counts = df['nivel_estresse'].value_counts()
    calm = df[df['estresse'] == 0]
    stress = df[df['estresse'] == 1]
    sig_cols = ['batimento_cardiaco_bpm', 'nivel_suor_uS', 'giroscopio_magnitude_dps',
                'hrv_rmssd_ms', 'acelerometro_magnitude_g', 'movimento_regularidade']

    resumo_rows = [
        ['Resumo - Pulseira de monitoramento de estresse (TEA) | dados sinteticos v4', None, None],
        ['Novidade da v4: HRV, acelerometro + regularidade de movimento,', None, None],
        ['sensores ambientais (luz/ruido) - alem da dinamica onset subito/gradual do v3.', None, None],
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
    ] + [
        [col, round(calm[col].mean(), 2), round(stress[col].mean(), 2)] for col in sig_cols
    ] + [
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
        ['hrv_rmssd_ms', 'Variabilidade da freq. cardiaca (RMSSD)', 'milissegundos - cai com estresse/esforco'],
        ['acelerometro_magnitude_g', 'Aceleracao linear dinamica (MPU6050)', 'g (gravidades)'],
        ['movimento_regularidade', 'Indice de periodicidade do movimento (analise a bordo, 1Hz resumido)', '0 (irregular) a 1 (muito regular/repetitivo)'],
        ['luminosidade_lux', 'Luminosidade ambiente', 'lux'],
        ['ruido_db', 'Nivel de ruido ambiente', 'decibeis (dB)'],
        ['estresse', 'Rotulo-alvo: indica episodio de estresse', '0 = nao / 1 = sim'],
        ['nivel_estresse', 'Intensidade do episodio de estresse', 'nenhum / leve / moderado / alto'],
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

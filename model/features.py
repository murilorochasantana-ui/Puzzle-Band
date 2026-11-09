"""
Engenharia de features para o modelo preditivo do Puzzle Band.

Historico (dataset v3): testamos uma feature de INCLINACAO curta vs longa
do batimento ("bpm_jerk") pra distinguir subida subita (estresse) de
subida gradual (exercicio). A feature existe e funciona no instante exato
do inicio de um episodio (ver docs/modelo.md), mas tem peso agregado
baixo porque esse instante e uma fatia pequena do total de segundos
rotulados como estresse.

O que decide a maior parte da classificacao no dataset v3 e a relacao
entre BPM/EDA e o nivel de MOVIMENTO (giroscopio): atividade fisica eleva
os tres sinais JUNTOS; estresse real eleva BPM/EDA mesmo com a crianca
parada. Essa v4 adiciona 4 grupos de features novos pra reforcar esse tipo
de raciocinio com sinais fisiologicamente mais especificos:

  - HRV (variabilidade da frequencia cardiaca) - cai tanto com esforco
    fisico quanto com estresse, mas cai de forma mais ABRUPTA e mais
    PRONUNCIADA no estresse agudo (retirada vagal e frequentemente a
    primeira resposta, antes mesmo do BPM subir visivelmente).
  - Acelerometro + indice de regularidade do movimento - o MPU6050 tem
    acelerometro alem do giroscopio; a "regularidade" e um indice (0-1)
    que representaria, num sistema real, uma analise de periodicidade
    feita a bordo em alta frequencia (dezenas de Hz) e transmitida so
    como um resumo a 1Hz junto com o resto - a 1Hz de amostragem nao da
    pra reconstruir a frequencia real de um "estereotipia" motora
    (tipicamente 1-5Hz), entao nao simulamos a forma de onda, so o indice
    resumido, como o hardware real faria.
  - Sensores ambientais (luminosidade, ruido) - contexto que pode ajudar a
    apontar um GATILHO provavel, nao so detectar o efeito.
  - Tempo acumulado em estado elevado - quantos dos ultimos 30s o BPM
    ficou consistentemente acima da propria tendencia recente (streak),
    pra distinguir um pico passageiro de um estado que esta se sustentando.
"""
import numpy as np
import pandas as pd

SHORT_WINDOW = 5    # segundos - detecta salto subito
LONG_WINDOW = 30     # segundos - detecta tendencia/rampa gradual

FEATURE_COLUMNS = [
    'bpm', 'bpm_mean_long', 'bpm_slope_short', 'bpm_slope_long', 'bpm_jerk', 'bpm_tempo_elevado',
    'eda', 'eda_mean_long', 'eda_slope_long',
    'gyro_mag', 'gyro_mean_long', 'gyro_slope_long',
    'hrv', 'hrv_mean_long', 'hrv_slope_long',
    'accel_mag', 'accel_mean_long', 'regularidade_mean_long',
    'luz', 'luz_mean_long', 'ruido', 'ruido_mean_long', 'ruido_slope_long',
    'idade',
]

# Features com MEMORIA (hipotese da subida subita x gradual, ver
# docs/modelo.md). Calculadas sempre; so entram no modelo se estiverem na
# lista de features do treino. Mesmas contas em frontend/src/model/predict.js.
MEMORY_WINDOW = 90       # segundos de memoria
SMOOTH_WINDOW = 5        # media curta do BPM e do giroscopio
BPM_PER_GYRO = 0.34      # bpm por dps no exercicio do dataset v4 (+38 bpm / +112 dps)
MIN_RISE_BPM = 10.0      # subida menor que isso nao conta como subida
MEMORY_FEATURES = ['bpm_jerk_max_90', 'bpm_excesso_mov', 'bpm_tempo_subida']


def _mean_in_order(values: np.ndarray, window: int) -> np.ndarray:
    """Media movel somando na ordem (mais antiga -> mais recente), igual ao
    reduce do predict.js, para os dois darem o mesmo numero. NaN antes de
    ter `window` amostras."""
    n = len(values)
    out = np.full(n, np.nan)
    if n >= window:
        total = np.zeros(n - window + 1)
        for k in range(window):
            total = total + values[k:n - window + 1 + k]
        out[window - 1:] = total / window
    return out


def _memory_features(bpm: np.ndarray, gyro: np.ndarray, jerk: np.ndarray):
    """As 3 features de memoria de uma crianca (arrays na ordem do tempo).
    Em cada instante i, olham os ultimos MEMORY_WINDOW segundos (menos no
    comeco da sessao, quando ha menos historico):
      bpm_jerk_max_90  - o maior bpm_jerk da janela (a subida subita deixa
                         marca por 90 s, nao so nos 5-15 s em que acontece);
      bpm_excesso_mov  - quanto a media de 5 s do BPM esta acima do menor
                         valor dela na janela, descontado o que a subida do
                         giroscopio (mesma conta) explicaria: BPM_PER_GYRO;
      bpm_tempo_subida - segundos entre 20% e 80% da subida ate o pico mais
                         recente da janela (MEMORY_WINDOW se a subida for
                         menor que MIN_RISE_BPM)."""
    n = len(bpm)
    s_bpm = _mean_in_order(bpm, SMOOTH_WINDOW)
    s_gyro = _mean_in_order(gyro, SMOOTH_WINDOW)
    jerk_max = np.full(n, np.nan)
    excesso = np.full(n, np.nan)
    tempo = np.full(n, np.nan)
    for i in range(n):
        lo = max(0, i - MEMORY_WINDOW + 1)
        j = jerk[lo:i + 1]
        j = j[~np.isnan(j)]
        if len(j):
            jerk_max[i] = j.max()
        w = s_bpm[lo:i + 1]
        g = s_gyro[lo:i + 1]
        ok = ~np.isnan(w)
        w, g = w[ok], g[ok]
        if not len(w):
            continue
        excesso[i] = (w[-1] - w.min()) - BPM_PER_GYRO * (g[-1] - g.min())
        p = len(w) - 1 - int(np.argmax(w[::-1]))  # pico mais recente
        base = w[:p + 1].min()
        rise = w[p] - base
        if rise < MIN_RISE_BPM:
            tempo[i] = MEMORY_WINDOW
            continue
        abaixo = np.nonzero(w[:p + 1] <= base + 0.2 * rise)[0]
        t_lo = int(abaixo[-1])
        acima = np.nonzero(w[t_lo:p + 1] >= base + 0.8 * rise)[0]
        tempo[i] = int(acima[0])
    return jerk_max, excesso, tempo


def _rolling_streak_above_trend(values: np.ndarray, window: int, min_margin: float, margin_frac_std: float) -> np.ndarray:
    """Pra cada posicao i (com pelo menos `window` amostras de historico),
    conta quantos segundos CONSECUTIVOS, olhando pra tras a partir de i,
    o valor ficou acima da media da propria janela + uma margem (a maior
    entre `min_margin` e uma fracao do desvio-padrao da janela). Streak
    zera assim que encontra uma amostra nao-elevada. NaN se nao ha janela
    completa ainda."""
    n = len(values)
    out = np.full(n, np.nan)
    for i in range(window - 1, n):
        win = values[i - window + 1:i + 1]
        mean = win.mean()
        margin = max(min_margin, margin_frac_std * win.std())
        threshold = mean + margin
        streak = 0
        for j in range(i, i - window, -1):
            if j < 0 or values[j] <= threshold:
                break
            streak += 1
        out[i] = streak
    return out


def build_features(df: pd.DataFrame) -> pd.DataFrame:
    """Recebe o dataframe cru (colunas em portugues do dataset) ordenado por
    crianca+tempo e devolve um dataframe so com as features do modelo,
    calculadas *por crianca* (nunca vaza dado entre criancas diferentes)."""

    df = df.sort_values(['id_crianca', 'timestamp']).reset_index(drop=True)
    out = pd.DataFrame(index=df.index)

    g_bpm = df.groupby('id_crianca')['batimento_cardiaco_bpm']
    g_eda = df.groupby('id_crianca')['nivel_suor_uS']
    g_gyro = df.groupby('id_crianca')['giroscopio_magnitude_dps']
    g_hrv = df.groupby('id_crianca')['hrv_rmssd_ms']
    g_accel = df.groupby('id_crianca')['acelerometro_magnitude_g']
    g_reg = df.groupby('id_crianca')['movimento_regularidade']
    g_luz = df.groupby('id_crianca')['luminosidade_lux']
    g_ruido = df.groupby('id_crianca')['ruido_db']

    out['bpm'] = df['batimento_cardiaco_bpm']
    out['bpm_mean_long'] = g_bpm.transform(lambda s: s.rolling(LONG_WINDOW, min_periods=LONG_WINDOW).mean())
    bpm_lag_short = g_bpm.transform(lambda s: s.shift(SHORT_WINDOW))
    bpm_lag_long = g_bpm.transform(lambda s: s.shift(LONG_WINDOW))
    out['bpm_slope_short'] = (df['batimento_cardiaco_bpm'] - bpm_lag_short) / SHORT_WINDOW
    out['bpm_slope_long'] = (df['batimento_cardiaco_bpm'] - bpm_lag_long) / LONG_WINDOW
    out['bpm_jerk'] = out['bpm_slope_short'] - out['bpm_slope_long']
    out['bpm_tempo_elevado'] = g_bpm.transform(
        lambda s: pd.Series(
            _rolling_streak_above_trend(s.to_numpy(dtype=float), LONG_WINDOW, min_margin=5.0, margin_frac_std=0.5),
            index=s.index,
        )
    )

    out['eda'] = df['nivel_suor_uS']
    out['eda_mean_long'] = g_eda.transform(lambda s: s.rolling(LONG_WINDOW, min_periods=LONG_WINDOW).mean())
    eda_lag_long = g_eda.transform(lambda s: s.shift(LONG_WINDOW))
    out['eda_slope_long'] = (df['nivel_suor_uS'] - eda_lag_long) / LONG_WINDOW

    out['gyro_mag'] = df['giroscopio_magnitude_dps']
    out['gyro_mean_long'] = g_gyro.transform(lambda s: s.rolling(LONG_WINDOW, min_periods=LONG_WINDOW).mean())
    gyro_lag_long = g_gyro.transform(lambda s: s.shift(LONG_WINDOW))
    out['gyro_slope_long'] = (df['giroscopio_magnitude_dps'] - gyro_lag_long) / LONG_WINDOW

    out['hrv'] = df['hrv_rmssd_ms']
    out['hrv_mean_long'] = g_hrv.transform(lambda s: s.rolling(LONG_WINDOW, min_periods=LONG_WINDOW).mean())
    hrv_lag_long = g_hrv.transform(lambda s: s.shift(LONG_WINDOW))
    out['hrv_slope_long'] = (df['hrv_rmssd_ms'] - hrv_lag_long) / LONG_WINDOW

    out['accel_mag'] = df['acelerometro_magnitude_g']
    out['accel_mean_long'] = g_accel.transform(lambda s: s.rolling(LONG_WINDOW, min_periods=LONG_WINDOW).mean())
    out['regularidade_mean_long'] = g_reg.transform(lambda s: s.rolling(LONG_WINDOW, min_periods=LONG_WINDOW).mean())

    out['luz'] = df['luminosidade_lux']
    out['luz_mean_long'] = g_luz.transform(lambda s: s.rolling(LONG_WINDOW, min_periods=LONG_WINDOW).mean())
    out['ruido'] = df['ruido_db']
    out['ruido_mean_long'] = g_ruido.transform(lambda s: s.rolling(LONG_WINDOW, min_periods=LONG_WINDOW).mean())
    ruido_lag_long = g_ruido.transform(lambda s: s.shift(LONG_WINDOW))
    out['ruido_slope_long'] = (df['ruido_db'] - ruido_lag_long) / LONG_WINDOW

    out['idade'] = df['idade']

    for name in MEMORY_FEATURES:
        out[name] = np.nan
    for idx in df.groupby('id_crianca').indices.values():
        cols = _memory_features(
            df['batimento_cardiaco_bpm'].to_numpy(dtype=float)[idx],
            df['giroscopio_magnitude_dps'].to_numpy(dtype=float)[idx],
            out['bpm_jerk'].to_numpy(dtype=float)[idx],
        )
        for name, values in zip(MEMORY_FEATURES, cols):
            out.loc[out.index[idx], name] = values

    out['id_crianca'] = df['id_crianca']
    out['timestamp'] = df['timestamp']
    out['nivel_estresse'] = df['nivel_estresse']
    out['estresse'] = df['estresse']

    return out.dropna().reset_index(drop=True)

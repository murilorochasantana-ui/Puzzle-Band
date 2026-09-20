"""
Engenharia de features para o modelo preditivo do Puzzle Band.

Historico (dataset v3): testamos uma feature de INCLINACAO curta vs longa
do batimento ("bpm_jerk") pra distinguir subida subita (estresse) de
subida gradual (exercicio). A feature existe e funciona no instante exato
do inicio de um episodio (ver model/README.md), mas tem peso agregado
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

    out['id_crianca'] = df['id_crianca']
    out['timestamp'] = df['timestamp']
    out['nivel_estresse'] = df['nivel_estresse']
    out['estresse'] = df['estresse']

    return out.dropna().reset_index(drop=True)

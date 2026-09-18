"""
Engenharia de features para o modelo preditivo do Puzzle Band.

Inclui features de INCLINACAO (slope) do batimento em janela curta vs longa,
para o caso de sensores reais capturarem picos subitos de estresse no
futuro. Nos testes com o dataset sintetico atual essas features de
"velocidade da subida" tiveram importancia quase nula: os episodios do
dataset sobem de forma gradual tanto no estresse real quanto durante
atividade fisica comum, entao o modelo nao consegue aprender a distinguir
"subito" de "gradual" a partir desses dados.

O que o dataset REALMENTE contem, e que o modelo aprende bem, e outra pista
fisiologica equivalente: batimento cardiaco sobe tanto por estresse quanto
por atividade fisica pura (ex.: brincadeira_ativa sem estresse chega a
121bpm em media, mais alto que um episodio de estresse "leve"!). A
diferenca esta em como o aumento de BPM se relaciona com o nivel de
MOVIMENTO (giroscopio) e de SUOR (EDA): atividade fisica eleva BPM e
giroscopio JUNTOS e proporcionalmente; estresse real eleva BPM e EDA
mesmo quando o giroscopio continua baixo (a crianca pode estar parada e
mesmo assim em crise). Por isso `gyro_mean_long` e as features de EDA
carregam a maior parte do peso do modelo, nao o BPM bruto.
"""
import numpy as np
import pandas as pd

SHORT_WINDOW = 5   # segundos - detecta salto subito
LONG_WINDOW = 30    # segundos - detecta tendencia/rampa gradual

FEATURE_COLUMNS = [
    'bpm', 'bpm_mean_long', 'bpm_slope_short', 'bpm_slope_long', 'bpm_jerk',
    'eda', 'eda_mean_long', 'eda_slope_long',
    'gyro_mag', 'gyro_mean_long', 'gyro_slope_long',
    'idade',
]


def build_features(df: pd.DataFrame) -> pd.DataFrame:
    """Recebe o dataframe cru (colunas em portugues do dataset) ordenado por
    crianca+tempo e devolve um dataframe so com as features do modelo,
    calculadas *por crianca* (nunca vaza dado entre criancas diferentes)."""

    df = df.sort_values(['id_crianca', 'timestamp']).reset_index(drop=True)
    out = pd.DataFrame(index=df.index)

    g_bpm = df.groupby('id_crianca')['batimento_cardiaco_bpm']
    g_eda = df.groupby('id_crianca')['nivel_suor_uS']
    g_gyro = df.groupby('id_crianca')['giroscopio_magnitude_dps']

    out['bpm'] = df['batimento_cardiaco_bpm']
    out['bpm_mean_long'] = g_bpm.transform(lambda s: s.rolling(LONG_WINDOW, min_periods=LONG_WINDOW).mean())
    bpm_lag_short = g_bpm.transform(lambda s: s.shift(SHORT_WINDOW))
    bpm_lag_long = g_bpm.transform(lambda s: s.shift(LONG_WINDOW))
    out['bpm_slope_short'] = (df['batimento_cardiaco_bpm'] - bpm_lag_short) / SHORT_WINDOW
    out['bpm_slope_long'] = (df['batimento_cardiaco_bpm'] - bpm_lag_long) / LONG_WINDOW
    # "jerk": o quanto a subida recente (curta) esta acima da tendencia (longa).
    # Alto e positivo = salto subito destoando do proprio ritmo da crianca.
    out['bpm_jerk'] = out['bpm_slope_short'] - out['bpm_slope_long']

    out['eda'] = df['nivel_suor_uS']
    out['eda_mean_long'] = g_eda.transform(lambda s: s.rolling(LONG_WINDOW, min_periods=LONG_WINDOW).mean())
    eda_lag_long = g_eda.transform(lambda s: s.shift(LONG_WINDOW))
    out['eda_slope_long'] = (df['nivel_suor_uS'] - eda_lag_long) / LONG_WINDOW

    out['gyro_mag'] = df['giroscopio_magnitude_dps']
    out['gyro_mean_long'] = g_gyro.transform(lambda s: s.rolling(LONG_WINDOW, min_periods=LONG_WINDOW).mean())
    gyro_lag_long = g_gyro.transform(lambda s: s.shift(LONG_WINDOW))
    out['gyro_slope_long'] = (df['giroscopio_magnitude_dps'] - gyro_lag_long) / LONG_WINDOW

    out['idade'] = df['idade']

    out['id_crianca'] = df['id_crianca']
    out['timestamp'] = df['timestamp']
    out['nivel_estresse'] = df['nivel_estresse']
    out['estresse'] = df['estresse']

    return out.dropna().reset_index(drop=True)

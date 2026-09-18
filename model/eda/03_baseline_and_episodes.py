import pandas as pd
import numpy as np

df = pd.read_pickle('/home/user/puzzle-band/model/eda/dados.pkl')

print('=== 6. Baseline por crianca (repouso, so estresse=0) - checa se cada crianca tem "perfil" proprio ===')
calmos = df[df['estresse']==0]
print(calmos.groupby('id_crianca')[['batimento_cardiaco_bpm','nivel_suor_uS','giroscopio_magnitude_dps']].agg(['mean','std']).round(2))

print()
print('=== 7. Distribuicao do giroscopio_magnitude (checar outliers extremos) ===')
print(df['giroscopio_magnitude_dps'].describe())
print('percentis altos:')
print(df['giroscopio_magnitude_dps'].quantile([0.9, 0.95, 0.99, 0.999, 1.0]))
print('registros > 500 dps:', (df['giroscopio_magnitude_dps'] > 500).sum())
print('registros > 500 dps E estresse=0:', ((df['giroscopio_magnitude_dps'] > 500) & (df['estresse']==0)).sum())

print()
print('=== 8. Duracao dos episodios de estresse (contiguidade temporal) ===')
def episode_lengths(sub):
    s = sub.sort_values('timestamp')['estresse'].values
    lens = []
    run = 0
    for v in s:
        if v == 1:
            run += 1
        else:
            if run > 0:
                lens.append(run)
            run = 0
    if run > 0:
        lens.append(run)
    return lens

all_lens = []
for cid, sub in df.groupby('id_crianca'):
    all_lens.extend(episode_lengths(sub))

all_lens = np.array(all_lens)
print('numero de episodios:', len(all_lens))
print('duracao (segundos) - min/mediana/media/max:', all_lens.min(), np.median(all_lens), all_lens.mean().round(1), all_lens.max())
print('percentual de episodios com 1 segundo so (liga/desliga instantaneo):', round((all_lens==1).mean()*100,1), '%')

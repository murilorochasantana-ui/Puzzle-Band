import pandas as pd
df = pd.read_pickle('/home/user/puzzle-band/model/eda/dados.pkl')

print('=== Stats globais por nivel_estresse (bpm, eda, gyro_mag) ===')
print(df.groupby('nivel_estresse')[['batimento_cardiaco_bpm','nivel_suor_uS','giroscopio_magnitude_dps']].agg(['mean','std']).round(2))

print()
print('=== Baseline calmo por crianca (para offset de personalizacao) ===')
calm = df[df['estresse']==0]
print(calm.groupby('id_crianca')[['batimento_cardiaco_bpm','nivel_suor_uS']].mean().round(2))

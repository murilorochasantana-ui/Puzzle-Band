import pandas as pd
import numpy as np

df = pd.read_pickle('/home/user/puzzle-band/model/eda/dados.pkl')

print('=== 1. Balanceamento por criança (idade, atividade) ===')
print(df.groupby('id_crianca')['idade'].first())
print()
print(df.groupby('id_crianca')['atividade'].value_counts(normalize=True).unstack().round(2))

print()
print('=== 2. Estresse por criança (garante que held-out crianças tenham exemplos) ===')
tab = df.groupby('id_crianca')['estresse'].agg(['mean','sum'])
tab['mean'] = (tab['mean']*100).round(1)
print(tab)

print()
print('=== 3. nivel_estresse por criança ===')
print(pd.crosstab(df['id_crianca'], df['nivel_estresse']))

print()
print('=== 4. Estresse cruzado com atividade (checar confusão atividade x estresse) ===')
print(pd.crosstab(df['atividade'], df['estresse'], normalize='index').round(3))
print(pd.crosstab(df['atividade'], df['nivel_estresse'], normalize='index').round(3))

print()
print('=== 5. Correlação idade x sinais basais (sem estresse) ===')
calmos = df[df['estresse']==0]
print(calmos.groupby('idade')[['batimento_cardiaco_bpm','nivel_suor_uS','giroscopio_magnitude_dps']].mean().round(2))

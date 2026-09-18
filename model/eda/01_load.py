import pandas as pd

df = pd.read_excel(
    '/home/user/puzzle-band/data/raw/dataset_pulseira_TEA_estresse.xlsx',
    sheet_name='Dados'
)
df.to_pickle('/home/user/puzzle-band/model/eda/dados.pkl')
print(df.shape)
print(df.dtypes)
print(df.isna().sum())
print('duplicados:', df.duplicated().sum())
print('duplicados (timestamp+crianca):', df.duplicated(subset=['timestamp','id_crianca']).sum())

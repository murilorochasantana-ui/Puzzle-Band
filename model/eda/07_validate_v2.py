import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GroupKFold
from sklearn.metrics import f1_score, recall_score, precision_score, roc_auc_score

df = pd.read_excel('/home/user/puzzle-band/data/raw/dataset_pulseira_TEA_estresse_v2.xlsx', sheet_name='Dados')
df = df.sort_values(['id_crianca','timestamp']).reset_index(drop=True)

print('=== Cobertura de niveis por crianca (deve ter as 4 colunas > 0 agora) ===')
print(pd.crosstab(df['id_crianca'], df['nivel_estresse']))

print()
print('=== Checagem de sanidade: nulos, duplicados, ranges ===')
print('nulos:', df.isna().sum().sum())
print('duplicados timestamp+crianca:', df.duplicated(subset=['timestamp','id_crianca']).sum())
print('bpm min/max:', df['batimento_cardiaco_bpm'].min(), df['batimento_cardiaco_bpm'].max())
print('eda min/max:', df['nivel_suor_uS'].min(), df['nivel_suor_uS'].max())
print('gyro_mag min/max:', df['giroscopio_magnitude_dps'].min(), df['giroscopio_magnitude_dps'].max())

print()
print('=== Prevalencia por crianca (antes vs depois deve ter subido um pouco nas 8 alteradas) ===')
tab = df.groupby('id_crianca')['estresse'].agg(['mean','sum'])
tab['mean'] = (tab['mean']*100).round(1)
print(tab)

# ---- Reavaliar modelo baseline (mesmo pipeline do dataset original) ----
for col in ['batimento_cardiaco_bpm','nivel_suor_uS','giroscopio_magnitude_dps']:
    grouped = df.groupby('id_crianca')[col]
    df[f'{col}_mean30'] = grouped.transform(lambda s: s.rolling(30, min_periods=5).mean())
    df[f'{col}_std30'] = grouped.transform(lambda s: s.rolling(30, min_periods=5).std())
df2 = df.dropna().reset_index(drop=True)

feature_cols = [
    'batimento_cardiaco_bpm','nivel_suor_uS','giroscopio_magnitude_dps',
    'batimento_cardiaco_bpm_mean30','nivel_suor_uS_mean30','giroscopio_magnitude_dps_mean30',
    'batimento_cardiaco_bpm_std30','nivel_suor_uS_std30','giroscopio_magnitude_dps_std30',
    'idade',
]
X = df2[feature_cols].values
y = df2['estresse'].values
groups = df2['id_crianca'].values

gkf = GroupKFold(n_splits=4)
f1s, recalls, precisions, aucs = [], [], [], []
print()
print('=== Baseline RandomForest, GroupKFold por crianca (dataset v2) ===')
for fold, (tr, te) in enumerate(gkf.split(X, y, groups)):
    clf = RandomForestClassifier(n_estimators=200, max_depth=8, class_weight='balanced', random_state=42, n_jobs=-1)
    clf.fit(X[tr], y[tr])
    pred = clf.predict(X[te])
    proba = clf.predict_proba(X[te])[:,1]
    f1 = f1_score(y[te], pred); rec = recall_score(y[te], pred)
    prec = precision_score(y[te], pred); auc = roc_auc_score(y[te], proba)
    test_children = sorted(set(groups[te]))
    print(f'Fold {fold} | teste={test_children} | F1={f1:.3f} recall={rec:.3f} precision={prec:.3f} AUC={auc:.3f}')
    f1s.append(f1); recalls.append(rec); precisions.append(prec); aucs.append(auc)

print(f'MEDIA -> F1={np.mean(f1s):.3f}  recall={np.mean(recalls):.3f}  precision={np.mean(precisions):.3f}  AUC={np.mean(aucs):.3f}')

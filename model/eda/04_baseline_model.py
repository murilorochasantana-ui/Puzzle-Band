import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GroupKFold
from sklearn.metrics import f1_score, recall_score, precision_score, roc_auc_score

df = pd.read_pickle('/home/user/puzzle-band/model/eda/dados.pkl').sort_values(['id_crianca','timestamp']).reset_index(drop=True)

# feature engineering: janela movel de 30s por crianca (media e desvio)
for col in ['batimento_cardiaco_bpm','nivel_suor_uS','giroscopio_magnitude_dps']:
    grouped = df.groupby('id_crianca')[col]
    df[f'{col}_mean30'] = grouped.transform(lambda s: s.rolling(30, min_periods=5).mean())
    df[f'{col}_std30'] = grouped.transform(lambda s: s.rolling(30, min_periods=5).std())

df = df.dropna().reset_index(drop=True)

feature_cols = [
    'batimento_cardiaco_bpm','nivel_suor_uS','giroscopio_magnitude_dps',
    'batimento_cardiaco_bpm_mean30','nivel_suor_uS_mean30','giroscopio_magnitude_dps_mean30',
    'batimento_cardiaco_bpm_std30','nivel_suor_uS_std30','giroscopio_magnitude_dps_std30',
    'idade',
]

X = df[feature_cols].values
y = df['estresse'].values
groups = df['id_crianca'].values

gkf = GroupKFold(n_splits=4)  # ~3 criancas de teste por fold
f1s, recalls, precisions, aucs = [], [], [], []

for fold, (train_idx, test_idx) in enumerate(gkf.split(X, y, groups)):
    clf = RandomForestClassifier(n_estimators=200, max_depth=8, class_weight='balanced', random_state=42, n_jobs=-1)
    clf.fit(X[train_idx], y[train_idx])
    pred = clf.predict(X[test_idx])
    proba = clf.predict_proba(X[test_idx])[:,1]

    f1 = f1_score(y[test_idx], pred)
    rec = recall_score(y[test_idx], pred)
    prec = precision_score(y[test_idx], pred)
    auc = roc_auc_score(y[test_idx], proba)

    test_children = sorted(set(groups[test_idx]))
    print(f'Fold {fold} | teste={test_children} | F1={f1:.3f} recall={rec:.3f} precision={prec:.3f} AUC={auc:.3f}')
    f1s.append(f1); recalls.append(rec); precisions.append(prec); aucs.append(auc)

print()
print(f'MEDIA -> F1={np.mean(f1s):.3f}  recall={np.mean(recalls):.3f}  precision={np.mean(precisions):.3f}  AUC={np.mean(aucs):.3f}')

print()
print('=== Importancia das features (ultimo fold treinado) ===')
imp = sorted(zip(feature_cols, clf.feature_importances_), key=lambda x: -x[1])
for name, val in imp:
    print(f'{name:40s} {val:.3f}')

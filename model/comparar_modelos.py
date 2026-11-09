"""
Compara versoes do modelo no dataset v4 (docs/modelo.md, "Versao
simplificada"): mesma validacao do train.py (GroupKFold por crianca, 4
folds), mudando so as features e o numero de arvores.

Por segundo: AUC (media dos folds, como no train.py), precisao, recall e F1
(limiar 0,5, todas as previsoes fora do fold juntas) e a precisao por
crianca (minima, mediana e maxima). Para cada versao tambem treina o modelo
final (todas as criancas) e grava em --saida o forest.json completo e o
compactado (limiares e probabilidades com 4 casas, JSON sem espacos), para a
comparacao por episodio (model/comparar_episodios.mjs).

Roda (da raiz):  python model/comparar_modelos.py --saida <pasta>
                 python model/comparar_modelos.py --saida <pasta> --variantes a,c_mem
"""
import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import f1_score, precision_score, recall_score, roc_auc_score
from sklearn.model_selection import GroupKFold

sys.path.insert(0, str(Path(__file__).parent))
from features import FEATURE_COLUMNS, MEMORY_FEATURES, build_features  # noqa: E402
from train import DATASET, MAX_DEPTH, ROOT, compactar, export_tree  # noqa: E402

# Importancia < 1% no modelo atual (fora as de ambiente, que saem em "c")
BAIXA_IMPORTANCIA = ['bpm_jerk', 'bpm_slope_short', 'bpm_tempo_elevado', 'idade', 'accel_mag', 'gyro_mag', 'gyro_slope_long']
AMBIENTE = ['luz', 'luz_mean_long', 'ruido', 'ruido_mean_long', 'ruido_slope_long']
# As 12 do modelo anterior ao v4 (linha "12 antigas" da ablacao)
ANTIGAS_12 = ['bpm', 'bpm_mean_long', 'bpm_slope_short', 'bpm_slope_long', 'bpm_jerk', 'eda', 'eda_mean_long',
              'eda_slope_long', 'gyro_mag', 'gyro_mean_long', 'gyro_slope_long', 'idade']

B = [c for c in FEATURE_COLUMNS if c not in BAIXA_IMPORTANCIA]
C = [c for c in B if c not in AMBIENTE]
VARIANTES = {
    'a': ('atual (24 features)', FEATURE_COLUMNS, 60),
    'b': ('b) sem importância < 1%', B, 60),
    'c': ('c) b sem ambiente', C, 60),
    'b30': ('b com 30 árvores', B, 30),
    'b40': ('b com 40 árvores', B, 40),
    'c30': ('c com 30 árvores', C, 30),
    'c40': ('c com 40 árvores', C, 40),
    'a_mem': ('a + memória', FEATURE_COLUMNS + MEMORY_FEATURES, 60),
    'b_mem': ('b + memória', B + MEMORY_FEATURES, 60),
    'c_mem': ('c + memória', C + MEMORY_FEATURES, 60),
    'c_mem30': ('c + memória, 30 árvores', C + MEMORY_FEATURES, 30),
    'c_mem40': ('c + memória, 40 árvores', C + MEMORY_FEATURES, 40),
    'b_mem30': ('b + memória, 30 árvores', B + MEMORY_FEATURES, 30),
    'b_mem40': ('b + memória, 40 árvores', B + MEMORY_FEATURES, 40),
    'abl12': ('12 antigas (ablação)', ANTIGAS_12, 60),
}


def floresta(n_arvores):
    return RandomForestClassifier(n_estimators=n_arvores, max_depth=MAX_DEPTH, class_weight='balanced',
                                  random_state=42, n_jobs=-1)


def avaliar(feats, colunas, n_arvores):
    X = feats[colunas].values
    y = feats['estresse'].values
    grupos = feats['id_crianca'].values
    proba = np.zeros(len(y))
    aucs = []
    for tr, te in GroupKFold(n_splits=4).split(X, y, grupos):
        clf = floresta(n_arvores).fit(X[tr], y[tr])
        proba[te] = clf.predict_proba(X[te])[:, 1]
        aucs.append(roc_auc_score(y[te], proba[te]))
    pred = (proba >= 0.5).astype(int)
    por_crianca = [precision_score(y[grupos == g], pred[grupos == g], zero_division=0) for g in sorted(set(grupos))]
    return {
        'auc': float(np.mean(aucs)),
        'precisao': precision_score(y, pred), 'recall': recall_score(y, pred), 'f1': f1_score(y, pred),
        'prec_crianca': (min(por_crianca), float(np.median(por_crianca)), max(por_crianca)),
    }


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser()
    ap.add_argument('--saida', required=True, help='pasta para os forest.json de cada versao')
    ap.add_argument('--variantes', default=','.join(VARIANTES), help='lista separada por virgula')
    args = ap.parse_args()
    saida = Path(args.saida)
    saida.mkdir(parents=True, exist_ok=True)

    feats = build_features(pd.read_excel(DATASET, sheet_name='Dados'))
    linhas = []
    for chave in args.variantes.split(','):
        nome, colunas, n_arvores = VARIANTES[chave]
        inicio = time.time()
        m = avaliar(feats, colunas, n_arvores)
        final = floresta(n_arvores).fit(feats[colunas].values, feats['estresse'].values)
        importancia = dict(sorted(zip(colunas, final.feature_importances_.round(4).tolist()), key=lambda x: -x[1]))
        arvores = [export_tree(est) for est in final.estimators_]
        base = {
            'meta': {'script': 'model/comparar_modelos.py', 'variante': chave, 'dataset': DATASET.relative_to(ROOT).as_posix(),
                     'n_arvores': n_arvores},
            'featureColumns': colunas, 'shortWindow': 5, 'longWindow': 30,
        }
        json.dump({**base, 'trees': arvores}, open(saida / f'{chave}.json', 'w'))
        json.dump({**base, 'trees': [compactar(a) for a in arvores]}, open(saida / f'{chave}.compacto.json', 'w'),
                  separators=(',', ':'))
        m.update(chave=chave, nome=nome, n_features=len(colunas), n_arvores=n_arvores, importancia=importancia,
                 kb=(saida / f'{chave}.compacto.json').stat().st_size / 1024)
        linhas.append(m)
        print(f'{chave}: AUC {m["auc"]:.3f} · precisao {m["precisao"]:.3f} · recall {m["recall"]:.3f} · '
              f'F1 {m["f1"]:.3f} · {time.time() - inicio:.0f} s', flush=True)
    with open(saida / 'metricas_por_segundo.json', 'w', encoding='utf-8') as f:
        json.dump(linhas, f, indent=1, ensure_ascii=False)

    print('\n| Versão | Features | Árvores | AUC | Precisão | Recall | F1 | Precisão por criança (mín · mediana · máx) | forest.json compacto |')
    print('|---|---|---|---|---|---|---|---|---|')
    for m in linhas:
        lo, med, hi = m['prec_crianca']
        print(f'| {m["nome"]} | {m["n_features"]} | {m["n_arvores"]} | {m["auc"]:.3f} | {m["precisao"]:.3f} | '
              f'{m["recall"]:.3f} | {m["f1"]:.3f} | {lo:.2f} · {med:.2f} · {hi:.2f} | {m["kb"]:.0f} KB |')


if __name__ == '__main__':
    main()

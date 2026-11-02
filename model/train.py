"""
Treina o classificador de "possivel crise" do Puzzle Band e valida com
GroupKFold por crianca (o modelo nunca ve dados da crianca em que esta
sendo avaliado - simula o uso em uma crianca nova).

Alvo binario (estresse: sim/nao), com probabilidade de saida - o dashboard
usa essa probabilidade para classificar em faixas de risco (nenhum /
atencao / alerta / crise), em vez de tentar prever os 4 rotulos originais
diretamente (testamos multiclasse - ver docs/modelo.md - e a fronteira
entre "leve" e "nenhum" e ruidosa demais pra ser confiavel; o binario com
probabilidade calibrada e uma base muito mais solida pra um alerta que vai
para um cuidador real).

Roda: python3 model/train.py

Este e o script OFICIAL do frontend/src/model/forest.json (o modelo que o
dashboard usa). O train_incremental.py e experimental - ver "Qual modelo
esta em producao" no docs/modelo.md.
"""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GroupKFold
from sklearn.metrics import classification_report, roc_auc_score, confusion_matrix

sys.path.insert(0, str(Path(__file__).parent))
from features import build_features, FEATURE_COLUMNS  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
DATASET = ROOT / 'data/raw/dataset_pulseira_TEA_estresse_v4.xlsx'
OUT_JSON = ROOT / 'frontend/src/model/forest.json'

N_ESTIMATORS = 60
MAX_DEPTH = 6


def export_tree(tree):
    """Converte uma arvore sklearn numa estrutura JSON simples de percorrer
    em JS: cada no tem feature/threshold/filhos, ou (se folha) a
    probabilidade da classe positiva (estresse=1)."""
    t = tree.tree_

    def node(i):
        if t.children_left[i] == t.children_right[i] == -1:
            counts = t.value[i][0]  # [count_classe_0, count_classe_1]
            total = counts.sum()
            proba1 = float(counts[1] / total) if total > 0 else 0.0
            return {'leaf': True, 'proba': proba1}
        return {
            'leaf': False,
            'feature': int(t.feature[i]),
            'threshold': float(t.threshold[i]),
            'left': node(t.children_left[i]),
            'right': node(t.children_right[i]),
        }

    return node(0)


def main():
    df = pd.read_excel(DATASET, sheet_name='Dados')
    feats = build_features(df)

    X = feats[FEATURE_COLUMNS].values
    y = feats['estresse'].values
    groups = feats['id_crianca'].values

    print(f'Total de amostras com features validas: {len(feats)}')
    print(f'Prevalencia de estresse: {y.mean()*100:.1f}%')
    print()

    gkf = GroupKFold(n_splits=4)
    all_true, all_pred, aucs = [], [], []

    for fold, (tr, te) in enumerate(gkf.split(X, y, groups)):
        clf = RandomForestClassifier(
            n_estimators=N_ESTIMATORS, max_depth=MAX_DEPTH,
            class_weight='balanced', random_state=42, n_jobs=-1,
        )
        clf.fit(X[tr], y[tr])
        pred = clf.predict(X[te])
        proba = clf.predict_proba(X[te])[:, 1]
        auc = roc_auc_score(y[te], proba)
        test_children = sorted(set(groups[te]))
        print(f'--- Fold {fold} | teste={test_children} | AUC={auc:.3f} ---')
        print(classification_report(y[te], pred, target_names=['sem_crise', 'possivel_crise'], zero_division=0))
        all_true.extend(y[te])
        all_pred.extend(pred)
        aucs.append(auc)

    print(f'AUC medio (GroupKFold por crianca): {np.mean(aucs):.3f}')
    print()
    print('=== Matriz de confusao agregada ===')
    print('linhas=real [sem_crise, possivel_crise], colunas=previsto')
    print(confusion_matrix(all_true, all_pred))

    print()
    print('=== Importancia das features (arvore final) ===')
    final_clf = RandomForestClassifier(
        n_estimators=N_ESTIMATORS, max_depth=MAX_DEPTH,
        class_weight='balanced', random_state=42, n_jobs=-1,
    )
    final_clf.fit(X, y)
    for name, val in sorted(zip(FEATURE_COLUMNS, final_clf.feature_importances_), key=lambda x: -x[1]):
        print(f'{name:20s} {val:.3f}')

    trees = [export_tree(est) for est in final_clf.estimators_]

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_JSON, 'w') as f:
        json.dump({
            # origem do modelo (mostrada no rodape do dashboard; predict.js ignora)
            'meta': {
                'script': 'model/train.py',
                'dataset': DATASET.relative_to(ROOT).as_posix(),
                'n_arvores': len(trees),
                'treinado_em': datetime.now(timezone.utc).isoformat(timespec='seconds'),
            },
            'featureColumns': FEATURE_COLUMNS,
            'shortWindow': 5,
            'longWindow': 30,
            'trees': trees,
        }, f)

    size_kb = OUT_JSON.stat().st_size / 1024
    print()
    print(f'Modelo exportado para {OUT_JSON} ({size_kb:.1f} KB)')


if __name__ == '__main__':
    main()

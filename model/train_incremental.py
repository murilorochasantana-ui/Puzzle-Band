"""
Treino INCREMENTAL do modelo do Puzzle Band - treina com um dataset sem
esquecer o que ja foi aprendido de rodadas anteriores com outros datasets.

Diferenca pro model/train.py (treino "do zero"): aqui usamos o warm_start
do RandomForestClassifier do scikit-learn. Cada chamada deste script NAO
recria o modelo - ela CARREGA o estado salvo da rodada anterior e ADICIONA
arvores novas, treinadas so com o dataset desta rodada. As arvores antigas
(treinadas em datasets anteriores) continuam exatamente como estavam, sem
serem retreinadas ou descartadas. A previsao final e a media de TODAS as
arvores acumuladas (antigas + novas).

Uso:
    # primeira rodada (cria o modelo do zero com este dataset)
    python3 model/train_incremental.py --dataset data/raw/dataset_pulseira_TEA_estresse_v3.xlsx --add-trees 60

    # segunda rodada (mantem as arvores da rodada anterior, soma mais arvores treinadas no dataset novo)
    python3 model/train_incremental.py --dataset data/raw/massive --add-trees 60

    # aceita .xlsx (aba 'Dados'), .csv, ou uma PASTA com varios .csv (concatena todos)

    # pra descartar tudo e comecar do zero de novo:
    python3 model/train_incremental.py --dataset caminho.xlsx --add-trees 60 --reset

Cada rodada sobrescreve frontend/src/model/forest.json com a floresta
COMPLETA (todas as arvores acumuladas ate agora) - o dashboard sempre usa
o conhecimento de todos os datasets ja treinados.

O estado do modelo (o objeto RandomForestClassifier em si, necessario pra
continuar treinando depois) fica salvo em model/state/forest_state.pkl -
nao apague esse arquivo se quiser treinar mais rodadas depois.
"""
import argparse
import json
import pickle
import sys
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import roc_auc_score

sys.path.insert(0, str(Path(__file__).parent))
from features import build_features, FEATURE_COLUMNS  # noqa: E402

MODEL_DIR = Path(__file__).parent
STATE_PATH = MODEL_DIR / 'state' / 'forest_state.pkl'
HISTORY_PATH = MODEL_DIR / 'state' / 'training_history.json'
OUT_JSON = MODEL_DIR.parent / 'frontend/src/model/forest.json'

MAX_DEPTH = 6


def load_dataset(path_str):
    """Aceita .xlsx (aba 'Dados', dados crus), .csv (ja com features) ou
    uma pasta com varios .csv (ex.: data/raw/massive/) - concatena tudo."""
    path = Path(path_str)

    if path.is_dir():
        parts = sorted(path.glob('*.csv'))
        if not parts:
            raise SystemExit(f'Nenhum .csv encontrado em {path}')
        print(f'Lendo {len(parts)} arquivo(s) csv de {path}...')
        df = pd.concat([pd.read_csv(p) for p in parts], ignore_index=True)
    elif path.suffix.lower() == '.csv':
        df = pd.read_csv(path)
    elif path.suffix.lower() in ('.xlsx', '.xls'):
        df = pd.read_excel(path, sheet_name='Dados')
    else:
        raise SystemExit(f'Formato nao suportado: {path.suffix}')

    if set(FEATURE_COLUMNS).issubset(df.columns):
        # ja vem com as features calculadas (ex.: dataset massivo) - so
        # remove as linhas de warmup (primeiras ~30s de cada crianca, sem
        # janela historica suficiente ainda)
        df = df.dropna(subset=FEATURE_COLUMNS).reset_index(drop=True)
    else:
        # dataset cru - calcula as features do zero
        df = build_features(df)

    return df


def export_tree(tree):
    t = tree.tree_

    def node(i):
        if t.children_left[i] == t.children_right[i] == -1:
            counts = t.value[i][0]
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


def load_history():
    if HISTORY_PATH.exists():
        with open(HISTORY_PATH) as f:
            return json.load(f)
    return []


def save_history(history):
    HISTORY_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(HISTORY_PATH, 'w') as f:
        json.dump(history, f, indent=2, ensure_ascii=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--dataset', required=True, help='.xlsx, .csv, ou pasta com varios .csv')
    parser.add_argument('--add-trees', type=int, default=60, help='quantas arvores NOVAS treinar nesta rodada (default: 60)')
    parser.add_argument('--reset', action='store_true', help='descarta o modelo acumulado e comeca do zero com este dataset')
    args = parser.parse_args()

    print(f'Carregando dataset: {args.dataset}')
    df = load_dataset(args.dataset)
    X = df[FEATURE_COLUMNS].values
    y = df['estresse'].values
    print(f'{len(df)} amostras validas | prevalencia de estresse: {y.mean()*100:.1f}%')

    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    history = load_history()

    if args.reset and STATE_PATH.exists():
        STATE_PATH.unlink()
        history = []
        print('--reset: modelo acumulado anterior descartado.')

    if STATE_PATH.exists():
        with open(STATE_PATH, 'rb') as f:
            clf = pickle.load(f)
        n_before = clf.n_estimators
        print(f'Modelo existente carregado: {n_before} arvores acumuladas de {len(history)} rodada(s) anterior(es).')

        # quao bem o modelo ATE AGORA (antes desta rodada) generaliza pra
        # este dataset novo - da uma nocao de "transferencia" entre datasets
        try:
            proba_antes = clf.predict_proba(X)[:, 1]
            auc_antes = roc_auc_score(y, proba_antes)
            print(f'AUC do modelo ANTES desta rodada, avaliado neste dataset novo: {auc_antes:.3f}')
        except Exception as exc:  # noqa: BLE001
            print(f'(nao foi possivel avaliar o modelo anterior neste dataset: {exc})')
    else:
        n_before = 0
        clf = RandomForestClassifier(
            n_estimators=0, warm_start=True, max_depth=MAX_DEPTH,
            class_weight='balanced', random_state=42, n_jobs=-1,
        )
        print('Nenhum modelo acumulado encontrado - comecando do zero.')

    clf.n_estimators = n_before + args.add_trees
    clf.fit(X, y)
    print(f'+{args.add_trees} arvores novas treinadas em "{args.dataset}". Total acumulado: {clf.n_estimators} arvores.')

    proba_depois = clf.predict_proba(X)[:, 1]
    auc_depois_insample = roc_auc_score(y, proba_depois)
    print(f'AUC do modelo COMPLETO (todas as rodadas) neste dataset (in-sample, nao e teste real): {auc_depois_insample:.3f}')

    with open(STATE_PATH, 'wb') as f:
        pickle.dump(clf, f)

    trees = [export_tree(est) for est in clf.estimators_]
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_JSON, 'w') as f:
        json.dump({
            'featureColumns': FEATURE_COLUMNS,
            'shortWindow': 5,
            'longWindow': 30,
            'trees': trees,
        }, f)

    history.append({
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'dataset': str(args.dataset),
        'amostras': len(df),
        'arvores_adicionadas': args.add_trees,
        'total_arvores_apos': clf.n_estimators,
    })
    save_history(history)

    size_kb = OUT_JSON.stat().st_size / 1024
    print()
    print(f'Modelo exportado para {OUT_JSON} ({size_kb:.1f} KB) - dashboard ja usa a floresta completa.')
    print(f'Historico de treino salvo em {HISTORY_PATH}')
    print()
    print('Nota: o AUC mostrado acima e "in-sample" (avaliado nos mesmos dados')
    print('usados pra treinar essa rodada) - serve so como sanity check rapido,')
    print('nao e uma metrica de generalizacao real. Pra validacao de verdade')
    print('(GroupKFold por crianca, held-out), use model/train.py num dataset')
    print('especifico.')


if __name__ == '__main__':
    main()

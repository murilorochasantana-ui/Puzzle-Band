"""
Estudo "exercicio x crise" (docs/modelo.md): avaliacao POR SEGUNDO de cada
versao no dataset v4, com o mesmo GroupKFold por crianca (4 folds) do
train.py.

Diferente do comparar_modelos.py (limiar 0,5), aqui as metricas sao no ponto
de operacao do alerta: "alerta" = nivel atencao ou possivel crise
(p >= 0,4) DEPOIS da politica de contexto, quando houver (mesmas contas de
frontend/src/model/contexto.js, reproduzidas aqui). Colunas:
  AUC (media dos folds, da probabilidade), precisao, recall e F1 do alerta,
  precisao do alerta por crianca (min / mediana / max) e "repouso com
  alerta": % dos segundos calmos (atividade calmo, sem estresse) com alerta,
  por crianca (min / mediana / max, e C03 e C06, as duas que ficavam acima
  de 0,4 em 98-99% do repouso).

Roda (da raiz): python model/estudo_exercicio.py --saida <pasta> [--versoes atual,p10,...]
"""
import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.metrics import f1_score, precision_score, recall_score, roc_auc_score
from sklearn.model_selection import GroupKFold

sys.path.insert(0, str(Path(__file__).parent))
from features import (BASE_FEATURES, CONTEXT_FEATURES, FEATURE_COLUMNS, RESIDUAL_FEATURES,  # noqa: E402
                      SLOPE_RESIDUAL_FEATURES, build_features, fit_coeficientes, residual_features)
from train import DATASET, MAX_DEPTH, N_ESTIMATORS, ROOT, compactar, export_tree  # noqa: E402
from sklearn.ensemble import RandomForestClassifier  # noqa: E402

LIMIAR_ATENCAO = 0.4
DESTAQUE = ['C03', 'C06']

# mesmos valores de frontend/src/model/contexto.js (CONTEXTO)
CONTEXTO = dict(janelaMovimentoS=10, memoriaExercicioS=60, giroExercicio=40, regularidadeRepetitiva=0.4,
                janelaBaseS=300, bpmPorGiro=0.34, edaElevada=3.5, bpmResiduoElevado=10)


def contexto(cru):
    """Por segundo (cru ordenado por crianca e tempo): politica ativa ou nao,
    igual a contextoDe + politicaAtiva do contexto.js."""
    c = CONTEXTO
    partes = []
    for _, g in cru.groupby('id_crianca', sort=False):
        gyro = g['giroscopio_magnitude_dps'].astype(float)
        reg = g['movimento_regularidade'].astype(float)
        eda = g['nivel_suor_uS'].astype(float)
        bpm = g['batimento_cardiaco_bpm'].astype(float)
        giro10 = gyro.rolling(c['janelaMovimentoS'], min_periods=1).mean()
        reg10 = reg.rolling(c['janelaMovimentoS'], min_periods=1).mean()
        repetitivo = reg10 >= c['regularidadeRepetitiva']
        exercicio = (~repetitivo) & (giro10 >= c['giroExercicio'])
        recente = exercicio.astype(int).rolling(c['memoriaExercicioS'], min_periods=1).max() > 0
        q = lambda s: s.rolling(c['janelaBaseS'], min_periods=1).quantile(0.1, interpolation='lower')  # noqa: E731
        eda_acima = eda.rolling(5, min_periods=1).mean() - q(eda)
        giro_acima = (giro10 - q(gyro)).clip(lower=0)
        residuo = bpm.rolling(5, min_periods=1).mean() - q(bpm) - c['bpmPorGiro'] * giro_acima
        ativa = recente & (~repetitivo) & (eda_acima < c['edaElevada']) & (residuo < c['bpmResiduoElevado'])
        bilateral = ativa & (residuo > -c['bpmResiduoElevado'])
        partes.append(pd.DataFrame({'id_crianca': g['id_crianca'], 'timestamp': g['timestamp'], 'politica_ativa': ativa,
                                    'politica_ativa_bilateral': bilateral,
                                    'ctx_eda_acima_base': eda_acima, 'ctx_bpm_residuo': residuo}))
    return pd.concat(partes)


def aplicar_politica(feats, proba, politica):
    """Alerta por segundo (p >= 0,4), com a politica aplicada por crianca."""
    alerta = proba >= LIMIAR_ATENCAO
    if not politica:
        return alerta
    out = alerta.copy()
    ativa = feats['politica_ativa_bilateral' if politica.get('bilateral') else 'politica_ativa'].to_numpy()
    if politica['tipo'] == 'rebaixa':
        return out  # rebaixar para atencao nao muda "alerta sim/nao"
    n = politica['n']
    for _, idx in feats.groupby('id_crianca').indices.items():
        a = pd.Series(alerta[idx].astype(int))
        persistiu = a.rolling(n, min_periods=n).min().fillna(0).to_numpy() > 0
        out[idx] = np.where(ativa[idx], persistiu, alerta[idx])
    return out


def floresta(n):
    return RandomForestClassifier(n_estimators=n, max_depth=MAX_DEPTH, class_weight='balanced', random_state=42, n_jobs=-1)


USA_COEF = set(RESIDUAL_FEATURES + SLOPE_RESIDUAL_FEATURES)


# Calibracao individual (E2d; Verkuil et al., 2016; Versluis et al., 2020):
# por crianca, os primeiros CAL_CALMO_S segundos calmos e CAL_ATIVO_S
# segundos ativos (atividade leve ou brincadeira), sem estresse, dao a linha
# de base (mediana no calmo) e os coeficientes do movimento dela.
CAL_CALMO_S = 600
CAL_ATIVO_S = 300
RELATIVAS_FIXAS = ['bpm_acima_base', 'hrv_abaixo_base', 'eda_acima_base', 'gyro_acima_base']


def relativas_calibradas(f, base):
    """As relativas (menos a inclinacao suave) com a linha de base FIXA da
    calibracao, no lugar do percentil dos ultimos 300 s."""
    return pd.DataFrame({
        'bpm_acima_base': f['bpm_mean_long'] - base['bpm'], 'hrv_abaixo_base': base['hrv'] - f['hrv_mean_long'],
        'eda_acima_base': f['eda_mean_long'] - base['eda'], 'gyro_acima_base': f['gyro_mean_long'] - base['gyro'],
    }, index=f.index)


def calibracao_de(f, cru_crianca):
    """Linha de base e coeficientes de UMA crianca (features dela, com a
    coluna atividade, e as leituras cruas)."""
    calmo = f[(f['atividade'] == 'calmo') & (f['estresse'] == 0)].head(CAL_CALMO_S)
    ativo = f[f['atividade'].isin(['atividade_leve', 'brincadeira_ativa']) & (f['estresse'] == 0)].head(CAL_ATIVO_S)
    c = cru_crianca.set_index('timestamp').loc[calmo['timestamp']]
    base = {'bpm': float(c['batimento_cardiaco_bpm'].median()), 'hrv': float(c['hrv_rmssd_ms'].median()),
            'eda': float(c['nivel_suor_uS'].median()), 'gyro': float(c['giroscopio_magnitude_dps'].median())}
    cal = pd.concat([calmo, ativo])
    cal = cal.drop(columns=RELATIVAS_FIXAS).join(relativas_calibradas(cal, base))
    return {**base, 'coeficientes': fit_coeficientes(cal, np.ones(len(cal), dtype=bool))}


# Variante sem rotulo nenhum: linha de base fixa tirada dos primeiros
# JANELA_S segundos de cada crianca (o que a pulseira veria logo depois de
# ser colocada), com os mesmos percentis da linha de base movel (10; 90 na
# HRV). Coeficientes do movimento: os globais do treino de cada dobra.
JANELA_S = 300


def base_da_janela(cru_crianca, n=JANELA_S):
    c = cru_crianca.sort_values('timestamp').head(n)
    q = lambda col, p: float(c[col].quantile(p, interpolation='lower'))  # noqa: E731
    return {'bpm': q('batimento_cardiaco_bpm', 0.1), 'hrv': q('hrv_rmssd_ms', 0.9), 'eda': q('nivel_suor_uS', 0.1),
            'gyro': q('giroscopio_magnitude_dps', 0.1)}


def aplicar_janela(feats, cru):
    """Troca as relativas pelas da linha de base fixa da janela inicial."""
    partes = []
    bases = {}
    for cid, f in feats.groupby('id_crianca', sort=False):
        base = base_da_janela(cru[cru['id_crianca'] == cid])
        bases[cid] = base
        partes.append(f.drop(columns=RELATIVAS_FIXAS).join(relativas_calibradas(f, base)))
    return pd.concat(partes).loc[feats.index], bases


def aplicar_calibracao(feats, cru):
    """Troca as relativas e os residuos pelos da calibracao de cada crianca."""
    partes = []
    cals = {}
    for cid, f in feats.groupby('id_crianca', sort=False):
        cal = calibracao_de(f, cru[cru['id_crianca'] == cid])
        cals[cid] = cal
        g = f.drop(columns=RELATIVAS_FIXAS).join(relativas_calibradas(f, cal))
        partes.append(g.join(residual_features(g, cal['coeficientes'])))
    return pd.concat(partes).loc[feats.index], cals


def matriz(feats, colunas, coef):
    """Matriz de features; as residuais usam os coeficientes `coef`
    ('individual': ja calculadas por crianca em aplicar_calibracao)."""
    if coef is None or coef == 'individual':
        return feats[colunas].values
    return feats.join(residual_features(feats, coef))[colunas].values


def oof(feats, colunas, n_arvores, individual=False):
    """Probabilidade fora do fold. Coeficientes do movimento ajustados SO nas
    criancas de treino de cada fold, nos segundos sem estresse (ou, com
    `individual`, os de cada crianca, da calibracao dela)."""
    y, g = feats['estresse'].values, feats['id_crianca'].values
    usa_coef = bool(USA_COEF & set(colunas)) and not individual
    proba = np.zeros(len(y))
    aucs = []
    for tr, te in GroupKFold(n_splits=4).split(feats, y, g):
        coef = None
        if usa_coef:
            mask = np.zeros(len(y), dtype=bool)
            mask[tr] = True
            coef = fit_coeficientes(feats, mask & (y == 0))
        X = matriz(feats, colunas, 'individual' if individual else coef)
        clf = floresta(n_arvores).fit(X[tr], y[tr])
        proba[te] = clf.predict_proba(X[te])[:, 1]
        aucs.append(roc_auc_score(y[te], proba[te]))
    return proba, float(np.mean(aucs))


def exportar(feats, colunas, n_arvores, destino, chave, individual=False):
    """Modelo final (todas as criancas) compactado, com os coeficientes do
    movimento (se usar), para a comparacao por episodio. Com `individual`,
    sem coeficientes globais: a calibracao da crianca simulada entra depois
    (model/calibrar_simulador.py)."""
    y = feats['estresse'].values
    coef = fit_coeficientes(feats, y == 0) if USA_COEF & set(colunas) and not individual else None
    clf = floresta(n_arvores).fit(matriz(feats, colunas, 'individual' if individual else coef), y)
    forest = {'meta': {'script': 'model/estudo_exercicio.py', 'variante': chave, 'dataset': DATASET.relative_to(ROOT).as_posix(),
                       'n_arvores': n_arvores},
              'featureColumns': list(colunas), 'shortWindow': 5, 'longWindow': 30}
    if coef:
        forest['coeficientes'] = coef
    forest['trees'] = [compactar(export_tree(e)) for e in clf.estimators_]
    with open(destino / f'{chave}.compacto.json', 'w') as f:
        json.dump(forest, f, separators=(',', ':'))
    importancia = sorted(zip(colunas, clf.feature_importances_.round(4).tolist()), key=lambda x: -x[1])
    return coef, importancia, (destino / f'{chave}.compacto.json').stat().st_size / 1024


def metricas(feats, proba, auc, alerta):
    y = feats['estresse'].values
    g = feats['id_crianca'].values
    criancas = sorted(set(g))
    prec = [precision_score(y[g == c], alerta[g == c], zero_division=0) for c in criancas]
    calmo = (feats['atividade'] == 'calmo').values & (y == 0)
    repouso = {c: float(alerta[(g == c) & calmo].mean()) for c in criancas}
    vals = list(repouso.values())
    return {
        'auc': auc, 'precisao': precision_score(y, alerta), 'recall': recall_score(y, alerta), 'f1': f1_score(y, alerta),
        'prec_crianca': (min(prec), float(np.median(prec)), max(prec)),
        'repouso': (min(vals), float(np.median(vals)), max(vals)), 'repouso_destaque': {c: repouso[c] for c in DESTAQUE},
        'repouso_por_crianca': repouso,
    }


ABSOLUTAS = ['bpm', 'bpm_mean_long', 'eda', 'eda_mean_long', 'hrv', 'hrv_mean_long']
SEM_ABS = [c for c in FEATURE_COLUMNS if c not in ABSOLUTAS]
E2A = FEATURE_COLUMNS + BASE_FEATURES
E2B = E2A + RESIDUAL_FEATURES
E2C = E2B + SLOPE_RESIDUAL_FEATURES

VERSOES = {
    'atual': dict(nome='atual (24 features, 60 árvores)', colunas=FEATURE_COLUMNS, politica=None),
    'p10': dict(nome='E4 persistência 10 s', colunas=FEATURE_COLUMNS, politica={'tipo': 'persistencia', 'n': 10}),
    'p20': dict(nome='E4 persistência 20 s', colunas=FEATURE_COLUMNS, politica={'tipo': 'persistencia', 'n': 20}),
    'p30': dict(nome='E4 persistência 30 s', colunas=FEATURE_COLUMNS, politica={'tipo': 'persistencia', 'n': 30}),
    'reb': dict(nome='E4 rebaixa para atenção', colunas=FEATURE_COLUMNS, politica={'tipo': 'rebaixa'}),
    'p10b': dict(nome='E4b persistência 10 s, batimento explicado', colunas=FEATURE_COLUMNS,
                 politica={'tipo': 'persistencia', 'n': 10, 'bilateral': True}),
    'p20b': dict(nome='E4b persistência 20 s, batimento explicado', colunas=FEATURE_COLUMNS,
                 politica={'tipo': 'persistencia', 'n': 20, 'bilateral': True}),
    'p30b': dict(nome='E4b persistência 30 s, batimento explicado', colunas=FEATURE_COLUMNS,
                 politica={'tipo': 'persistencia', 'n': 30, 'bilateral': True}),
    'e2a': dict(nome='E2a + relativas à linha de base', colunas=E2A, politica=None),
    'e2b': dict(nome='E2b + batimento/HRV adicional (global)', colunas=E2B, politica=None),
    'e2c': dict(nome='E2c + inclinações descontadas do movimento', colunas=E2C, politica=None),
    'e2a_rel': dict(nome='E2a só relativas (sem níveis absolutos)', colunas=SEM_ABS + BASE_FEATURES, politica=None),
    'e2c_rel': dict(nome='E2c só relativas (sem níveis absolutos)', colunas=SEM_ABS + BASE_FEATURES + RESIDUAL_FEATURES
                    + SLOPE_RESIDUAL_FEATURES, politica=None),
    'e2c_cal': dict(nome='E2d = E2c com calibração individual', colunas=E2C, politica=None, individual=True),
    'e2c_rel_cal': dict(nome='E2d = E2c só relativas, calibração individual', colunas=SEM_ABS + BASE_FEATURES
                        + RESIDUAL_FEATURES + SLOPE_RESIDUAL_FEATURES, politica=None, individual=True),
    'e2c_jan': dict(nome='E2d sem rótulo = E2c, base fixa dos primeiros 5 min', colunas=E2C, politica=None, janela=True),
    'e2c_rel_jan': dict(nome='E2d sem rótulo = E2c só relativas, base dos primeiros 5 min', colunas=SEM_ABS + BASE_FEATURES
                        + RESIDUAL_FEATURES + SLOPE_RESIDUAL_FEATURES, politica=None, janela=True),
    'e3': dict(nome='E3 + contexto de atividade (regras)', colunas=FEATURE_COLUMNS + CONTEXT_FEATURES, politica=None),
}


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser()
    ap.add_argument('--saida', required=True)
    ap.add_argument('--versoes', default=','.join(VERSOES))
    ap.add_argument('--exportar', action='store_true', help='grava o forest.json compactado de cada versao (sem politica)')
    args = ap.parse_args()
    saida = Path(args.saida)
    saida.mkdir(parents=True, exist_ok=True)

    cru = pd.read_excel(DATASET, sheet_name='Dados').sort_values(['id_crianca', 'timestamp']).reset_index(drop=True)
    feats = build_features(cru)
    feats = feats.merge(cru[['id_crianca', 'timestamp', 'atividade']], on=['id_crianca', 'timestamp'])
    feats = feats.merge(contexto(cru), on=['id_crianca', 'timestamp'])

    feats_cal = None
    feats_jan = None
    cache = {}
    linhas = []
    for chave in args.versoes.split(','):
        v = VERSOES[chave]
        inicio = time.time()
        individual = v.get('individual', False)
        if individual and feats_cal is None:
            feats_cal, cals = aplicar_calibracao(feats, cru)
            with open(saida / 'calibracoes.json', 'w') as f:
                json.dump(cals, f, indent=1)
        janela = v.get('janela', False)
        if janela and feats_jan is None:
            feats_jan, bases = aplicar_janela(feats, cru)
            with open(saida / 'bases_janela.json', 'w') as f:
                json.dump(bases, f, indent=1)
        fv = feats_cal if individual else feats_jan if janela else feats
        k = (tuple(v['colunas']), v.get('n_arvores', N_ESTIMATORS), individual, janela)
        if k not in cache:
            cache[k] = oof(fv, v['colunas'], k[1], individual)
        proba, auc = cache[k]
        alerta = aplicar_politica(fv, proba, v['politica'])
        m = metricas(fv, proba, auc, alerta)
        m.update(chave=chave, nome=v['nome'], n_features=len(v['colunas']))
        if args.exportar and not v['politica']:
            m['coef'], m['importancia'], m['kb'] = exportar(fv, v['colunas'], k[1], saida, chave, individual)
        linhas.append(m)
        print(f'{chave}: AUC {m["auc"]:.3f} · precisão {m["precisao"]:.3f} · recall {m["recall"]:.3f} · '
              f'F1 {m["f1"]:.3f} · repouso C03 {m["repouso_destaque"]["C03"]:.2f} C06 {m["repouso_destaque"]["C06"]:.2f} '
              f'· {time.time() - inicio:.0f} s', flush=True)
    with open(saida / 'por_segundo.json', 'w', encoding='utf-8') as f:
        json.dump(linhas, f, indent=1, ensure_ascii=False)

    print('\n| Versão | AUC | Precisão | Recall | F1 | Precisão por criança (mín · mediana · máx) | Repouso com alerta, por criança (mín · mediana · máx) | C03 · C06 em repouso |')
    print('|---|---|---|---|---|---|---|---|')
    for m in linhas:
        a, b, c = m['prec_crianca']
        r1, r2, r3 = m['repouso']
        d = m['repouso_destaque']
        pc = lambda x: f'{100 * x:.0f}%'  # noqa: E731
        print(f'| {m["nome"]} | {m["auc"]:.3f} | {m["precisao"]:.3f} | {m["recall"]:.3f} | {m["f1"]:.3f} | '
              f'{a:.2f} · {b:.2f} · {c:.2f} | {pc(r1)} · {pc(r2)} · {pc(r3)} | **{pc(d["C03"])} · {pc(d["C06"])}** |')


if __name__ == '__main__':
    main()

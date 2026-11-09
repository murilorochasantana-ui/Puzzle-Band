"""
Diagnostico do alarme falso no exercicio, lado do dataset (docs/modelo.md,
"Estudo: exercicio x crise"). So mede, nao treina modelo novo.

1. Quantos INICIOS de exercicio (entrada em brincadeira_ativa) o v4 tem
   rotulados como nao-estresse, e quantos segundos isso da.
2. Probabilidade fora do fold (mesmo GroupKFold e mesma floresta do
   train.py) nesses inicios: em quantos o modelo passaria de 0,4 (atencao)
   ou 0,7 (possivel crise).
3. Faixas (p10 / mediana / p90) das leituras e das features no inicio e no
   plato do exercicio: v4 x simulador (features_simulador.csv, gerado por
   model/diagnostico_exercicio.mjs features <pasta>).
4. Graficos das curvas do simulador (curva_*.csv do modo "curvas").

Roda (da raiz):  python model/diagnostico_exercicio.py <pasta> [--png <pasta das imagens>]
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GroupKFold

sys.path.insert(0, str(Path(__file__).parent))
from features import FEATURE_COLUMNS, build_features  # noqa: E402
from train import DATASET, MAX_DEPTH, N_ESTIMATORS  # noqa: E402

INICIO_S = 60   # "inicio do exercicio" = primeiros 60 s depois da entrada
JANELA_ALERTA_S = 90  # um alarme no inicio = p >= limiar em algum segundo dos primeiros 90 s
COMPARAR = ['bpm', 'eda', 'hrv', 'gyro_mag', 'accel_mag', 'bpm_mean_long', 'bpm_slope_long', 'bpm_jerk',
            'eda_mean_long', 'eda_slope_long', 'gyro_mean_long', 'hrv_mean_long', 'hrv_slope_long',
            'accel_mean_long', 'regularidade_mean_long', 'prob']
SIM_COL = {'bpm': 'bpm', 'eda': 'eda_uS', 'hrv': 'hrv_ms', 'gyro_mag': 'gyro_mag_dps', 'accel_mag': 'accel_mag_g'}


def oof(feats):
    X, y, g = feats[FEATURE_COLUMNS].values, feats['estresse'].values, feats['id_crianca'].values
    proba = np.zeros(len(y))
    for tr, te in GroupKFold(n_splits=4).split(X, y, g):
        clf = RandomForestClassifier(n_estimators=N_ESTIMATORS, max_depth=MAX_DEPTH, class_weight='balanced',
                                     random_state=42, n_jobs=-1).fit(X[tr], y[tr])
        proba[te] = clf.predict_proba(X[te])[:, 1]
    return proba


def trechos(df):
    """Rotula cada segundo: inicio_60s / plato / saida_60s / outro, e numera
    as entradas em brincadeira_ativa."""
    df = df.sort_values(['id_crianca', 'timestamp']).reset_index(drop=True)
    trecho = np.full(len(df), 'outro', dtype=object)
    evento = np.full(len(df), -1)
    origem = np.full(len(df), '', dtype=object)
    n_ev = 0
    for _, idx in df.groupby('id_crianca').indices.items():
        a = df['atividade'].to_numpy()[idx]
        i = 0
        while i < len(a):
            if a[i] == 'brincadeira_ativa' and (i == 0 or a[i - 1] != 'brincadeira_ativa'):
                j = i
                while j < len(a) and a[j] == 'brincadeira_ativa':
                    j += 1
                ini = idx[i:min(j, i + INICIO_S)]
                trecho[ini] = 'inicio_60s'
                trecho[idx[i + INICIO_S:j]] = 'plato'
                trecho[idx[j:min(len(a), j + INICIO_S)]] = 'saida_60s'
                evento[idx[i:min(len(a), i + JANELA_ALERTA_S)]] = n_ev
                origem[idx[i:j]] = a[i - 1] if i else 'inicio'
                n_ev += 1
                i = j
            else:
                i += 1
    df['trecho'] = trecho
    df['evento'] = evento
    df['origem'] = origem
    return df


def faixa(s):
    s = s.dropna()
    return f'{s.quantile(0.1):.2f} · {s.median():.2f} · {s.quantile(0.9):.2f}' if len(s) else '—'


def graficos(pasta, destino):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    destino.mkdir(parents=True, exist_ok=True)
    paineis = [('prob', 'probabilidade'), ('bpm', 'BPM'), ('eda_uS', 'EDA (µS)'), ('hrv_ms', 'HRV (ms)'),
               ('gyro_mag_dps', 'giroscópio (dps)'), ('accel_mag_g', 'acelerômetro (g)'), ('regularidade', 'regularidade')]
    for arq in sorted(pasta.glob('curva_*.csv')):
        d = pd.read_csv(arq)
        fig, axs = plt.subplots(len(paineis), 1, figsize=(9, 11), sharex=True)
        alerta = d[d['alerta'].notna() & (d['alerta'] != '')]
        ep = d['episodio'].to_numpy()
        for ax, (col, rot) in zip(axs, paineis):
            ax.plot(d['t_rel'], d[col], lw=1, color='#2b5c8a')
            if col == 'prob':
                ax.axhline(0.4, color='#c98a00', lw=0.8, ls='--')
                ax.axhline(0.7, color='#b03030', lw=0.8, ls='--')
                ax.set_ylim(0, 1)
            if col == 'bpm':
                ax.plot(d['t_rel'], d['bpm_mean_long'], lw=1, color='#888', label='média 30 s')
            ax.fill_between(d['t_rel'], 0, 1, where=ep == 1, transform=ax.get_xaxis_transform(), color='#b03030', alpha=0.08)
            for t in alerta['t_rel']:
                ax.axvline(t, color='#b03030', lw=0.8)
            ax.set_ylabel(rot, fontsize=8)
            ax.tick_params(labelsize=7)
        for t, nome in [(0, 'início')]:
            for ax in axs:
                ax.axvline(t, color='#444', lw=0.6, ls=':')
        axs[0].set_title(f'cenário exercicio — {arq.stem.replace("curva_", "")} '
                         '(faixa vermelha: episódio aberto; linhas vermelhas: alerta)', fontsize=9)
        axs[-1].set_xlabel('segundos desde o início do exercício', fontsize=8)
        fig.tight_layout()
        fig.savefig(destino / f'exercicio_{arq.stem.replace("curva_", "")}.png', dpi=80)
        plt.close(fig)
        print('png:', destino / f'exercicio_{arq.stem.replace("curva_", "")}.png')


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    ap = argparse.ArgumentParser()
    ap.add_argument('pasta')
    ap.add_argument('--png', default=None)
    args = ap.parse_args()
    pasta = Path(args.pasta)

    cru = trechos(pd.read_excel(DATASET, sheet_name='Dados'))
    feats = build_features(cru)
    feats['prob'] = oof(feats)
    feats = feats.merge(cru[['id_crianca', 'timestamp', 'atividade', 'trecho', 'evento', 'origem']],
                        on=['id_crianca', 'timestamp'])

    res = {}
    # 1. inicios e segundos
    ev = cru[cru['evento'] >= 0].groupby('evento').agg(origem=('origem', 'first'), estresse=('estresse', 'max'))
    res['inicios'] = {'total': int(len(ev)), 'por_origem': ev['origem'].value_counts().to_dict(),
                      'sem_estresse_nos_90s': int((ev['estresse'] == 0).sum())}
    ini = cru[cru['trecho'] == 'inicio_60s']
    res['segundos_inicio_60s'] = {'total': int(len(ini)), 'sem_estresse': int((ini['estresse'] == 0).sum()),
                                  'percentual_do_dataset': round(100 * len(ini) / len(cru), 2),
                                  'percentual_dos_nao_estresse': round(100 * (ini['estresse'] == 0).sum() / (cru['estresse'] == 0).sum(), 2)}

    # 2. probabilidade fora do fold nos inicios sem estresse
    limpos = ev.index[ev['estresse'] == 0]
    fe = feats[feats['evento'].isin(limpos)]
    pico = fe.groupby('evento')['prob'].max()
    res['inicios_sem_estresse_com_dados'] = int(len(pico))
    res['inicios_com_p_ge_0_4'] = int((pico >= 0.4).sum())
    res['inicios_com_p_ge_0_7'] = int((pico >= 0.7).sum())
    res['pico_p_mediano'] = round(float(pico.median()), 3)
    for trecho in ['inicio_60s', 'plato', 'saida_60s']:
        s = feats[(feats['trecho'] == trecho) & (feats['estresse'] == 0)]['prob']
        res[f'p_{trecho}'] = {'segundos': int(len(s)), 'p>=0.4': round(float((s >= 0.4).mean()), 3), 'mediana': round(float(s.median()), 3)}
    calmo = feats[(feats['atividade'] == 'calmo') & (feats['estresse'] == 0)]['prob']
    res['p_calmo'] = {'segundos': int(len(calmo)), 'p>=0.4': round(float((calmo >= 0.4).mean()), 3)}

    # 3. faixas v4 x simulador
    sim = pd.read_csv(pasta / 'features_simulador.csv')
    for k, c in SIM_COL.items():
        sim[k] = sim[c]
    linhas = []
    for col in COMPARAR:
        linha = {'feature': col}
        for nome, d, filtro in [
            ('v4 calmo', feats, (feats['atividade'] == 'calmo') & (feats['estresse'] == 0)),
            ('sim calmo', sim, sim['trecho'] == 'calmo'),
            ('v4 início 60 s', feats, (feats['trecho'] == 'inicio_60s') & (feats['estresse'] == 0)),
            ('sim início 60 s', sim, sim['trecho'] == 'inicio_60s'),
            ('v4 platô', feats, (feats['trecho'] == 'plato') & (feats['estresse'] == 0)),
            ('sim platô', sim, sim['trecho'] == 'plato'),
            ('v4 estresse alto parado', feats, (feats['nivel_estresse'] == 'alto') & (feats['gyro_mean_long'] < 40)),
        ]:
            linha[nome] = faixa(d.loc[filtro, col]) if col in d else '—'
        linhas.append(linha)
    res['faixas'] = linhas
    (pasta / 'diagnostico_dataset.json').write_text(json.dumps(res, indent=1, ensure_ascii=False), encoding='utf-8')
    feats.to_pickle(pasta / 'features_v4_oof.pkl')

    print(json.dumps({k: v for k, v in res.items() if k != 'faixas'}, indent=1, ensure_ascii=False))
    cols = list(linhas[0])
    print('\n| ' + ' | '.join(cols) + ' |')
    print('|' + '---|' * len(cols))
    for l in linhas:
        print('| ' + ' | '.join(l[c] for c in cols) + ' |')

    if args.png:
        graficos(pasta, Path(args.png))


if __name__ == '__main__':
    main()

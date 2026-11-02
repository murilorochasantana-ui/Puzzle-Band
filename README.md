# Puzzle Band

Sistema *wearable* de monitoramento sensorial e auxílio na identificação de
gatilhos de estresse no Transtorno do Espectro Autista (TEA) — TCC
(Bacharelado em Ciências da Computação, modalidade Empreendedor).

O projeto tem duas partes:

- **Dashboard** (`frontend/`) — painel do cuidador em React, com duas
  fontes de dados: um simulador manual (sem depender de dataset) onde você
  controla BPM, EDA, giroscópio/acelerômetro, HRV e sensores ambientais pra
  testar o modelo em tempo real, e a pulseira via MQTT.
- **Modelo preditivo** (`model/`) — classificador em Python (Random
  Forest) que cruza os sinais e estima a probabilidade de uma possível
  crise. É treinado em Python e exportado como JSON; a inferência roda
  inteira em JavaScript no navegador, sem precisar de backend.

## Funcionalidades do dashboard

- **Previsão de possível crise** — o Random Forest estima a probabilidade a
  cada segundo e a converte em faixas (sem sinais de crise / atenção /
  possível crise).
- **Indicação de gatilho provável** — quando o modelo alerta, uma regra
  explicável compara luz e ruído dos últimos 60 s com a linha de base da
  criança e verifica se a mudança veio **antes** da alteração fisiológica.
  O alerta mostra, por exemplo: *"Provável gatilho: ruído (45 → 88 dB,
  cerca de 12 s antes da alteração fisiológica)"*. Detalhes, limites e
  testes: [docs/gatilho.md](docs/gatilho.md).
- **Histórico de episódios** — cada episódio (do alerta até 30 s de volta
  ao normal) fica salvo no navegador com duração, nível e probabilidade
  máximos e gatilho provável. O cuidador pode confirmar ou descartar o
  gatilho e anotar uma observação. Há um resumo de padrões por criança e
  exportação em CSV. Detalhes e privacidade (LGPD):
  [docs/historico.md](docs/historico.md).
- **Modo Pulseira (MQTT)** — recebe as leituras do broker e publica os
  alertas em `puzzleband/<id>/alertas`, agora com o objeto do gatilho.

## Pré-requisitos

- **Node.js** (inclui o `npm`) — para rodar o dashboard
- **Python 3** (inclui o `pip`) — só necessário se for treinar/retreinar o modelo

No Windows, teste antes com `python --version` e `node --version` no
PowerShell pra confirmar que ambos estão instalados e no PATH.

## Estrutura do projeto

```
puzzle-band/
├── data/raw/              # datasets sintéticos (.xlsx) usados pra treinar
├── model/
│   ├── features.py        # engenharia de features (compartilhada)
│   ├── train.py            # treino do zero + validação (GroupKFold) — gera o forest.json OFICIAL
│   ├── train_incremental.py # treino incremental (experimental)
│   ├── state/               # estado do treino incremental (floresta separada, não é a do dashboard)
│   ├── eda/                 # geradores de dataset + análises exploratórias
│   └── README.md            # decisões de design do modelo, métricas detalhadas
├── docs/
│   ├── avaliacao_dataset.md # avaliação do dataset sintético
│   ├── gatilho.md           # indicação de gatilho provável (algoritmo, limites, testes)
│   └── historico.md         # histórico de episódios (campos, CSV, privacidade)
└── frontend/
    ├── src/
    │   ├── App.jsx           # dashboard principal
    │   ├── components/       # UI (controles, gráfico, alerta, histórico, etc.)
    │   ├── hooks/            # MQTT e monitor de episódios
    │   └── model/
    │       ├── forest.json    # modelo treinado (gerado pelo Python)
    │       ├── predict.js     # inferência (roda no navegador)
    │       ├── simulate.js    # gerador de leituras do simulador manual
    │       ├── trigger.js     # regra do gatilho provável (+ trigger.test.js)
    │       └── episodes.js    # episódios, histórico e CSV (+ episodes.test.js)
    ├── scripts/cenarios.mjs  # cenários de ponta a ponta com o modelo real
    └── package.json
```

## Rodando o dashboard

Todo comando abaixo roda dentro da pasta `frontend/` — é onde fica o
`package.json` (comum confundir com a raiz do projeto):

```bash
cd frontend
npm install
npm run dev
```

Isso abre um servidor local (o terminal mostra o endereço, normalmente algo como
`http://localhost:5173`). Abra esse endereço no navegador.

Outros comandos úteis, também dentro de `frontend/`:

```bash
npm run build     # gera a versão de produção (pasta dist/)
npm run preview   # serve a versão de produção localmente pra conferir
npm run lint      # checagem de código (oxlint)
npm test          # testes automatizados (node:test, sem dependências extras)
```

### Testes

`npm test` (dentro de `frontend/`) roda os testes da regra do gatilho, do
histórico de episódios e os cenários de ponta a ponta com o modelo real. Pra
ver o relatório completo dos cenários (quantas vezes o gatilho certo foi
identificado):

```bash
node scripts/cenarios.mjs              # 20 sementes por cenário
node scripts/cenarios.mjs --sementes 50
```

Resultados e explicação: [docs/gatilho.md](docs/gatilho.md#resultado-dos-testes).

O dashboard já vem com um modelo pré-treinado (`frontend/src/model/forest.json`)
— não é necessário treinar nada em Python só para usar o simulador.

## Treinando o modelo

Isso só é necessário se você quiser gerar um modelo novo (dataset
diferente, mais dados, etc.). Rode a partir da **raiz do projeto**
(`puzzle-band/`, não dentro de `frontend/`):

```bash
pip install pandas numpy scikit-learn openpyxl
```

### Opção A — treino do zero (mais simples)

Treina um modelo novo com um único dataset e já valida com
`GroupKFold` por criança (o modelo nunca vê dados da criança em que está
sendo avaliado):

```bash
python model/train.py
```

Por padrão usa `data/raw/dataset_pulseira_TEA_estresse_v4.xlsx` (o dataset
mais completo, com HRV, acelerômetro e sensores ambientais). Pra trocar de
dataset, edite a constante `DATASET` no topo de `model/train.py`.

### Opção B — treino incremental (experimental)

> O `forest.json` oficial vem da Opção A. A Opção B substitui o modelo do
> dashboard por uma floresta experimental; pra voltar, rode
> `python model/train.py`. Ver "Qual modelo está em produção" no
> `model/README.md`.

Treina somando árvores novas à floresta já existente, sem esquecer
datasets treinados em rodadas anteriores (usa o `warm_start` do
scikit-learn):

```bash
# primeira rodada — cria o modelo do zero com este dataset
python model/train_incremental.py --dataset data/raw/dataset_pulseira_TEA_estresse_v4.xlsx --add-trees 60

# rodadas seguintes — mantém as árvores anteriores, soma mais árvores treinadas no dataset novo
python model/train_incremental.py --dataset data/raw/dataset_pulseira_TEA_estresse_v3.xlsx --add-trees 60

# aceita .xlsx (aba 'Dados'), .csv com features já calculadas, ou uma PASTA com vários .csv

# pra descartar o modelo acumulado e recomeçar do zero:
python model/train_incremental.py --dataset caminho.xlsx --add-trees 60 --reset
```

Detalhes de cada opção, limitações e como interpretar o AUC impresso no
terminal: `model/README.md`.

**Depois de treinar (qualquer uma das opções):** o arquivo
`frontend/src/model/forest.json` é sobrescrito automaticamente. Se o
dashboard já estava rodando (`npm run dev`), dê um refresh (F5) na página
pra carregar o modelo novo. O rodapé do dashboard mostra qual modelo está em
uso (ex.: "Modelo: 60 árvores, treinado em 02/11/2026 (model/train.py)").

## Simulador da pulseira (MQTT)

Cenários do simulador de linha de comando (pasta `simulator/`), que publica
leituras no broker para o modo "Pulseira (MQTT)" do dashboard:

```bash
npm start -- --cenario calmo              	  Criança em repouso, todos os sinais estáveis
npm start -- --cenario exercicio              Atividade física: BPM, EDA e movimento sobem juntos, com movimento irregular
npm start -- --cenario estereotipia           Movimento repetitivo e regular (ex.: balançar o corpo), com sinais de estresse
npm start -- --cenario crise_sem_gatilho      Crise sem causa externa: os sinais fisiológicos sobem, mas luz e ruído ficam normais
npm start -- --cenario crise_ruido            Crise com gatilho ambiental: o ruído sobe e depois BPM e EDA sobem e a HRV cai
```

Com `crise_ruido`, o alerta do dashboard deve indicar "Provável gatilho:
ruído"; com `crise_sem_gatilho`, "Sem gatilho ambiental aparente". Os dois
episódios aparecem no histórico, abaixo do gráfico.


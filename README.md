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
│   └── eda/                 # geradores de dataset + análises exploratórias
├── docs/                   # documentação detalhada (ver "Documentação" abaixo)
├── simulator/              # simulador da pulseira (ESP32) via MQTT
│   ├── index.js             # publica leituras e status no broker
│   ├── scenarios.js         # cenários (linha do tempo de cada sinal)
│   ├── verificar.js         # confere os cenários com o modelo e o gatilho, sem broker
│   └── .env.example         # modelo do simulator/.env (broker, usuário, CHILD_ID)
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
> `python model/train.py`. Ver "Qual modelo está em produção" em
> [docs/modelo.md](docs/modelo.md#qual-modelo-está-em-produção).

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
terminal: [docs/modelo.md](docs/modelo.md).

**Depois de treinar (qualquer uma das opções):** o arquivo
`frontend/src/model/forest.json` é sobrescrito automaticamente. Se o
dashboard já estava rodando (`npm run dev`), dê um refresh (F5) na página
pra carregar o modelo novo. O rodapé do dashboard mostra qual modelo está em
uso (ex.: "Modelo: 60 árvores, treinado em 02/11/2026 (model/train.py)").

## Simulador da pulseira (MQTT)

A pasta `simulator/` faz o papel do ESP32: publica 1 leitura por segundo no
broker (`puzzleband/<CHILD_ID>/leituras`, QoS 0) e o status da pulseira
(`puzzleband/<CHILD_ID>/status`: `online` retido ao conectar, `offline` ao
sair com Ctrl+C ou como Last Will se o processo cair). As leituras vêm do
mesmo gerador do simulador manual (`frontend/src/model/simulate.js`).

Configuração (uma vez), dentro de `simulator/`:

```bash
cd simulator
npm install
copy .env.example .env      # Windows (Linux/macOS: cp .env.example .env)
```

Depois preencha `MQTT_USER` e `MQTT_PASS` no `simulator/.env` com o usuário
da pulseira no EMQX Cloud. O `CHILD_ID` precisa ser igual ao `VITE_CHILD_ID`
do `frontend/.env`. O `.env` não vai para o Git.

Rodando (no dashboard, escolha a fonte "Pulseira (MQTT)"):

```bash
npm start -- --cenario crise_ruido                 # ou o atalho: npm run crise-ruido
npm run crise-ruido -- --duracao 300 --idade 10    # para sozinho após 300 s; idade de 5 a 12
npm run demo                                       # sequência da apresentação (10,5 min)
```

| Cenário | Atalho | O que acontece | Roteiro |
|---|---|---|---|
| `calmo` | `npm run calmo` | Repouso: todos os sinais estáveis | 300 s (sempre calmo) |
| `exercicio` | `npm run exercicio` | Atividade física: BPM, EDA e movimento sobem juntos, movimento irregular | 410 s |
| `estereotipia` | `npm run estereotipia` | Movimento repetitivo e regular (balançar o corpo) com sinais de estresse; ambiente estável | 410 s |
| `crise_ruido` | `npm run crise-ruido` | Ruído sobe (45 → 88 dB) ~12 s antes da fisiologia; depois BPM e EDA sobem e a HRV cai | 357 s |
| `crise_luz` | `npm run crise-luz` | Luz sobe forte (300 → 1200 lux) ~12 s antes da fisiologia | 357 s |
| `crise_sem_gatilho` | `npm run crise-sem-gatilho` | A fisiologia sobe; luz e ruído ficam na linha de base | 357 s |
| `crise_ruido_e_luz` | `npm run crise-ruido-e-luz` | Ruído e luz sobem juntos ~12 s antes da fisiologia | 357 s |
| `barulho_sem_crise` | `npm run barulho-sem-crise` | Ruído alto (~85 dB) e luz forte (~1200 lux) por 3 min, mas a criança continua calma | 450 s |
| `ruido_depois_da_crise` | `npm run ruido-depois-da-crise` | A fisiologia sobe primeiro; o ruído só sobe ~30 s depois (criança gritando) | 357 s |
| `crise_e_recuperacao` | `npm run crise-e-recuperacao` | Calmo → crise com ruído (~2 min) → volta gradual e ≥ 90 s calmo (o episódio fecha) | 417 s |
| `demo` | `npm run demo` | Apresentação: calmo → exercício → calmo → crise com ruído → recuperação → crise sem gatilho → recuperação | 630 s |

Os cenários isolados começam com **2 minutos calmos** (linha de base da regra
de gatilho); a `demo` começa com 60 s. As transições são rampas de 20 a 40 s.
A linha do tempo e a duração do roteiro aparecem no início da execução, e cada
leitura é impressa com a fase atual. Depois do roteiro, tudo fica calmo até
o Ctrl+C (ou use `--duracao`).

Com `crise_ruido`, o alerta do dashboard deve indicar "Provável gatilho:
ruído"; com `crise_luz`, "luminosidade"; com `crise_sem_gatilho`, "Sem
gatilho ambiental aparente". Os episódios aparecem no histórico, abaixo do
gráfico.

Para conferir os cenários contra o modelo e a regra de gatilho **sem broker**
(roda em segundos): `npm run verificar` (ou
`node verificar.js --cenario demo --sementes 50`). Resultados esperados ×
obtidos e o roteiro da apresentação: [docs/testes.md](docs/testes.md).

## Documentação

Este é o único README do projeto; os detalhes ficam em `docs/`:

| Documento | Conteúdo |
|---|---|
| [docs/modelo.md](docs/modelo.md) | Modelo preditivo: decisões de design, validação, ablação, importância das features e qual modelo está em produção |
| [docs/gatilho.md](docs/gatilho.md) | Indicação de gatilho provável: algoritmo, limites e por quê, testes e limitações |
| [docs/historico.md](docs/historico.md) | Histórico de episódios: campos, avaliação do cuidador, CSV e privacidade (LGPD) |
| [docs/testes.md](docs/testes.md) | Cenários do simulador × resultado esperado × obtido e roteiro da apresentação |
| [docs/avaliacao_dataset.md](docs/avaliacao_dataset.md) | Avaliação do dataset sintético |


# Puzzle Band

Sistema *wearable* de monitoramento sensorial e auxílio na identificação de
gatilhos de estresse no Transtorno do Espectro Autista (TEA) — TCC
(Bacharelado em Ciências da Computação, modalidade Empreendedor).

O projeto tem quatro partes, ligadas por um broker MQTT na nuvem (EMQX
Cloud):

- **Site / painel de controle** (`frontend/`) — dashboard em React e
  "servidor" do sistema. Tem duas fontes de dados: um simulador manual (sem
  depender de dataset) onde você controla BPM, EDA, giroscópio/acelerômetro,
  HRV e sensores ambientais pra testar o modelo em tempo real, e a pulseira
  via MQTT. Roda o modelo, a regra de gatilho e o histórico, e publica o
  resultado processado para o app.
- **App do cuidador** (`mobile/`) — app Android em Flutter: estado ao vivo,
  notificação com som nos alertas, botão "Estou ciente", painel com os
  episódios do dia, histórico com avaliação do gatilho (que volta para o
  site) e lembretes do cuidador, que ficam só no celular.
- **Simulador da pulseira** (`simulator/`) — faz o papel do ESP32 e publica
  as leituras no broker.
- **Modelo preditivo** (`model/`) — classificador em Python (Random
  Forest) que cruza os sinais e estima a probabilidade de uma possível
  crise. É treinado em Python e exportado como JSON; a inferência roda
  inteira em JavaScript no navegador.

```
simulador ──leituras──▶ broker ──▶ site (roda o modelo) ──estado/alertas/historico──▶ broker ──▶ app
                                     ▲                                                          │
                                     └──────────── avaliacao / ack / app/status ◀───────────────┘
```

Tópicos, formatos, QoS e ACL: [docs/mqtt.md](docs/mqtt.md).

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
- **Modo Pulseira (MQTT)** — recebe as leituras da pulseira pelo broker.
- **Sincronia com o app do cuidador** (nos dois modos, com o broker
  conectado) — o site publica o estado ao vivo 1×/s
  (`puzzleband/<id>/estado`), os alertas na mudança de nível
  (`puzzleband/<id>/alertas`, com o objeto do gatilho) e os 50 últimos
  episódios (`puzzleband/<id>/historico`). Ele recebe do app o "Estou
  ciente" e a avaliação do gatilho. O cabeçalho mostra "App do cuidador:
  conectado/desconectado".

## Pré-requisitos

- **Node.js** (inclui o `npm`) — para rodar o dashboard e o simulador
- **Flutter** + **Android Studio** — para o app do cuidador (`mobile/`)
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
│   ├── index.js             # publica leituras e status no broker (loop, --ciclos, --seed)
│   ├── scenarios.js         # cenários, variação entre ciclos e eventos_aleatorios
│   ├── gabarito.js          # gabarito dos testes: logs/eventos_<data-hora>.csv e .json
│   ├── verificar.js         # confere os cenários (em loop) com o modelo e o gatilho, sem broker
│   ├── logs/                # gabaritos gravados pelo simulador (locais, fora do Git)
│   └── .env.example         # modelo do simulator/.env (broker, usuário, CHILD_ID)
├── tools/
│   └── verificar-app.mjs    # faz o papel do app pelo terminal: confere site ⇄ app (npm run verificar-app)
├── mobile/                 # app do cuidador (Flutter, Android) — ver docs/app.md
│   ├── lib/
│   │   ├── services/mqtt_service.dart   # serviço MQTT único (TLS, Last Will, reconexão)
│   │   ├── services/notification_service.dart
│   │   ├── models/           # parse validado das mensagens do site
│   │   ├── theme/            # tema único (cores claro/escuro, tipografia, medidas)
│   │   └── screens/          # login, início, gráficos, histórico, ajustes
│   ├── test/                 # flutter test
│   └── env.example.json      # modelo do mobile/env.json (broker, usuário app, CHILD_ID)
└── frontend/
    ├── src/
    │   ├── App.jsx           # dashboard principal
    │   ├── components/       # UI (controles, gráfico, alerta, histórico, etc.)
    │   ├── hooks/            # MQTT (useMqttReadings), sincronia com o app
    │   │                     # (useCaregiverSync), mensagens (parse/buildMessages)
    │   │                     # e monitor de episódios
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
copy .env.example .env      # só na primeira vez (Linux/macOS: cp .env.example .env)
npm run dev
```

No `frontend/.env`, preencha `VITE_MQTT_PASS` com a senha do usuário
`dashboard` do EMQX Cloud. Sem ele, o simulador manual funciona, mas o site
não conecta ao broker (nem pulseira, nem app do cuidador).

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
npm start -- --cenario crise_ruido                    # ou o atalho: npm run crise-ruido (loop até o Ctrl+C)
npm run crise-ruido -- --ciclos 3 --seed 42           # 3 ciclos reproduzíveis e encerra
npm run crise-ruido -- --uma-vez --idade 10           # só o roteiro nominal, uma vez; idade de 5 a 12
npm run eventos-aleatorios -- --ciclos 20 --seed 42   # 20 eventos sorteados (teste do TCC)
npm run demo -- --ciclos 1                            # sequência da apresentação (10,5 min + pausa final)
```

### Loop (padrão) e opções

Todo cenário roda em **loop** até o Ctrl+C. Quando o roteiro termina (todos
os sinais de volta ao calmo), vem uma **pausa calma** e começa um novo ciclo
do mesmo cenário. A pausa (padrão 120 s) é o tempo para:

1. o episódio anterior fechar no site: o modelo ainda alerta ~20–25 s depois
   de a fisiologia normalizar, e o episódio só fecha após 30 s seguidos em
   baixo risco;
2. a linha de base ambiental da regra de gatilho se restabelecer (≥ 60 s de
   leituras calmas antes da janela de análise).

O 1º ciclo é o roteiro nominal, com os 2 minutos calmos iniciais. É o mesmo
do `--uma-vez` e das tabelas do [docs/testes.md](docs/testes.md). A partir do
2º ciclo, cada um varia um pouco. Os limites foram conferidos para manter o
resultado esperado (`npm run verificar`):

| O que varia | Quanto |
|---|---|
| Intensidade do pico (BPM, EDA, HRV e movimento; luz e ruído com sorteio próprio) | ±15% |
| Duração de cada fase (subida, platô, descida) | ±20% |
| Antecedência do sinal ambiental (cruzar o limite da regra → início da fisiologia) | 8 a 15 s |

No terminal, cada ciclo começa com uma linha destacada e a variação sorteada.
Cada leitura continua com o nome da fase (trecho real de
`npm run crise-ruido -- --seed 42`):

```
=== Ciclo 3 · crise_ruido ===
    roteiro crise_ruido · pico ×1,06 · subida 35 s · platô 61 s · descida 35 s · ambiente ×1,08 · antecedência ~14 s
[10:56] bpm  79  eda  4.03  hrv  53.0  gyro   2.4  reg 0.18  luz  292  ruido  44.0 | ruído subindo
...
[13:26] bpm  77  eda  3.79  hrv  57.0  gyro   8.1  reg 0.12  luz  303  ruido  44.8 | pausa calma (recuperação) · ciclo 4 em 120 s
```

| Opção | O que faz |
|---|---|
| `--uma-vez` | Só o roteiro nominal, uma vez, e encerra (como antes do loop) |
| `--ciclos N` | Roda N ciclos (no `eventos_aleatorios`, N eventos) e uma pausa final, para o último episódio fechar no site, e encerra |
| `--pausa S` | Pausa calma entre ciclos, em segundos (padrão 120; mínimo 90: abaixo disso o simulador avisa e usa 90). No `eventos_aleatorios`, a pausa é sorteada entre S e 2×S |
| `--seed N` | Semente do sorteio e do ruído dos sensores: a mesma seed repete a mesma sequência de ciclos ou eventos e as mesmas leituras. Sem `--seed`, uma é sorteada e impressa no início |
| `--idade A` | Idade da criança, de 5 a 12 anos (padrão 8) |
| `--duracao S` | Para depois de S segundos, em qualquer modo |

O `barulho_sem_crise` (e o `ambiente_sem_crise` do `eventos_aleatorios`) usa
pausa de pelo menos **300 s** depois dele. Como a criança fica calma, as
leituras barulhentas entram na linha de base de 5 min da regra de gatilho, e
ela precisa desse tempo para voltar ao ambiente calmo (ver
[docs/testes.md](docs/testes.md#teste-com-eventos-aleatórios)).

| Cenário | Atalho | O que acontece | Roteiro nominal |
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
| `eventos_aleatorios` | `npm run eventos-aleatorios` | Eventos sorteados de vários tipos, com pausas calmas aleatórias (ver abaixo) | sem fim |

Os cenários isolados começam com **2 minutos calmos** (linha de base da regra
de gatilho); a `demo` começa com 60 s. As transições são rampas de 20 a 40 s.
A linha do tempo do roteiro aparece no início da execução, e cada leitura é
impressa com a fase atual. Em loop, cada ciclo dura o trecho ativo do roteiro
(~2,5 a 4 min) mais a pausa.

Com `crise_ruido`, o alerta do dashboard deve indicar "Provável gatilho:
ruído"; com `crise_luz`, "luminosidade"; com `crise_sem_gatilho`, "Sem
gatilho ambiental aparente". Os episódios aparecem no histórico, abaixo do
gráfico, um por ciclo.

### Cenário `eventos_aleatorios`

Sequência sem fim (ou `--ciclos N` eventos) de eventos sorteados, separados
por pausas calmas de 120 a 240 s. Cada evento reaproveita o roteiro de um
cenário, com a variação descrita acima:

| Tipo | Roteiro usado | Crise real | Gatilho esperado | Peso |
|---|---|---|---|---|
| `sonora` | `crise_ruido` | sim | `ruido` | 20 |
| `visual` | `crise_luz` | sim | `luminosidade` | 15 |
| `sobrecarga_sensorial` | `crise_ruido_e_luz` | sim | `ruido_e_luminosidade` | 15 |
| `interna` | `crise_sem_gatilho` | sim | `nenhum_ambiental` | 15 |
| `motora` | `estereotipia` | sim | `nenhum_ambiental` | 10 |
| `consequencia` | `ruido_depois_da_crise` | sim | `nenhum_ambiental` (o ruído é consequência) | 10 |
| `exercicio` | `exercicio` | não | sem episódio (pode gerar alerta falso: limitação conhecida) | 10 |
| `ambiente_sem_crise` | `barulho_sem_crise` | não | sem episódio | 5 |

- Os pesos ficam em `PESOS_EVENTOS` (`simulator/scenarios.js`). O mesmo tipo
  sai no máximo 2 vezes seguidas.
- Cada crise ganha uma **intensidade** sorteada, que multiplica o pico de
  BPM/EDA e a queda de HRV (`INTENSIDADES`): leve ×0,3, moderada ×0,65,
  alta ×1. A alta é o roteiro nominal, o nível "alto" do dataset v4; a
  moderada e a leve seguem a proporção dos níveis moderado e leve do mesmo
  dataset.

Trecho real de `npm run eventos-aleatorios -- --seed 42`:

```
=== Evento 11 · visual · intensidade moderada · gatilho esperado: luminosidade ===
    roteiro crise_luz · pico ×0,67 · subida 31 s · platô 53 s · descida 36 s · ambiente ×1,02 · antecedência ~8 s
[56:37] bpm  77  eda  3.98  hrv  54.2  gyro   8.1  reg 0.09  luz  304  ruido  44.5 | luz subindo
...
[58:45] bpm  77  eda  3.93  hrv  55.7  gyro   2.3  reg 0.00  luz  299  ruido  46.6 | pausa calma (recuperação) · evento 12 em 125 s
```

### Gabarito dos testes (`simulator/logs/`)

Toda execução grava `simulator/logs/eventos_<data-hora>.csv` (e `.json`), com
uma linha por evento (nos outros cenários, uma por ciclo). Cada linha é
escrita quando os sinais voltam ao calmo. A pasta `logs/` está no
`simulator/.gitignore`: os logs são locais.

| Coluna | Conteúdo |
|---|---|
| `numero` | Número do evento ou ciclo |
| `tipo` | Tipo do evento (`sonora`, `visual`…) ou, fora do `eventos_aleatorios`, o nome do cenário |
| `intensidade` | `leve`, `moderada` ou `alta` (vazio fora do `eventos_aleatorios` e nos eventos sem crise) |
| `inicio`, `fim` | Quando os sinais começaram a mudar e quando voltaram ao calmo (ISO 8601, hora local) |
| `crise_real` | `sim` ou `não` |
| `gatilho_esperado` | `ruido`, `luminosidade`, `ruido_e_luminosidade`, `nenhum_ambiental` ou `sem_episodio` |
| `seed` | Semente da execução |
| Extras | `cenario`, `fator_pico`, `fator_ambiente`, `antecedencia_s`, `fisiologia_inicio`, `pausa_depois_s` e `observacao` (`interrompido (…)` se o simulador parou no meio do evento) |

O CSV segue o formato do CSV do histórico do site (`;`, vírgula decimal,
UTF-8 com BOM), para comparar os dois no Excel. Passo a passo:
[docs/testes.md](docs/testes.md#teste-com-eventos-aleatórios).

### Verificação sem broker

`npm run verificar` confere os cenários contra o modelo e a regra de gatilho
**sem broker**, em segundos. Ele roda cada cenário em loop (3 ciclos, 20
sementes) e o `eventos_aleatorios` com seed fixa, comparando o gabarito com
os episódios detectados. `node verificar.js --uma-vez` repete a verificação
antiga, só com o roteiro nominal. Resultados esperados × obtidos e o roteiro
da apresentação: [docs/testes.md](docs/testes.md).

## App do cuidador (celular)

A pasta `mobile/` é um app Flutter para Android. Configuração (uma vez),
dentro de `mobile/`:

```bash
cd mobile
flutter pub get
copy env.example.json env.json     # Windows (Linux/macOS: cp env.example.json env.json)
```

Preencha `MQTT_PASS` no `mobile/env.json` com a senha do usuário `app` do
EMQX Cloud. O `CHILD_ID` precisa ser o mesmo do site. O `env.json` está no
`.gitignore`.

- **Android Studio:** abra a pasta `mobile/` → **Run → Edit
  Configurations…** → configuração Flutter `main.dart` → **Additional run
  args**: `--dart-define-from-file=env.json` → **OK** → escolha o emulador
  ou o celular → **Run ▶**.
- **Terminal:** `flutter run --dart-define-from-file=env.json`

Emulador, celular físico (depuração USB), telas, notificações e limitações:
[docs/app.md](docs/app.md).

## Roteiro de demonstração (site + app)

Antes: `frontend/.env` e `mobile/env.json` preenchidos, internet no
computador e no celular, e notificações do app permitidas.

Para conferir a troca de mensagens sem o celular, use
`npm run verificar-app` em `simulator/`. Ele faz o papel do app pelo
terminal (ver [docs/mqtt.md](docs/mqtt.md#verificar-pelo-terminal-verificar-app)).

1. **Site no modo manual + app aberto no celular.** `npm run dev` em
   `frontend/`, abra o site e deixe em **Simulador manual**. No celular,
   abra o app e toque em **Entrar**. O site mostra "App do cuidador:
   conectado", e o app mostra "Broker: conectado" e "Painel: ao vivo", com
   **Calmo** e o BPM dos controles. Mexa no BPM no site e o número muda no
   celular em ~1 s.
2. **Crise pelos controles → notificação → "Estou ciente".** Deixe tudo
   calmo por **~2 min**: a regra de gatilho precisa de 60 s de linha de base
   antes da janela de análise de 60 s. Suba o **ruído** para ~90 dB e, uns 10
   s depois, suba **BPM** (~140) e **EDA** (~12 µS) e baixe a **HRV** (~20
   ms). O site mostra o alerta "Provável gatilho: ruído". No celular chega a
   notificação **Possível crise** com esse texto, e a Home mostra o card do
   alerta. Toque em **Estou ciente**: o banner do site passa a mostrar
   "Alerta visto pelo cuidador às HH:MM". Esse roteiro foi conferido com o
   modelo real: 10 de 10 sementes deram gatilho "ruído" com linha de base
   confiável. Durante a crise o nível oscila entre atenção e possível crise,
   mas o app notifica uma vez só.
3. **Confirmar o gatilho no app → histórico do site atualiza.** Volte os
   controles ao normal e espere 30 s para o episódio fechar. No app, abra
   **Histórico**, escreva uma observação e toque em **Confirmar gatilho**. No
   site, o episódio passa a "✓ confirmado pelo cuidador", com a etiqueta
   "avaliado pelo app às HH:MM" e a observação.
4. **Simulador com `crise_ruido`.** No site, escolha **Pulseira (MQTT)**. Em
   outro terminal: `cd simulator` e `npm run crise-ruido`. Os indicadores
   ficam "Pulseira: online" no site e no app. Depois de ~2 min calmos, o
   ruído sobe, o modelo alerta e o celular notifica com "Provável gatilho:
   ruído (45 → 88 dB, …)". Ctrl+C no simulador: "Pulseira: offline" nos dois.

## Documentação

Este é o README principal do projeto; os detalhes ficam em `docs/`:

| Documento | Conteúdo |
|---|---|
| [docs/modelo.md](docs/modelo.md) | Modelo preditivo: decisões de design, validação, ablação, importância das features e qual modelo está em produção |
| [docs/gatilho.md](docs/gatilho.md) | Indicação de gatilho provável: algoritmo, limites e por quê, testes e limitações |
| [docs/historico.md](docs/historico.md) | Histórico de episódios: campos, avaliação do cuidador, CSV e privacidade (LGPD) |
| [docs/testes.md](docs/testes.md) | Cenários do simulador × resultado esperado × obtido (uma vez e em loop), teste com eventos aleatórios e roteiro da apresentação |
| [docs/avaliacao_dataset.md](docs/avaliacao_dataset.md) | Avaliação do dataset sintético |
| [docs/mqtt.md](docs/mqtt.md) | Diagrama, tópicos (quem publica/assina, QoS, retain), formatos das mensagens e ACL sugerida |
| [docs/app.md](docs/app.md) | App do cuidador: telas, `env.json`, como rodar (emulador e celular) e limitações |
| [docs/design-app.md](docs/design-app.md) | Design do app (UX/UI): direção visual, paleta com contrastes, tipografia, acessibilidade para o TEA e antes/depois de cada tela |

## Créditos

As telas do app do cuidador (login, home, gráficos e configurações) vieram do
repositório [mariafernandarsantos/puzzleband](https://github.com/mariafernandarsantos/puzzleband)
(pasta `frontend/`, Flutter). Aqui os dados fixos foram trocados pelos dados
recebidos do site via MQTT, e o visual foi redesenhado para o público do TEA
([docs/design-app.md](docs/design-app.md)).


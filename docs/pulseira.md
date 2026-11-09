# Pulseira simulada (`simulator/`)

Como rodar e configurar a pulseira (ESP32 simulado, com processamento na
borda): cenários, modo controle, loop e opções, eventos aleatórios, gabarito
dos testes e verificação sem broker. Tópicos e formatos:
[mqtt.md](mqtt.md). Resultados dos cenários: [testes.md](testes.md).
Reset e roteiro da apresentação: [apresentacao.md](apresentacao.md).

## Arquivos

```
simulator/
├── index.js        # linha de comando: cenários (loop, --ciclos, --seed), modo controle, broker
├── borda.js        # processamento: modelo + episódios + gatilho; publica estado/alertas/historico
├── historico.js    # histórico em data/historico_<id>.json (gravação atômica) e último reset aplicado
├── resetar.js      # npm run resetar: apaga tudo antes de uma apresentação (pulseira, broker, app, site)
├── trava.js        # data/pulseira_<id>.lock: o reset recusa apagar com a pulseira rodando
├── config.js       # leitura do simulator/.env (pulseira e reset)
├── controle.js     # modo controle: segue os valores do painel, com rampa de 20 s
├── scenarios.js    # cenários, variação entre ciclos e eventos_aleatorios
├── gabarito.js     # gabarito dos testes: logs/eventos_<data-hora>.csv e .json
├── verificar.js    # confere os cenários (em loop) com o processamento da pulseira, sem broker
├── testes/         # npm test (node:test, cliente MQTT falso: sem broker)
├── data/           # histórico de episódios (local, fora do Git)
├── logs/           # gabaritos gravados pelo simulador (locais, fora do Git)
└── .env.example    # modelo do simulator/.env (broker, usuário, CHILD_ID)
```

A pulseira roda os módulos de `frontend/src/model/` (modelo, episódios,
gatilho, gerador de leituras) e as mensagens de `frontend/src/hooks/`
(`buildMessages.js`, `parseMessages.js`), sem cópia de código.
`tools/verificar-app.mjs` (`npm run verificar-app`) faz o papel do app pelo
terminal.

## Como funciona

A pasta `simulator/` faz o papel do ESP32. A cada segundo ela:

1. gera uma leitura dos sensores (mesmo gerador de sempre,
   `frontend/src/model/simulate.js`), seguindo um cenário ou, no modo
   controle, os valores do painel;
2. roda o modelo, os episódios e o gatilho (`simulator/borda.js`, com os
   módulos de `frontend/src/model/`);
3. publica:
   - `leituras` (QoS 0), para os gráficos do painel;
   - `estado` (1×/s, retain);
   - `alertas` (QoS 1), na mudança de nível;
   - `historico` (retain), quando um episódio abre, fecha ou é avaliado;
   - `status`: `online` retido ao conectar, `offline` ao sair com Ctrl+C ou
     como Last Will se o processo cair.

Ela assina `ack` e `avaliacao` (e `controle` no modo controle) e aplica no
histórico o "Estou ciente" e a avaliação que chegam do app ou do painel.
Também assina `comando`, a ordem de reset do `npm run resetar` (ver
[Resetar para uma apresentação](apresentacao.md#resetar-para-uma-apresentação)).

**Histórico local.** Os episódios ficam em `simulator/data/historico_<id>.json`
(fora do Git). Ao iniciar sem esse arquivo, a pulseira recupera o histórico da
mensagem retida em `historico`, mas só se ela tiver sido publicada pela
própria pulseira (`origem: "pulseira"`). Ao encerrar com Ctrl+C, fecha o
episódio aberto como "interrompido" e publica o histórico final. Para começar
do zero:
- `npm start -- --limpar-historico`: apaga a lista e publica a lista vazia,
  também para o app;
- `npm run resetar`: apaga também os dados do app e do site, com a pulseira
  desligada.

Enquanto roda, a pulseira mantém a trava `data/pulseira_<id>.lock`, que é
removida ao encerrar.

Configuração (uma vez), dentro de `simulator/`:

```bash
cd simulator
npm install
copy .env.example .env      # Windows (Linux/macOS: cp .env.example .env)
```

Depois preencha `MQTT_USER` e `MQTT_PASS` no `simulator/.env` com o usuário
da pulseira no EMQX Cloud. O `CHILD_ID` precisa ser igual ao `VITE_CHILD_ID`
do `frontend/.env` e ao `CHILD_ID` do `mobile/env.json`. O `.env` não vai
para o Git.

Rodando:

```bash
npm start -- --cenario crise_ruido                    # ou o atalho: npm run crise-ruido (loop até o Ctrl+C)
npm run crise-ruido -- --ciclos 3 --seed 42           # 3 ciclos reproduzíveis e encerra
npm run crise-ruido -- --uma-vez --idade 10           # só o roteiro nominal, uma vez; idade de 5 a 12
npm run eventos-aleatorios -- --ciclos 20 --seed 42   # 20 eventos sorteados (teste do TCC)
npm run demo -- --ciclos 1                            # sequência da apresentação (10,5 min + pausa final)
npm run controle                                      # modo controle: segue o "Controle da pulseira" do painel
npm run resetar                                       # apaga tudo antes de uma apresentação (pulseira desligada)
npm test                                              # testes da pulseira e do reset (sem broker)
```

Cada leitura impressa no terminal traz o nível calculado na pulseira
(`normal 12%`, `ATENÇÃO 64%`, `CRISE 91%`, ou `coletando` nos primeiros 30 s).
Alertas, avaliações e publicações do histórico aparecem em linhas próprias.

## Modo controle (`npm run controle`)

Em vez de um cenário, a pulseira segue os valores-alvo que o painel do site
publica em `puzzleband/<id>/controle`: BPM, EDA, HRV, movimento,
regularidade, luz, ruído e idade.

- **Transições:** cada sinal chega ao novo valor numa rampa de 20 s, com o
  mesmo ruído de sensor do gerador. A idade muda na hora.
- **Sem comando:** fica no estado calmo.
- **Validação:** valores fora das faixas dos controles são ignorados, um a
  um. JSON inválido é descartado.
- **Fonte:** o estado sai com `fonte: "manual"` (o app mostra "Simulador
  manual").
- **Quando para:** não há ciclos nem gabarito. Roda até o Ctrl+C (ou
  `--duracao`).
- **Pulseira desligada:** o painel avisa "Inicie a pulseira com npm run
  controle para usar estes controles". O painel publica no máximo 2×/s.

Formato e faixas: [docs/mqtt.md](mqtt.md#controle-site--pulseira-modo-controle).

## Loop (padrão) e opções

Todo cenário roda em **loop** até o Ctrl+C. Quando o roteiro termina (todos
os sinais de volta ao calmo), vem uma **pausa calma** e começa um novo ciclo
do mesmo cenário. A pausa (padrão 120 s) é o tempo para:

1. o episódio anterior fechar na pulseira: o modelo ainda alerta ~20–25 s depois
   de a fisiologia normalizar, e o episódio só fecha após 30 s seguidos em
   baixo risco;
2. a linha de base ambiental da regra de gatilho se restabelecer (≥ 60 s de
   leituras calmas antes da janela de análise).

O 1º ciclo é o roteiro nominal, com os 2 minutos calmos iniciais. É o mesmo
do `--uma-vez` e das tabelas do [docs/testes.md](testes.md). A partir do
2º ciclo, cada um varia um pouco. Os limites foram conferidos para manter o
resultado esperado (`npm run verificar`):

| O que varia | Quanto |
|---|---|
| Intensidade do pico (BPM, EDA, HRV e movimento; luz e ruído com sorteio próprio) | ±15% |
| Duração de cada fase (subida, platô, descida) | ±20% |
| Subida da fisiologia nas crises (sorteio próprio, como no gerador do dataset v4) | 70% súbita (5 a 15 s), 30% gradual (40 a 90 s); o platô compensa, e a duração do roteiro não muda |
| Antecedência do sinal ambiental (cruzar o limite da regra → início da fisiologia) | 8 a 15 s |

No terminal, cada ciclo começa com uma linha destacada e a variação sorteada.
Cada leitura continua com o nome da fase (trecho real de
`npm run crise-ruido -- --seed 42`):

```
=== Ciclo 3 · crise_ruido ===
    roteiro crise_ruido · pico ×1,06 · subida gradual 42 s · platô 54 s · descida 35 s · ambiente ×1,08 · antecedência ~14 s
[10:56] bpm  79  eda  4.03  hrv  53.0  gyro   2.4  reg 0.18  luz  292  ruido  44.0 | ruído subindo
...
[13:26] bpm  77  eda  3.79  hrv  57.0  gyro   8.1  reg 0.12  luz  303  ruido  44.8 | pausa calma (recuperação) · ciclo 4 em 120 s
```

| Opção | O que faz |
|---|---|
| `--uma-vez` | Só o roteiro nominal, uma vez, e encerra (como antes do loop) |
| `--ciclos N` | Roda N ciclos (no `eventos_aleatorios`, N eventos) e uma pausa final, para o último episódio fechar, e encerra |
| `--pausa S` | Pausa calma entre ciclos, em segundos (padrão 120; mínimo 90: abaixo disso o simulador avisa e usa 90). No `eventos_aleatorios`, a pausa é sorteada entre S e 2×S |
| `--seed N` | Semente do sorteio e do ruído dos sensores: a mesma seed repete a mesma sequência de ciclos ou eventos e as mesmas leituras. Sem `--seed`, uma é sorteada e impressa no início |
| `--idade A` | Idade da criança, de 5 a 12 anos (padrão 8) |
| `--duracao S` | Para depois de S segundos, em qualquer modo |
| `--limpar-historico` | Começa com o histórico de episódios vazio (apaga a lista do `data/historico_<id>.json` e publica a lista vazia). Para apagar também o app e o site: `npm run resetar` |

O `barulho_sem_crise` (e o `ambiente_sem_crise` do `eventos_aleatorios`) usa
pausa de pelo menos **300 s** depois dele. Como a criança fica calma, as
leituras barulhentas entram na linha de base de 5 min da regra de gatilho, e
ela precisa desse tempo para voltar ao ambiente calmo (ver
[docs/testes.md](testes.md#teste-com-eventos-aleatórios)).

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
| `controle` | `npm run controle` | Segue os valores-alvo do "Controle da pulseira" do painel; sem comando, fica calmo (ver acima) | sem fim |

Os cenários isolados começam com **2 minutos calmos** (linha de base da regra
de gatilho); a `demo` começa com 60 s. As transições são rampas de 20 a 40 s,
menos a subida da fisiologia nas crises: no 1º ciclo (nominal) ela é súbita,
em 10 s, e nos seguintes é sorteada (tabela acima). O exercício e a
estereotipia continuam subindo aos poucos (40 s).
A linha do tempo do roteiro aparece no início da execução, e cada leitura é
impressa com a fase atual. Em loop, cada ciclo dura o trecho ativo do roteiro
(~2,5 a 4 min) mais a pausa.

Com `crise_ruido`, o alerta (no app e no painel) deve indicar "Provável
gatilho: ruído"; com `crise_luz`, "luminosidade"; com `crise_sem_gatilho`,
"Sem gatilho ambiental aparente". Os episódios aparecem no histórico, um por
ciclo.

## Cenário `eventos_aleatorios`

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
    roteiro crise_luz · pico ×0,67 · subida gradual 81 s · platô 20 s · descida 36 s · ambiente ×1,02 · antecedência ~8 s
[56:53] bpm  79  eda  4.12  hrv  53.2  gyro   3.0  reg 0.17  luz  295  ruido  44.8 | luz subindo
...
[59:18] bpm  79  eda  3.82  hrv  55.1  gyro   7.6  reg 0.11  luz  293  ruido  46.4 | pausa calma (recuperação) · evento 12 em 125 s
```

## Gabarito dos testes (`simulator/logs/`)

Toda execução de cenário grava `simulator/logs/eventos_<data-hora>.csv` (e `.json`), com
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

O CSV segue o formato do CSV do histórico exportado pelo painel (`;`,
vírgula decimal, UTF-8 com BOM), para comparar os dois no Excel. Passo a passo:
[docs/testes.md](testes.md#teste-com-eventos-aleatórios).

## Verificação sem broker

`npm run verificar` confere os cenários contra o modelo e a regra de gatilho
**sem broker**, em segundos, passando pelo mesmo processamento que a pulseira
roda ao vivo (`createEdgeProcessor`, em `borda.js`). Ele roda cada cenário em loop (3 ciclos, 20
sementes) e o `eventos_aleatorios` com seed fixa, comparando o gabarito com
os episódios detectados. `node verificar.js --uma-vez` repete a verificação
antiga, só com o roteiro nominal. Resultados esperados × obtidos e o roteiro
da apresentação: [docs/testes.md](testes.md).

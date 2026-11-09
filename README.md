# Puzzle Band

Sistema *wearable* de monitoramento sensorial e auxílio na identificação de
gatilhos de estresse no Transtorno do Espectro Autista (TEA) — TCC
(Bacharelado em Ciências da Computação, modalidade Empreendedor).

O projeto tem quatro partes, ligadas por um broker MQTT na nuvem (EMQX
Cloud):

- **Pulseira** (`simulator/`, faz o papel do ESP32) — gera as leituras dos
  sensores e **processa ali mesmo** (processamento na borda): roda o modelo,
  a regra de gatilho e o histórico de episódios, e publica o resultado pronto
  para o app. Guarda o histórico num arquivo local. Roda cenários prontos ou,
  no modo controle, segue os valores enviados pelo painel do site.
- **App do cuidador** (`mobile/`) — app Android em Flutter: estado ao vivo,
  notificação com som nos alertas, botão "Estou ciente", painel com os
  episódios do dia, histórico com avaliação do gatilho (que volta para a
  pulseira) e lembretes do cuidador, que ficam só no celular.
- **Site / painel do desenvolvedor** (`frontend/`, **opcional**) — dashboard
  em React só de visualização e controle: mostra o que a pulseira publica
  (nível, probabilidade, gatilho, gráficos, histórico, status do app) e, no
  "Controle da pulseira", envia os valores-alvo de BPM, EDA, HRV, movimento,
  luz, ruído e idade. Não roda o modelo.
- **Modelo preditivo** (`model/`) — classificador em Python (Random
  Forest) que cruza os sinais e estima a probabilidade de uma possível
  crise. É treinado em Python e exportado como JSON; a inferência roda
  em JavaScript, na pulseira.

```
                 (tudo passa pelo broker MQTT, EMQX Cloud)

pulseira    ──── estado · alertas · historico ─────────────▶ app do cuidador
(modelo,    ◀─── ack · avaliacao ───────────────────────────
 episódios,
 gatilho)   ──── leituras + estado · alertas · historico ──▶ site / painel (opcional)
            ◀─── controle · avaliacao ──────────────────────
```

**A pulseira é obrigatória; o site é opcional.** O app do cuidador funciona
com o site fechado. Na primeira versão o site rodava o modelo; agora o
processamento fica na pulseira (processamento na borda), como seria no
ESP32: trafega só o resultado, e o histórico detalhado fica no aparelho
(LGPD). Rodar o Random Forest no ESP32 real (TinyML) fica como trabalho
futuro. Por quê, tópicos, formatos, QoS e ACL: [docs/mqtt.md](docs/mqtt.md).

## Funcionalidades

Na pulseira:

- **Previsão de possível crise:** o Random Forest estima a probabilidade a
  cada segundo e a converte em faixas (sem sinais de crise / atenção /
  possível crise). [docs/modelo.md](docs/modelo.md)
- **Gatilho provável:** quando o modelo alerta, uma regra explicável compara
  luz e ruído dos últimos 60 s com a linha de base da criança e verifica se
  a mudança veio **antes** da alteração fisiológica. Exemplo: *"Provável
  gatilho: ruído (45 → 88 dB, cerca de 12 s antes da alteração
  fisiológica)"*. [docs/gatilho.md](docs/gatilho.md)
- **Histórico de episódios** (do alerta até 30 s de volta ao normal) em
  `simulator/data/historico_<id>.json`, com duração, nível e probabilidade
  máximos e gatilho provável. [docs/historico.md](docs/historico.md)
- **Sincronia com o app:** estado ao vivo 1×/s, alertas na mudança de nível
  e os 50 últimos episódios; recebe o "Estou ciente" e a avaliação do
  gatilho (do app ou do site). [docs/mqtt.md](docs/mqtt.md)

No site (opcional): tudo o que a pulseira publica (nível, banner de alerta
com o gatilho, "Alerta visto pelo cuidador", sensores, gráfico, histórico
com resumo de padrões e CSV, "Pulseira: online/offline" e "App do cuidador:
conectado"), **Confirmar / Descartar** um gatilho e o **Controle da
pulseira**, que publica os valores-alvo em `puzzleband/<id>/controle` (no
máximo 2×/s) para a pulseira rodando com `npm run controle`.

## Estrutura do projeto

```
puzzle-band/
├── data/raw/      # dataset sintético v4 (.xlsx) usado pra treinar
├── model/         # treino em Python (features.py, train.py, gerar_dataset_v4.py) — docs/modelo.md
├── simulator/     # a pulseira (ESP32 simulado), com processamento na borda — docs/pulseira.md
├── tools/         # verificar-app.mjs: faz o papel do app pelo terminal
├── mobile/        # app do cuidador (Flutter, Android) — docs/app.md
├── frontend/      # painel do site (React, opcional)
│   ├── src/components/, src/hooks/  # UI; MQTT do painel (useBandLink, useControlSender); mensagens (parse/buildMessages), usadas também pela pulseira
│   ├── src/model/  # módulos que a PULSEIRA roda: forest.json, predict.js, simulate.js, trigger.js, episodes.js
│   └── scripts/cenarios.mjs  # cenários de ponta a ponta com o modelo real
└── docs/          # documentação detalhada (ver abaixo)
```

## Como rodar

Pré-requisitos: **Node.js** (pulseira e painel), **Flutter** + **Android
Studio** (app) e **Python 3** só para treinar o modelo. No Windows, confira
com `node --version` e `python --version` no PowerShell.

1. **Pulseira (obrigatória)**, em `simulator/`:

   ```bash
   cd simulator
   npm install
   copy .env.example .env      # só na primeira vez (Linux/macOS: cp .env.example .env)
   npm run crise-ruido         # um cenário (loop até o Ctrl+C)
   npm run controle            # ou: segue o "Controle da pulseira" do painel
   ```

   No `simulator/.env`, preencha `MQTT_USER` e `MQTT_PASS` (usuário da
   pulseira no EMQX Cloud). O `CHILD_ID` precisa ser o mesmo do
   `mobile/env.json` e do `frontend/.env`. Cenários e opções:
   [docs/pulseira.md](docs/pulseira.md).
2. **App do cuidador**, em `mobile/`: copie `env.example.json` para
   `env.json`, preencha `MQTT_PASS` (usuário `app`) e rode com
   `flutter run --dart-define-from-file=env.json`. Android Studio, emulador
   e celular: [docs/app.md](docs/app.md#como-rodar).
3. **Painel (opcional)**, em `frontend/` (é onde fica o `package.json`):

   ```bash
   cd frontend
   npm install
   copy .env.example .env      # só na primeira vez; preencha VITE_MQTT_PASS (usuário dashboard)
   npm run dev                 # abre em http://localhost:5173 (o terminal mostra o endereço)
   npm run build               # versão de produção (dist/); npm run preview serve ela
   ```

Para uma apresentação (apagar dados antigos com `npm run resetar` e os
roteiros de demonstração): [docs/apresentacao.md](docs/apresentacao.md).

## Testes

| Onde | Comando | O que testa |
|---|---|---|
| `frontend/` | `npm run lint` e `npm test` | regra do gatilho, histórico, mensagens MQTT e cenários de ponta a ponta com o modelo real |
| `frontend/` | `node scripts/cenarios.mjs [--sementes 50]` | relatório dos cenários ([docs/gatilho.md](docs/gatilho.md#resultado-dos-testes)) |
| `simulator/` | `npm test` | a pulseira e o reset sem broker (cliente MQTT falso) |
| `simulator/` | `npm run verificar` | os cenários contra o modelo e a regra, sem broker ([docs/testes.md](docs/testes.md)) |
| `mobile/` | `flutter analyze` e `flutter test` | parse, telas, acessibilidade e imagens (golden) |

## Treinando o modelo

O projeto já vem com o modelo treinado (`frontend/src/model/forest.json`).
Para gerar outro, na raiz: `pip install pandas numpy scikit-learn openpyxl` e
`python model/train.py`; depois, reinicie a pulseira para ela carregar o
modelo novo. Detalhes: [docs/modelo.md](docs/modelo.md).

## Documentação

| Documento | Conteúdo |
|---|---|
| [docs/pulseira.md](docs/pulseira.md) | Pulseira simulada: cenários, modo controle, loop e opções, eventos aleatórios, gabarito e verificação sem broker |
| [docs/apresentacao.md](docs/apresentacao.md) | Reset para uma apresentação e roteiros de demonstração (com o app e do cenário `demo`) |
| [docs/mqtt.md](docs/mqtt.md) | Processamento na borda (por quê), tópicos (quem publica/assina, QoS, retain), formatos das mensagens e ACL sugerida |
| [docs/modelo.md](docs/modelo.md) | Modelo preditivo: decisões de design, validação, ablação, importância das features e modelo em produção |
| [docs/gatilho.md](docs/gatilho.md) | Gatilho provável: algoritmo, limites e por quê, testes e limitações |
| [docs/historico.md](docs/historico.md) | Histórico de episódios: campos, avaliação do cuidador, CSV e privacidade (LGPD) |
| [docs/testes.md](docs/testes.md) | Testes automatizados, cenários × resultado esperado × obtido (uma vez e em loop), eventos aleatórios e verificação com o app |
| [docs/app.md](docs/app.md) | App do cuidador: telas, `env.json`, como rodar (emulador e celular) e limitações |
| [docs/design-app.md](docs/design-app.md) | Design do app (UX/UI): paleta com contrastes, tipografia, acessibilidade para o TEA e antes/depois de cada tela |
| [docs/avaliacao_dataset.md](docs/avaliacao_dataset.md) | Avaliação do dataset sintético original (registro histórico) |

## Créditos

As telas do app do cuidador (home, gráficos, configurações e um login só visual, removido em 11/2026) vieram do
repositório [mariafernandarsantos/puzzleband](https://github.com/mariafernandarsantos/puzzleband)
(pasta `frontend/`, Flutter). Aqui os dados fixos foram trocados pelos dados
recebidos da pulseira via MQTT, e o visual foi redesenhado para o público do TEA
([docs/design-app.md](docs/design-app.md)).


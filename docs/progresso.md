# Progresso da limpeza (branch `limpeza`)

Registro para retomar o trabalho se a sessão for interrompida. Objetivo:
enxugar o projeto (código mais limpo e leve) **sem perder funcionalidade nem
mudar comportamento**. Regras: sem commit; não mexer em `.env` nem em
`mobile/env.json`; `.claude/` continua no `.gitignore`; tópicos MQTT, formatos,
regras de episódio e de gatilho, telas e textos visíveis não mudam; parar para
aprovação no fim de cada etapa.

## Situação

| Etapa | Situação |
|---|---|
| 1. Inventário (só leitura) | concluída e aprovada |
| 2. Remoções aprovadas — parte 1 | concluída (commit `660a35e`) |
| 2. Remoções aprovadas — parte 2 | concluída e aprovada (sem commit) |
| 2. Remoções aprovadas — partes 2 e 3 | concluídas (commit `9ca0a01`) |
| 3. Simplificação do código | não iniciada |
| 4. Modelo mais simples | **concluída — aguardando revisão** (modelo mantido e compactado; sem commit) |
| 5. Relatório final | não iniciada |

## Ponto de partida

- Branch `limpeza` (já existia), HEAD `9f7f8aa` ("npm run resetar").
- Atualização: o usuário commitou essas alterações em `b8a5f14` ("Reset
  completo: pulseira, broker e app"). A Etapa 2 parte de `b8a5f14`.
- **Alterações não commitadas que já estavam na árvore antes da limpeza**
  (28 arquivos, +1.174/−79 linhas: configuração do broker no app, mensagens
  do site, docs, 5 goldens de Ajustes). Fazem parte da linha de base e não
  são da limpeza. Cópia de segurança (fora do repo):
  `C:\Users\muril\AppData\Local\Temp\claude\b5482cacf0edafbe\0c3f5ef8-564c-4f0f-82e4-542346fac298\scratchpad\alteracoes-pre-existentes.patch`
  (`git apply` recupera). Entre elas estão `mqtt_service.dart` e
  `configuracoes_screen.dart`: refatorar esses dois só depois do seu commit.

## Linha de base (07/11/2026, antes de qualquer mudança)

Saídas em `linha-de-base/*.log` (ignoradas pelo `*.log` do `.gitignore`).

| Verificação | Comando | Resultado |
|---|---|---|
| Lint do site | `frontend: npm run lint` | OK (0 avisos) |
| Testes do site | `frontend: npm test` | 67/67 |
| Build do site | `frontend: npm run build` | OK (JS 37,7 + 218,9 + 330,2 kB) |
| Testes do simulador | `simulator: npm test` | 30/30 |
| Verificação offline | `simulator: node verificar.js` (seeds fixas: loop 1–20, eventos 42, agregado 1–50) | sai com 1: **FALHOU exercicio, barulho_sem_crise, demo** — igual ao `docs/testes.md` (linhas 208–246); critério da limpeza = saída **idêntica** |
| idem, Markdown | `node verificar.js --markdown` | sai com 1 (mesmo motivo) |
| idem, uma vez | `node verificar.js --uma-vez --sementes 50` | sai com 1 (mesmo motivo) |
| Cenários do site | `frontend: node scripts/cenarios.mjs` | OK |
| verificar-app | `node --check tools/verificar-app.mjs` | OK (precisa de broker para rodar de verdade) |
| Análise do app | `mobile: flutter analyze` | No issues found |
| Testes do app | `mobile: flutter test` | 205/205 |
| Goldens / forest.json | `sha256sum` | `linha-de-base/goldens-sha256.log` |

Tamanho: 379 arquivos rastreados (43,8 MB); `.git` com 27 MB.

## Etapa 1 — Inventário

Evidência de uso: `git grep` no repositório inteiro (código, testes e docs).
`oxlint` em todo o JS (48 arquivos, regra `no-unused-vars`): 0 avisos;
`flutter analyze`: 0 — **não há imports nem variáveis sem uso**; o código morto
que existe são exports que ninguém importa.

### Remover

| ID | O quê | Prova | Ganho |
|---|---|---|---|
| R1 | `data/processed/` (`sample_C01.json`, `sample_C05.json`) | 0 referências a `sample_C0`/`data/processed` | 2 arq., 0,3 MB |
| R2 | `frontend/src/assets/` (hero.png, react.svg, vite.svg) e `frontend/public/icons.svg` | 0 referências (sobras do template do Vite; o `favicon.svg` fica, o `index.html` usa) | 4 arq., 31 KB |
| R3 | `mobile/lib/screens/gps_screen.dart` | só citado em comentário (`main.dart:162`) e em `docs/app.md:101`; fora da navegação | 23 linhas |
| R4 | Código morto JS: `toHistory` (`trigger.js:492-497`, utilitário fora da regra: limites e textos intactos), `scenarioAt` (`scenarios.js:588-592`), `STATE_INTERVAL_MS` (`buildMessages.js:12`) | 1 ocorrência cada (só a declaração) | ~15 linhas |
| R5 | Pastas `mobile/ios`, `linux`, `macos`, `windows`, `web` + exclusões delas no `analysis_options.yaml` | nenhum código as usa; app só Android (o código de notificação nem configura iOS/Linux) | 102 arq., ~400 KB |
| R6 | Datasets v1, v2, v3 (`data/raw/*.xlsx`) | só lidos por `model/eda/01–08` (caminhos fixos `/home/user/...`, não rodam aqui) e citados como exemplo do treino incremental. Os números v2/v3 do `docs/modelo.md` dependem do `features.py` antigo: v2/v3 não têm as colunas de HRV, acelerômetro e ambiente que o `features.py` atual exige, então manter os .xlsx **não** os torna reproduzíveis. (Correção: a linha "12 antigas" da ablação é um subconjunto das 24 features atuais, logo **é** reproduzível no v4; só falta script — Etapa 4.) | 3 arq., 19,3 MB |
| R7 | `model/eda/01–09` | análise do dataset original e geradores v2/v3/massivo; dependem de R6; caminhos absolutos | 9 arq., ~1.000 linhas |
| R8 | `model/train_incremental.py` e `model/state/` | experimental; a floresta dele (80 árvores) **não** é a de produção; rodá-lo sobrescreve o `forest.json` oficial | 3 arq., 1,5 MB |
| R9 | 36 dos 85 goldens (lista abaixo) | cobertura mantida pelos testes de acessibilidade (contraste AA, toque ≥ 48 dp, rótulos em todas as telas, claro e escuro) e de fonte 1,3× (8 estados × 4 abas, sem texto cortado) | 36 arq., 4,8 MB |
| R10 | `@types/react`, `@types/react-dom` (devDependencies do site) | sem TypeScript nem `jsconfig`; build, lint e testes não usam | 2 dependências |
| R11 | Linha `Skills Claude/` do `.gitignore` | a pasta não existe | 1 linha |

**R9 — goldens que ficam (49):** claro (26): login, inicio_calmo,
inicio_atencao, inicio_possivel_crise, inicio_possivel_crise_ciente,
inicio_bpm_190, inicio_painel_aberto, inicio_painel_vazio, inicio_sem_conexao,
inicio_painel_e_pulseira_offline, inicio_erro_configuracao, episodio_detalhe,
lembrete_editor, graficos, graficos_balao, graficos_7dias,
graficos_painel_parado, graficos_sem_dados, historico,
historico_cartao_expandido, historico_pendente, historico_descartado,
historico_filtro_dia, historico_vazio, historico_sem_conexao, ajustes ·
escuro (14): login, inicio_calmo, inicio_atencao, inicio_possivel_crise,
inicio_painel_aberto, inicio_sem_conexao, episodio_detalhe, graficos,
graficos_balao, graficos_7dias, historico, historico_cartao_expandido,
historico_descartado, ajustes · fonte 1,3× (9): login,
inicio_possivel_crise_inteira, inicio_painel_aberto, inicio_bpm_190, graficos_balao,
graficos_7dias, historico, historico_expandido, ajustes.

**R9 — saem (36):** inicio_bpm_79, inicio_nome_padrao, inicio_conectando,
graficos_ruido, historico_lista, ajustes_erro_configuracao; escuro: as 7
métricas (eda, hrv, luz, movimento, probabilidade, regularidade, ruido),
inicio_bpm_190, inicio_possivel_crise_ciente, inicio_painel_vazio,
inicio_conectando, inicio_painel_e_pulseira_offline, inicio_erro_configuracao,
lembrete_editor, graficos_painel_parado, graficos_sem_dados, historico_lista,
historico_pendente, historico_filtro_dia, historico_vazio,
historico_sem_conexao, ajustes_erro_configuracao; fonte 1,3×: inicio_calmo,
inicio_atencao, inicio_possivel_crise, inicio_possivel_crise_ciente,
inicio_painel_vazio, inicio_sem_conexao, graficos, historico_vazio. Os testes
correspondentes saem do `goldens_test.dart`; 3 células de
`docs/design-app.md` (linhas 356, 485, 532) apontam para imagens que saem e
serão ajustadas.

**R5 — recriar se precisar:** `cd mobile` e
`flutter create --platforms=ios,linux,macos,windows,web --org br.unimar --project-name puzzleband .`
(só cria o que falta; não mexe em `lib/` nem em `android/`). Impacto: só
`flutter run -d windows/chrome/...` deixa de funcionar; build Android,
`analyze` e `test` não usam essas pastas.

**R6 — histórico:** os arquivos continuam no git; por exemplo
`git show 9f7f8aa:data/raw/dataset_pulseira_TEA_estresse_v3.xlsx > v3.xlsx`.

### Simplificar

| ID | O quê | Como | Ganho |
|---|---|---|---|
| S1 | Comentários de fases antigas ("o site publica/processa") | app: `models.dart:1,321`, `resumo.dart:1`, `sinais.dart:38,196`, `historico_screen.dart:17`, `mqtt_service.dart:57,106,137,412,421,593`, `gatilho_simples.dart:6-7`, `painel_do_dia.dart:13`, `cartao_episodio.dart:149`; `train.py` (docstring: "dashboard", 4 faixas); `mobile/README.md` ("Recebe tudo do site") | só comentários |
| S2 | Duplicações JS → módulo compartilhado | gerador com semente `seeded`/`withRandom` (`scenarios.js` e `frontend/scripts/cenarios.mjs`) → `frontend/src/model/aleatorio.js`; `TIER_RANK` (`episodes.js` e `verificar.js`) → export do `episodes.js`; tempo `[mm:ss]` (`index.js` `formatElapsed` e `verificar.js` `mmss`, "mesmo formato") e decimais com vírgula (`fmt`, `dec`, `fmtFactor`) → `simulator/formato.js` | ~60 linhas |
| S3 | Arquivos grandes | ver tabela "Divisão" | legibilidade |
| S4 | `model/eda/10_generate_dataset_v4.py` | vira `model/gerar_dataset_v4.py`, com caminho relativo ao repo (hoje `/home/user/...`), como no `train.py` | pasta `eda/` some |
| S5 | `pubspec.yaml`: `description: "A new Flutter project."` | descrição real (metadado, não aparece no app) | — |
| S6 | README (703 linhas) | ~150 linhas: o que é, arquitetura, como rodar cada parte, testes e tabela de docs. "Pulseira simulada" (cenários, loop, opções, eventos, gabarito) → novo `docs/pulseira.md`; "Roteiro de demonstração" + "Resetar para uma apresentação" + o roteiro do `docs/testes.md` → novo `docs/apresentacao.md` (hoje o roteiro está em 2 lugares); "Treinando o modelo" e "App do cuidador" já estão em `docs/modelo.md` e `docs/app.md` | −550 linhas no README |
| S7 | `docs/modelo.md` | sai a seção do treino incremental e a história "60 × 80" (com R8); linhas v2/v3 marcadas como históricas | −60 linhas |
| S8 | `docs/avaliacao_dataset.md` | mantém (narrativa v1→v2 do TCC) com nota "histórico; datasets no git" | — |
| S9 | `mobile/README.md` | 10 linhas apontando para `docs/app.md` | −20 linhas |

**Divisão dos arquivos grandes (S3)** — os nomes públicos continuam
importáveis dos mesmos caminhos (reexport), então testes e imports não mudam:

| Arquivo | Linhas | Mistura | Proposta |
|---|---|---|---|
| `simulator/scenarios.js` | 769 | blocos de sinal, catálogo de roteiros, eventos aleatórios, gerador com semente, montagem do programa | `scenarios/sinais.js`, `scenarios/roteiros.js`, `scenarios/eventos.js`, `scenarios/programa.js`; `scenarios.js` reexporta |
| `simulator/verificar.js` | 726 | simulação, estatística/formatação de tabelas, expectativas, laço, eventos aleatórios, CLI | `verificar/tabela.js` (printTable, range, median…), `verificar/esperado.js` (EXPECTED, LOOP_EXPECTED), `verificar/aleatorio.js`; `verificar.js` fica com simulação, laço e CLI. Saída byte a byte igual |
| `simulator/index.js` | 523 | argumentos (~100 linhas) + terminal + laço | `simulator/argumentos.js`; formatação vai para `formato.js` (S2) |
| `simulator/resetar.js` | 542 | uma ferramenta só, bem seccionada; os testes importam as funções | **manter** |
| `frontend/src/model/trigger.js` | 497 | é a regra (congelada) | **manter**; só R4 |
| `frontend/src/model/episodes.js` | 402 | detecção (pulseira) + persistência (pulseira) + resumo e CSV (site) | `episodes.js` (monitor e lista), `episodeStorage.js` (load/save/normalize/store), `episodeReport.js` (resumo e CSV) |
| `tools/verificar-app.mjs` | 757 | esquemas (espelho do Dart) + sessão MQTT + relatório | `tools/formatos-do-app.mjs` com os esquemas e `validar`; o resto fica |
| `mobile/.../graficos_screen.dart` | 898 | tela + gráfico ao vivo (seletor, trackball, balão, legenda, resumo) + gráfico de 7 dias | `widgets/grafico_sinais.dart` (~600) e `widgets/grafico_sete_dias.dart` (~180); a tela fica com ~60 linhas e reexporta |
| `mobile/.../faixa_estado.dart` | 437 | lógica de situação (usada por 3 telas) + faixa + `_LinhaBpm` (220 linhas de medida de layout) | `models/situacao.dart` (`SituacaoEstado`, `situacaoDe`) e `widgets/linha_bpm.dart` (com as chaves de teste); reexport |
| `mobile/.../mqtt_service.dart` | 664 | uma classe com conexão, recebimento, reset, notificação e persistência | **manter** agora (tem alterações suas não commitadas; Dart não divide classe entre arquivos sem `part`); só S1 |

### Manter (com motivo)

| ID | O quê | Motivo |
|---|---|---|
| M1 | `frontend/scripts/cenarios.mjs` (+ teste) | roda no `npm test`; números citados em `docs/gatilho.md` e `README`; passa a usar S2 |
| M2 | Conexão MQTT em `index.js`, `resetar.js`, `verificar-app.mjs` | opções diferentes de propósito (Last Will/keepalive, MQTT 5 para motivo da ACL, reconexão) |
| M3 | Tópicos e esquemas próprios no `verificar-app.mjs` | ele imita o app (espelho de `models.dart`) de propósito |
| M4 | `features.py` ↔ `predict.js` | treino e inferência precisam calcular igual (Etapa 4 mexe nos dois) |
| M5 | `docs/design-app.md`, `docs/figma/`, `docs/imagens/app-antes/` | antes/depois do redesign (documentação do TCC) |
| M6 | `.mcp.json` | configura o MCP do Figma usado no design |
| M7 | Dependências | todas usadas: `mqtt`, `react`, `react-dom`, `vite`, `@vitejs/plugin-react`, `oxlint`, `dotenv`; Flutter: `flutter_local_notifications`, `intl`, `mqtt_client`, `shared_preferences`, `syncfusion_flutter_charts`, `timezone` |
| M8 | CSS do site | todas as classes usadas (`band-controls__notice--*` é montada no `BandControls.jsx`) |

### Fora do escopo — decisão sua

- **D1. Texto visível desatualizado** em Ajustes:
  "Painel (site): … O modelo roda no site: ele precisa estar aberto."
  (`configuracoes_screen.dart:113`). Hoje o modelo roda na pulseira. Mudar
  altera um texto visível e 3 goldens (ajustes, escuro_ajustes,
  fonte_130_ajustes): só com o seu pedido.
- **D2.** O `verificar.js` já falha na linha de base (exercicio,
  barulho_sem_crise, demo), como documentado. A limpeza mantém a saída
  idêntica; a Etapa 4 pode melhorar o barulho_sem_crise (o modelo reage à luz
  e ao ruído).
- **D3.** O `.git` (27 MB) não diminui com remoções: os arquivos ficam no
  histórico. Encolher exigiria reescrever o histórico (não recomendado).
- **D4.** O `simulator/` e o `tools/` não têm lint próprio (o `oxlint` do
  `frontend/` passou neles na inspeção, 0 avisos).

## Etapa 4 — preparação (para quando chegar lá)

- O Python daqui não tem scikit-learn: criar um venv no scratchpad
  (`pandas scikit-learn openpyxl numpy`), sem tocar no Python global.
- Primeiro conferir se o `train.py` reproduz as 60 árvores do `forest.json`
  atual com a versão instalada; se não, a variante (a) é o retreino com a
  mesma versão, e o `forest.json` atual entra como referência.
- Comparação por episódio: rodar o `verificar.js` numa cópia do
  `simulator/` + `frontend/src` no scratchpad, trocando só o `forest.json` e o
  `predict.js`.
- Dá para reproduzir também a linha "12 antigas" da ablação do
  `docs/modelo.md`, que hoje não tem script.

## Decisões do usuário

- **07/11/2026 — Etapa 2, parte 1:** aprovados R1–R11, S1, S4, S5, S7, S8,
  S9 e D1 (corrigir o texto de Ajustes e os 3 goldens). **Não agora:** S2,
  S3 e S6 (dividir o README).
- **08/11/2026 — Etapa 2, parte 2:** corrigir no app todos os textos que
  dizem que o site analisa ou precisa estar aberto (D2), com os goldens;
  fazer o S6 (README ~150 linhas, `docs/pulseira.md`,
  `docs/apresentacao.md`, sem perder informação); `linha-de-base/` no
  `.gitignore`. S2 e S3 continuam fora.
- **08/11/2026 — Etapa 2, parte 3:** parte 2 aprovada. Aviso do reset sem
  citar o painel ("Dados apagados para uma nova apresentação."); teste sem
  imagem para as 8 métricas no tema escuro (sem goldens novos).
- **08/11/2026 — Etapa 4 (com a hipótese da subida súbita):** comparar a, b,
  c, d e versões com 3 features com memória (calculadas igual em
  `features.py` e `predict.js`); ajustar os cenários de crise para ~70%
  subida súbita (5–15 s), mantendo o exercício gradual; registrar a hipótese
  no `docs/modelo.md`. Só trocar o `forest.json` com "aprovado".
- **08/11/2026 — Etapa 4, decisões:** não trocar o modelo antes de testar
  "b + memória" com limiares mais baixos (recomendar a troca só se recuperar
  todas as crises sem piorar mais nada); compactar o modelo atual; manter os
  cenários novos (atualizar `docs/testes.md` e a linha do tempo da `demo`);
  manter as features de memória no código; registrar a conclusão negativa da
  hipótese no `docs/modelo.md` (vai para Resultados e Limitações do TCC). O
  usuário disse ter apagado `mobile/ios` e `mobile/macos`, desfeito o
  `analysis_options.yaml` e posto as plataformas no `.gitignore`.

## Etapa 2, parte 1 — feito (commitado pelo usuário em `660a35e`)

As remoções foram feitas com `git rm`/`git mv` (ficam no índice); as edições
estão só na árvore de trabalho.

| ID | Feito |
|---|---|
| R1, R2, R6 | removidos `data/processed/`, sobras do Vite e datasets v1–v3 |
| R3 | `gps_screen.dart` removido; menções em `main.dart` e `docs/app.md` retiradas |
| R4 | `toHistory` (trigger.js — limites e textos intactos), `scenarioAt`, `STATE_INTERVAL_MS` removidos |
| R5 | `mobile/ios`, `linux`, `macos`, `windows`, `web` removidos (incluindo os arquivos gerados que não estavam no git); `analysis_options.yaml` sem as exclusões delas |
| R7, S4 | `model/eda/01–09` removidos; `10_generate_dataset_v4.py` → `model/gerar_dataset_v4.py` com caminho relativo ao repo |
| R8 | `train_incremental.py` e `model/state/` removidos; README e `modelInfo.js` sem as menções |
| R9 | 36 goldens e os testes deles removidos do `goldens_test.dart` (49 ficam, cada um com seu teste); 3 colunas de `docs/design-app.md` e a contagem ("49 imagens") ajustadas |
| R10 | `@types/react` e `@types/react-dom` desinstalados (`package.json` e lock) |
| R11 | linha `Skills Claude/` saiu do `.gitignore` |
| S1 | comentários "site" → "pulseira" em 9 arquivos do app e no docstring do `train.py` |
| S5 | `pubspec.yaml` com descrição real |
| S7 | `docs/modelo.md`: seções de arquivos, modelo em produção e treino reescritas; incremental removido; v2/v3 marcados como históricos |
| S8 | nota de registro histórico no `docs/avaliacao_dataset.md` |
| S9 | `mobile/README.md` reduzido a um atalho para `docs/app.md` |
| D1 | Ajustes: "Painel (site): … O modelo roda no site: ele precisa estar aberto." → "Análise (pulseira): … O modelo roda na própria pulseira. O painel do site é opcional." A linha mede o estado ao vivo publicado pela pulseira (`estadoAoVivo`). `docs/app.md` e README atualizados; goldens ajustes, escuro_ajustes e fonte_130_ajustes regenerados (só eles) |

Encontrado e **não** alterado na parte 1 (corrigido na parte 2, item D2):
`faixa_estado.dart:398-406`, Início sem dados ao vivo — "O painel (site)
parou de enviar às HH:MM. Ele precisa estar aberto para analisar os sinais."
e "Aguardando o painel / Abra o painel (site) no computador. É ele que analisa
os sinais da pulseira." Mesma ideia desatualizada do D1 (afeta os goldens
inicio_painel_e_pulseira_offline e graficos_painel_parado).

### Linha de base depois da parte 1 (`linha-de-base/etapa2/`)

| Verificação | Antes | Depois |
|---|---|---|
| Lint do site / oxlint em todo o JS | 0 / 0 avisos | 0 / 0 avisos |
| Testes do site | 67/67 | 67/67 |
| Build do site | OK | OK, bundle com os mesmos hashes |
| Testes do simulador | 30/30 | 30/30 |
| `verificar.js` (padrão, `--markdown`, `--uma-vez --sementes 50`) | sai com 1 (falhas conhecidas) | **saídas idênticas** byte a byte |
| `scripts/cenarios.mjs` | OK | saída idêntica |
| `node --check tools/verificar-app.mjs` | OK | OK |
| `flutter analyze` | 0 | 0 |
| `flutter test` | 205/205 | 169/169 (−36 testes de golden) |
| Goldens | 85 | 49: 46 idênticos, 3 de Ajustes regenerados (D1); `forest.json` idêntico |

### Antes x depois (parte 1)

| Parte | Arquivos | Tamanho | Linhas de código |
|---|---|---|---|
| data | 6 → 1 | 27,5 → 8,8 MB | — |
| model | 15 → 3 | 1,55 → 0,03 MB | 1.757 → 656 |
| frontend | 46 → 42 | 0,63 → 0,60 MB | 4.899 → 4.890 (src) |
| simulator | 20 → 20 | 0,20 MB | 4.279 → 4.273 |
| tools | 1 → 1 | 0,03 MB | 757 |
| mobile | 269 → 130 | 12,8 → 7,6 MB | lib 8.084 → 8.060 · test 3.090 → 2.923 |
| docs + READMEs | 22 → 22 | 1,2 MB | 4.127 → 4.025 linhas de Markdown |
| **Total** | **380 → 220** | **43,8 → 18,4 MB** | — |

Dependências removidas: `@types/react`, `@types/react-dom`. O `.git` não
diminui (os arquivos ficam no histórico).

## Etapa 2, parte 2 — feito (sem commit)

Pedido (08/11/2026): D2 (textos do app que diziam que o site analisa ou
precisa estar aberto), S6 (README ~150 linhas + `docs/pulseira.md` e
`docs/apresentacao.md`) e `linha-de-base/` no `.gitignore`. S2 e S3
continuam fora.

### D2 — textos visíveis do app

| Onde | Antes | Depois |
|---|---|---|
| Início, pulseira parada (`faixa_estado.dart`) | "O painel (site) parou de enviar às HH:MM. Ele precisa estar aberto para analisar os sinais." | "A pulseira parou de enviar às HH:MM. Confira se ela está ligada e conectada." |
| Início, aguardando (`faixa_estado.dart`) | "Aguardando o painel" / "Abra o painel (site) no computador. É ele que analisa os sinais da pulseira." | "Aguardando a pulseira" / "Confira se ela está ligada e conectada. É ela que analisa os sinais." |
| Gráficos (`graficos_screen.dart`) | "O painel (site) parou de enviar…"; "…leituras do painel (site) chegarem."; "…quando o painel (site) estiver aberto e enviando o estado." | "A pulseira parou de enviar…"; "…leituras da pulseira chegarem."; "…quando a pulseira estiver ligada e enviando o estado." |
| Histórico (`historico_screen.dart`) | "Episódios detectados pelo painel…"; "Quando o painel (site) detectar…"; "Atualizado pelo painel às…" | "…pela pulseira…"; "Quando a pulseira detectar…"; "Atualizado pela pulseira às…" |
| Painel do dia vazio (`painel_do_dia.dart`) | "Quando o painel (site) detectar…" | "Quando a pulseira detectar…" |
| Episódio fora do histórico (`episodio_screen.dart`) | "O painel (site) não mandou mais este episódio." | "A pulseira não mandou mais este episódio." |
| Avaliação (SnackBar, `cartao_episodio.dart`) | "…enviado ao painel." / "…enviada ao painel." | "…enviado à pulseira." / "…enviada à pulseira." |
| "Estou ciente" (dica do leitor de tela, `cartao_episodio_ativo.dart`) | "Avisa o painel que você viu o alerta" | "Avisa a pulseira que você viu o alerta" |
| Conexões (leitor de tela, `connection_bar.dart`) | "…Servidor, pulseira e painel funcionando." | "…Servidor e pulseira funcionando, com os dados ao vivo." |
| Ajustes, CHILD_ID (`configuracoes_screen.dart`) | "Precisa ser a mesma do painel." | "Precisa ser a mesma da pulseira." |

Mantidos (corretos): "não vai para o painel" (nome e lembretes ficam só no
celular), "confirmado no painel" (avaliação feita no site). Notificações:
nenhum texto sobre o site. **Não alterado, fora do pedido:** o aviso do reset
"Dados apagados pelo painel para uma nova apresentação." — o reset vem do
terminal (`npm run resetar`), não do site; não diz que o site analisa.

Testes: 4 asserts de `telas_test.dart` com os textos novos. Goldens: 13
regenerados (ajustes, escuro_ajustes, fonte_130_ajustes, historico,
escuro_historico, fonte_130_historico, historico_filtro_dia,
historico_sem_conexao, historico_vazio, inicio_painel_e_pulseira_offline,
inicio_painel_vazio, graficos_painel_parado, graficos_sem_dados); os outros 36
e o `forest.json` idênticos (hash). Docs que descreviam esses estados
atualizados (`app.md`, `design-app.md`, `figma/home.md`).

Sobras da parte 1 corrigidas junto: `design-app.md` ainda listava as 7
métricas no escuro e outros goldens removidos; `app.md` ainda dizia
"pulseira e painel" nas conexões e que o CHILD_ID só precisava bater com o
site. Ponto de atenção registrado no `design-app.md`: as cores das outras
sete métricas no escuro não têm mais imagem nem teste próprio (removidas na
parte 1, R9).

### S6 — README e docs novos

- README: 672 → 164 linhas (intro, diagrama, funcionalidades, estrutura,
  como rodar, testes, treino, tabela de docs, créditos).
- `docs/pulseira.md` (264 linhas): seção "Pulseira simulada" do README
  inteira (como funciona, histórico local, configuração, modo controle, loop
  e opções, cenários, eventos aleatórios, gabarito, verificação sem broker) +
  a lista de arquivos do `simulator/` que estava na estrutura do README.
- `docs/apresentacao.md` (223 linhas): "Resetar para uma apresentação" e
  "Roteiro de demonstração" do README + o roteiro do cenário `demo` (linha
  do tempo e plano B) que estava no `docs/testes.md`; o `testes.md` ficou
  com um atalho.
- Prova de que nada se perdeu: as 445 linhas movidas existem nos docs novos;
  as 7 diferenças são títulos renomeados e links reescritos. Detalhes que só
  estavam no README e não iam para os docs novos foram para `modelo.md`
  (constante `DATASET`, reiniciar a pulseira), `pulseira.md` (aviso do site
  com a pulseira desligada, 2×/s) e `app.md` (CHILD_ID igual ao da pulseira).
- Links para seções do README em `app.md`, `historico.md`, `modelo.md`,
  `mqtt.md`, `testes.md` e `frontend/scripts/cenarios.mjs` apontam para os
  docs novos. Verificador de links (arquivo + âncora, em todos os `.md`):
  0 quebrados.

### `.gitignore`

`linha-de-base/` adicionada.

### Linha de base depois da parte 2 (`linha-de-base/etapa2-parte2/`)

| Verificação | Resultado |
|---|---|
| Lint do site / oxlint em todo o JS | 0 / 0 avisos |
| Testes do site | 67/67 |
| Build do site | OK, bundle com os mesmos hashes |
| Testes do simulador | 30/30 |
| `verificar.js` (padrão, `--markdown`, `--uma-vez --sementes 50`) e `cenarios.mjs` | **idênticos** a `linha-de-base/etapa2/` |
| `node --check tools/verificar-app.mjs` | OK |
| `flutter analyze` | 0 |
| `flutter test` | 169/169 |

## Etapa 2, parte 3 — feito (sem commit)

- **Aviso do reset:** `MqttService.avisoDeReset` passou de "Dados apagados
  pelo painel para uma nova apresentação." para "Dados apagados para uma nova
  apresentação." (o reset vem do terminal). 3 testes atualizados
  (`mqtt_service_test.dart:272`; `telas_test.dart`: nome do teste e os dois
  `find.text`) e os docs que citavam o texto (`app.md`, `apresentacao.md`,
  `mqtt.md`). O aviso do site (`App.jsx`, "pelo terminal") já estava certo.
  Nenhum golden mostra esse SnackBar.
- **Métricas no escuro:** teste novo em `telas_test.dart`, grupo Gráficos,
  "tema escuro: as 8 métricas desenham sem erro, cada uma com a sua cor".
  Abre Gráficos no escuro e, para cada `Metrica`, seleciona o chip e confere:
  nenhuma exceção ao desenhar, chip selecionado, série com pontos e linha na
  cor de `CoresDados.escuro.metricas`. Conferido por mutação (esperar a cor
  clara faz o teste falhar). Nota do `design-app.md` atualizada.

### Linha de base depois da parte 3 (`linha-de-base/etapa2-parte3/`)

| Verificação | Resultado |
|---|---|
| Lint do site / oxlint em todo o JS | 0 / 0 avisos |
| Testes do site / do simulador | 67/67 · 30/30 |
| Build do site | OK, mesmos hashes |
| `verificar.js` (3 variantes) e `cenarios.mjs` | **idênticos** a `linha-de-base/etapa2/` |
| `node --check tools/verificar-app.mjs` | OK |
| `flutter analyze` / `flutter test` | 0 · 170/170 (+1 teste novo) |
| Goldens e `forest.json` | idênticos aos da parte 2 (hash) |
| Links dos `.md` | 0 quebrados |

## Etapa 4 — comparação feita (sem commit; forest.json NÃO trocado)

Ambiente: venv no scratchpad (scikit-learn 1.9.1, pandas 3.1.1, numpy
2.5.4). O `train.py` reproduz exatamente as 60 árvores do `forest.json`
(conferido antes e depois das mudanças em `features.py`).

### O que mudou no código

- `model/features.py`: 3 features com memória (`bpm_jerk_max_90`,
  `bpm_excesso_mov`, `bpm_tempo_subida`, janela de 90 s; `MEMORY_FEATURES`).
  Calculadas sempre, mas fora de `FEATURE_COLUMNS`: o treino atual não muda.
- `frontend/src/model/predict.js`: as mesmas contas (`memoryFeatures`), só
  quando o `forest.json` as usa; `classify.js` passa até 120 leituras
  (`FEATURE_HISTORY`) em vez de 31. Paridade Python × JS: diferença zero em
  26.910 s do v4 (3 crianças) e 5.607 s do simulador.
- `simulator/scenarios.js`: subida da crise como no gerador do v4 (70%
  súbita 5–15 s, 30% gradual 40–90 s; nominal súbita 10 s), com sorteio
  próprio (os outros sorteios não mudam) e o platô compensando (a linha do
  tempo fica igual, exceto quando o platô bate no mínimo de 20 s). Exercício
  e estereotipia continuam graduais. `docs/pulseira.md` atualizado (tabela de
  variação e os dois exemplos de terminal, reproduzidos com o mesmo gerador).
- Novos: `model/comparar_modelos.py` (por segundo) e
  `model/comparar_episodios.mjs` (por episódio, roda o `verificar.js` numa
  cópia da pulseira com cada forest.json).
- `docs/modelo.md`: seção "Versão simplificada" (hipótese, método, tabelas,
  resultados negativos, recomendação).

### Resultado (detalhes e tabelas no `docs/modelo.md`)

- Memória: por segundo, precisão 0,47 → 0,68–0,72 com o mesmo recall; por
  episódio, **nenhuma** versão reduz os alarmes do exercício (96/96 em
  todas): o pico vem no começo do exercício, que também parece subida
  súbita.
- Melhor nova: b + memória (barulho sem crise 56/60 contra 40/60), mas perde
  4/852 crises e 8/420 no laço e alerta ~1 s depois.
- Simplificar (b, c, 30/40 árvores) perde crises e piora o barulho sem crise.
- Recomendação: **manter o modelo atual**. Compactar o atual: 358 → 267 KB,
  muda 1 de 1000 eventos.

### Linha de base (`linha-de-base/etapa4/`)

Testes do site 67/67, do simulador 30/30, lint 0, build com os mesmos
hashes, `cenarios.mjs` idêntico, `flutter analyze` 0, `flutter test`
170/170. O `verificar.js` **mudou** por causa dos cenários (esperado): laço
igual (exercício 0/60, barulho 40/60, demo 51/60); eventos aleatórios com
alerta 6,4 s após a fisiologia (antes 7,2 s), 21/52 ambientes com alarme
(antes 19/52) e gatilho certo em 851/852 (antes 852/852). Nova referência:
`linha-de-base/etapa4/`.

### Pendente de decisão

- Trocar o modelo? (recomendação: não.) Compactar o atual?
- Manter os cenários com subida súbita? Se sim, regenerar as tabelas do
  `docs/testes.md` e a linha do tempo da `demo` no `docs/apresentacao.md`
  (a crise nominal agora sobe em 10 s), que ainda mostram os números antigos.
- Manter as features de memória no código (inativas) ou removê-las, se o
  modelo não mudar.
- Encontrado e **não alterado**: `mobile/ios/` e `mobile/macos/` voltaram
  (só arquivos gerados pelo Flutter, criados às 15:08 de 08/11) e o
  `mobile/analysis_options.yaml` ganhou `ios/**` e `macos/**`: não foi a
  limpeza.

## Etapa 4 — decisões aplicadas (sem commit)

- **Limiares de "b + memória"** (0,35/0,65; 0,30/0,60; 0,35/0,70;
  0,25/0,55): não recuperam as crises, pioram (848 → 840 → 824 → 797
  detectadas), porque o modelo passa a abrir episódios nas pausas calmas
  (37 → 125 → 330) que "engolem" a crise seguinte. Recomendação mantida:
  **não trocar**. A segunda rodada (com as colunas "calmo" e "episódios nas
  pausas") mostrou ainda que todas as versões novas alarmam na calma; só o
  atual tem 60/60 no `calmo` e 0 episódios nas pausas.
- **Compactação:** `forest.json` com 4 casas e sem espaços (366 → 273 KB,
  `meta` igual); `compactar()` no `train.py` (o `comparar_modelos.py` a
  importa), que agora grava compactado; o retreino gera exatamente o arquivo
  versionado.
- **`docs/testes.md`:** as 7 tabelas que são saída do `verificar.js`
  trocadas pelas novas (conferido que a cópia antiga reproduzia as antigas
  byte a byte), a tabela de detalhes do `--uma-vez`, os resumos e o texto
  (tempos de alerta, gatilho 851/852, leves 245/248 em alto_risco, ambiente
  22/52, variação com a subida). `--pausa 90 --sementes 40` (crises 120/120,
  mínimo 64) e `demo` com 100 sementes (48/300) conferidos de novo.
- **`docs/apresentacao.md`:** linha do tempo da `demo` (alerta ~3:49 e
  ~7:02; texto do gatilho 45 → 87 dB, ~11 s; nota sobre "antes do alerta do
  modelo"); fechamentos e recuperação não mudaram.
- **`docs/modelo.md`:** compactação em "Modelo em produção"; na "Versão
  simplificada", tabela por episódio com "calmo" e "pausas", tabela dos
  limiares e "Conclusão (para Resultados e Limitações do TCC)".
- `model/comparar_episodios.mjs`: opção `--limiares` e colunas "calmo sem
  alerta" e "episódios nas pausas".
- **Não encontrado nesta cópia:** as mudanças do usuário em `mobile/` (as
  pastas `ios`/`macos` ainda existem, o `analysis_options.yaml` ainda tem
  `ios/**` e `macos/**`, e o `.gitignore` não tem as plataformas). Não
  mexi.

### Linha de base final (`linha-de-base/etapa4-final/`)

Site: lint 0, 67/67, build com os mesmos hashes; simulador 30/30;
`cenarios.mjs` idêntico ao da Etapa 2; `verificar.js` igual ao usado nas
tabelas do `docs/testes.md` (falhas conhecidas: exercicio, barulho_sem_crise
e demo); `flutter analyze` 0; `flutter test` 170/170; links dos `.md`: 0
quebrados.

## Estudo exercício x crise (branch `estudo-exercicio`, a partir de `a520460`)

Pedido (09/11/2026): reduzir os alarmes falsos do exercício (96/96 eventos,
60/60 ciclos) e do barulho sem crise (20/60) **sem perder crises**, com
abordagens da literatura (contexto de atividade, batimento adicional,
calibração individual). Regras: sem commit; tópicos MQTT, formatos,
`trigger.js` (limites e textos), `.env` e `mobile/env.json` intactos; sem
navegador; sensores todos mantidos; não recriar `mobile/ios`, `macos`,
`linux`, `windows`, `web`. Trocar o modelo só com "aprovado".

Situação: **E4d 30 s em produção (09/11/2026; antes, 20 s) e ligado
(`POLITICA` no `contexto.js`; `forest.json` igual). Passo 5 feito. Sem
commit.**

Decisões do usuário (09/11/2026): plano aprovado; cenários novos só no laço
(pesos do `eventos_aleatorios` intactos); v5 no scratchpad (vai para
`data/raw/` só se a versão escolhida usar o v5). Ajustes: teste do exercício
"parecido com o dataset" (só diagnóstico, cenário oficial intacto); no E4,
o `exercicio_e_crise` é o teste principal (descartar N que atrase o alerta
da crise > 30 s ou perca crise); poucos PNGs (nominal + 2 sementes).

### Passo 1 — feito (sem commit)

Arquivos: `model/diagnostico_exercicio.mjs` (curvas, exercício "parecido
com o dataset", features do simulador) e `model/diagnostico_exercicio.py`
(inícios no v4, probabilidade fora do fold, faixas v4 × simulador, PNGs);
`docs/imagens/estudo-exercicio/exercicio_{nominal,seed2,seed3}.png` (~170 KB
cada). Saídas em `<scratchpad desta sessão>\diag\`.

- **Curvas:** alerta no **início** (t ≈ 20–50 s, "começando a correr") e de
  novo na **desaceleração** (t ≈ 180–205 s); nunca "possível crise" no
  nominal (pico 0,55). O acelerômetro satura em 20 g já no início.
- **Exercício parecido com o dataset** (60 sementes cada): 78/85/92/100
  bpm × reta/cosseno 30/40/50 s → episódio em **60/60 em todas**, pico
  mediano 0,62–0,65. A diferença simulador × dataset **não** é a causa.
- **No próprio v4 (fora do fold):** 66 entradas em brincadeira_ativa (56
  sem estresse nos 90 s seguintes; 3.811 s de início sem estresse = 3,8% dos
  não-estresse). **44/56 passam de 0,4 e 10/56 de 0,7.** Por segundo,
  p ≥ 0,4 em 29,8% do início, 8,3% do platô, 30,3% da saída e 17,4% do calmo.
- **Por quê:** (1) as inclinações: zerar `eda_slope_long`, `hrv_slope_long`
  e `bpm_slope_long` no início derruba p ≥ 0,4 de 15,7% para 3,3% (modelo
  final); com o giroscópio médio já no valor do platô, 7,6%. "EDA subindo e
  HRV caindo com movimento ainda médio" se parece com as crises com agitação
  do v4 (2.673 s de estresse com `gyro_mean_long` 40–80). (2) Linha de base:
  no calmo do v4, C03 (HRV de repouso 29 ms) e C06 (45 ms) ficam com
  p ≥ 0,4 em 99% e 98% do tempo, e as outras 10 crianças em ≤ 6%. O modelo
  usa níveis absolutos: reforça o E2 (features relativas à linha de base).
- **Cenários novos** (`scenarios.js`, `verificar.js`; `--nivel` no
  `verificar.js` e `nivel` no `programTicks`; sem eles nada muda):
  `crise_com_agitacao` (crise + giroscópio ~125 dps irregular, sem batimento
  extra do movimento) e `exercicio_e_crise` (crise somada 60 s depois do
  platô; avaliação: episódio próprio que começa na crise; episódio do
  exercício ainda aberto quando a crise começa = "engolida" = falhou; alarme
  do exercício fora da crise = limitação). Modelo atual, laço 60 ciclos:

  | Cenário | leve | moderada | alta |
  |---|---|---|---|
  | crise_com_agitacao | 39/60 (21 = 2 episódios só de atenção; **0 sem episódio**) | 60/60 | 60/60 |
  | exercicio_e_crise | 0/60 (51 lim. · 9 engolidas) | 0/60 (51 · 9) | 0/60 (49 · 11) |

- `verificar.js` padrão: tudo igual a `linha-de-base/etapa4-final/` (só
  as 2 linhas novas e a largura de uma coluna); `npm test` do simulador 30/30.

### Passo 1 aprovado (09/11/2026) — conferências pedidas antes dos experimentos

Decisões: variante nova do E2 = descontar só a parte da inclinação da
EDA/HRV explicada pelo movimento (ajustada no treino de cada dobra), sem
zerar; `crise_com_agitacao` nas 3 intensidades é a trava (nenhuma variante
pode piorá-lo). Ordem: E4 → E2 → E3 → E5; E1 (v5) só se nenhum cumprir o
critério. Tabela com a precisão por criança em repouso (destacar C03 e C06).

- **Acelerômetro:** mesma unidade (g) e mesma fórmula no gerador do v4
  (`gerar_dataset_v4.py:261`) e no simulador (`simulate.js:43`):
  giroscópio (dps) × 0,55 × U(0,5; 1,6), limitado a [0,02; 20]. O
  `features.py` e o `predict.js` usam o valor cru (sem conversão). **Não há
  mistura de unidades nem saturação só no simulador**, mas a escala é
  irreal: repouso ~2,9 g (deveria ser ~0–0,3 g dinâmico), exercício e
  agitação saturam em 20 g (real ~2–4 g; o MPU6050 vai no máximo a ±16 g).
  O acelerômetro é uma cópia ruidosa do giroscópio, saturada acima de ~36
  dps. **Mostrado ao usuário; nada corrigido.**
- **Subida de nível dentro do episódio aberto:** a pulseira já publica um
  alerta a cada mudança de nível para atenção/alto (`episodes.js`,
  `ingestReadings`), inclusive atenção → alto no mesmo episódio. O app
  (`mqtt_service.dart`, `_notificarSePreciso`) notifica uma vez por
  episódio; na subida atenção → possível crise só **atualiza a mesma
  notificação sem som** (`silent`/`onlyAlertOnce`); se o episódio já estava
  em possível crise, nada. É o caso (b). Medido no `exercicio_e_crise` (60
  ciclos por intensidade, modelo atual): episódio próprio 51/51/49 (leve,
  moderada, alta; mediana 4/2/2 s, máx. 23 s); dentro do episódio aberto com
  subida atenção → alto 4/4/5 (mediana 9/5/2 s, máx. 10 s); dentro de
  episódio que já estava em possível crise (sem alerta novo) 5/5/6; sem
  nenhuma subida 0. **Correção proposta, não aplicada.**

### Conferências aprovadas (09/11/2026) — aplicado (sem commit)

- **App:** `_notificarSePreciso` (`mqtt_service.dart`) continua notificando
  só quando o nível SOBE no episódio; a subida agora toca de novo.
  `notification_service.dart`: `silent` e `onlyAlertOnce` eram `true` na
  atualização (deixavam a reemissão com o mesmo id em silêncio); agora são
  `false` explícitos. Teste `mqtt_service_test.dart` (nome e asserts da
  subida) e `docs/app.md` ajustados. `flutter analyze` 0; `flutter test`
  170/170; nenhum golden mudou (`git status` só mostra os 3 arquivos). O
  flag do Android não é coberto por teste de unidade (o teste usa um
  serviço falso): conferir no emulador (semente 15, abaixo).
- **`verificar.js`:** `simulateProgram` guarda, por ciclo, os alertas e o
  episódio aberto no início da fisiologia; `exerciseCrisisCheck` conta a
  crise como detectada com episódio próprio OU subida de nível do episódio
  aberto (tempo desde o início da crise); senão "engolida"/"perdida". Modelo
  atual: falhas 5/5/6 (só as engolidas em episódio que já estava em
  possível crise). Laço padrão e `--uma-vez --sementes 50` idênticos à
  referência (fora as linhas novas); simulador 30/30.
- `simulator/package.json`: atalhos `crise-com-agitacao` e
  `exercicio-e-crise`. **Pendente para o Passo 5:** cenários novos no
  `docs/pulseira.md` e no `docs/testes.md`.
- `docs/modelo.md`: limitação da escala do acelerômetro (seção v4).
- Emulador: `npm run exercicio-e-crise -- --uma-vez --seed 15` → episódio
  do exercício abre em atenção ~2:18, sobe para possível crise ~3:42 (crise
  começa 3:40).

### E4 — feito (sem commit; produção inalterada: `POLITICA = null`)

Código: `frontend/src/model/contexto.js` (contexto por regras sobre o
giroscópio e a regularidade; linha de base = percentil 10 de 300 s; política
desligada por padrão), `classify.js` (aplica a política se houver),
`model/comparar_episodios.mjs` (`--politica`, `--nome`, `--saida`; roda os 2
cenários novos × 3 intensidades ciclo a ciclo), `model/tabela_estudo.mjs`
(tabelas), `model/estudo_exercicio.py` (por segundo, com a política
reproduzida). Saídas: `<scratchpad>\e4\`.

- Persistência 10/20/30 s (sem "bilateral"): exercício nos eventos 96 →
  65/55/52; laço do exercício sem alerta 0 → 23/30/30; engolidas 5/5/6 →
  2/0–1/0–1; **mas perde crise_com_agitacao leve** (12/24/33 de 60): viola
  a trava. Rebaixar: nada perdido, engolidas 1/1/1, exercício "possível
  crise" 23 → 3, mas os episódios continuam (96/96).
- **E4b (batimento explicado pelo movimento: |resíduo| < 10 bpm)**: N = 10,
  20, 30 → 852/852, 420/420, crise_com_agitacao 60/60 nas 3 intensidades;
  exercicio_e_crise 58/58/58 (N=10) e 60/59/59 (N=20/30), engolidas 0/1/1;
  exercício nos eventos 67/58/57 de 96; laço do exercício sem alerta
  21/27/27; barulho 40 (igual); calmo 60; pausas 0; maior atraso no
  exercicio_e_crise +12 s (≤ 30 s: nenhum N descartado); crise agitada leve:
  um ciclo +20 s (máx. 51 s contra 43 s). Por segundo: precisão 0,341–0,344
  (atual 0,330), recall 0,884–0,891 (atual 0,911); C03/C06 em repouso
  99%/95–97% (atual 99%/98%). ~0,06 ms/leitura (atual 0,012).

### E2 e E3 — feito (sem commit; produção inalterada)

Código: `features.py` (`BASE_FEATURES`, `RESIDUAL_FEATURES`,
`SLOPE_RESIDUAL_FEATURES`, `COEFICIENTES`, `fit_coeficientes`,
`residual_features`, `CONTEXT_FEATURES`) e `predict.js` (mesmas contas, só
se o `forest.json` usar; coeficientes em `"coeficientes"`, calibração em
`"calibracao"`; `FEATURE_HISTORY` 300 quando usa linha de base). Paridade
Python × JS: diferença máxima 7·10⁻¹⁴ em 4.410 s (C03, C07, C11). O
`train.py` continua gerando as mesmas 60 árvores. `model/estudo_exercicio.py`
(versões e2a…e2c_rel_cal, e3; coeficientes ajustados só no treino de cada
dobra; `--exportar`) e `model/calibrar_simulador.py` (calibração da criança
simulada). Saídas: `<scratchpad>\e2\`, `\e3\`.

- Por segundo: relativas à linha de base resolvem C03/C06 (99%/98% → 1%);
  precisão 0,33 → 0,77–0,89; melhor = E2d (calibração individual) 0,885.
  Coeficientes no treino: 0,30 bpm/dps, 0,13 ms/dps (gerador: 0,34).
- Por episódio: E2b/E2c/E2c só relativas cortam o exercício (96 → 38–49
  eventos) e o barulho (40 → 60/60), mas **perdem crise_com_agitacao leve**
  (29/13/15 de 60): o resíduo do batimento esconde a crise agitada (no v4,
  crise leve com agitação tem giroscópio de só 14–41 dps; a de 125 dps não
  existe no treino). E2a só relativas: 852/852, agitação 60/60, barulho
  60/60, mas exercício 96/96 (54 só atenção), 2 episódios nas pausas e a
  agitada leve mais lenta (mediana 34 s, máx. 126 s). E2a (com absolutas):
  perde 2/852, calmo 52/60, 26 nas pausas.
- E3 por segundo: precisão 0,340 (atual 0,330); C06 em repouso 77%.
- E3 por episódio: perde 15/852 e 14/420, calmo 48/60, 79 nas pausas,
  barulho 20/60 (pior). E2d por episódio (calibração rotulada): E2c 852/852,
  exercício 51/96, barulho 60, mas agitada leve 46/60; E2c só relativas
  agitada leve 34/60 e 4 engolidas.
- E5 (1ª rodada): E2a só relativas + E4b 20/30 s: 852/852, agitação 60/60,
  exercício 39/35 de 96, barulho 60, calmo 60, mas 2 episódios de 1 s nas
  pausas (110 s depois de ambiente_sem_crise, sementes 10 e 47) e 2
  engolidas por intensidade; agitada leve lenta (mediana 38 s, máx. 126 s).
  E2c só relativas + E4b 20 s: exercício 21/96, 0 engolidas, mas agitada
  leve 43/60.

### Perguntas do usuário (09/11/2026) antes da recomendação

1. **Calibração do E2d:** usava os rótulos (primeiros 600 s com atividade
   "calmo" e sem estresse + 300 s ativos sem estresse). Refeita **sem
   rótulo**: linha de base fixa = percentis dos primeiros 300 s de cada
   criança (6 das 12 têm estresse nesse trecho; C04 começa em brincadeira,
   base 132 bpm), coeficientes globais do treino de cada dobra
   (`e2c_jan`, `e2c_rel_jan`; `calibrar_simulador.py --janela`). Por
   segundo se mantém (precisão 0,875/0,895; recall por criança igual,
   C04 0,92 → 0,91). Por episódio não: E2c 850/852, 410/420, calmo 56,
   32 nas pausas; só relativas 852/852 mas agitada leve 29/60.
2. **0 engolidas:** E4c (teto de atenção dentro da política) não muda nada
   (0/1/1). O caso que sobra é um só (semente 3, ciclo 2, moderada e alta):
   aos 80 s de exercício o resíduo do batimento encosta em 10 bpm (ruído),
   a política desliga, sai "possível crise" no exercício, o episódio fica
   aberto e a crise (108 s) só gera um alerta que o app não notifica (já
   tinha notificado possível crise). **E4d** (`contexto.js`, `tetoAtivo`;
   `teto: 'atencao_eda'`): teto de "atenção" no exercício recente enquanto a
   EDA não está elevada e o batimento não está muito abaixo do esperado
   (não olha o resíduo acima). N = 10/20/30: **852/852, 420/420, agitação
   60/60 ×3, exercicio_e_crise 60/60 ×3 (0 engolidas)**, calmo 60, pausas 0,
   barulho 40 (igual), demo 60/60 (atual 51), leves 248/248, gatilho
   851/852, exercício nos eventos 67/58/57 de 96, laço do exercício 21/27/27
   sem alerta e 0 possível crise; atraso máx. +12 s no exercicio_e_crise;
   agitada leve: 1 ciclo +20 s (máx. 51 s, atual 43 s). forest.json igual
   (267 KB); ~0,06–0,09 ms/leitura. Por segundo = E4b. **Cumpre o
   critério. E1 (v5) não rodado** (só se nada cumprisse).
3. **Recomendação (aguardando "aprovado"):** E4d com N = 20 s — só a
   política (`POLITICA` no `contexto.js`), sem trocar o `forest.json`.

### Validação pedida antes do "aprovado" (09/11/2026)

- O usuário desfez o `git reset` (branch de novo em `a520460`). Não mexer
  no git.
- Sementes novas 101–300 (`model/validar_sementes.mjs`): E4d 20 s com 0
  crises perdidas que o modelo sem política detecta (3401/3402 nos dois;
  4200/4200; agitada 600/600 ×3), mas **2 engolidas por intensidade**
  (sementes 107 e 143, as mesmas do modelo sem política) e atrasos de até
  +36 s (exercicio_e_crise leve) e +45 s (agitada leve). Exercício 409 → 234
  de 409 eventos com alarme. **Não cumpriu a condição** posta pelo usuário
  (0 engolidas); o "aprovado" chegou antes de o resultado ser mostrado —
  aplicado e registrado no `modelo.md`, com o aviso ao usuário.
- Origem dos limites do E4d (para o `docs/modelo.md`): constantes do gerador
  v4, não do simulador. EDA elevada = 3,5 µS: ponto médio entre a EDA da
  brincadeira ativa (+2,6) e brincadeira + crise leve (+2,6 + 2,1 = 4,7),
  arredondado para baixo (lado seguro: desliga a política antes). Batimento
  muito acima/abaixo = ±10 bpm: o BPM da crise leve (+11), arredondado para
  baixo. 0,34 bpm/dps = +38 bpm / +112 dps da brincadeira ativa. Conferido no
  v4 (`contexto` do `estudo_exercicio.py`): brincadeira sem estresse tem EDA
  acima da base ≥ 3,5 em 0% dos segundos e resíduo ≥ 10 em 2% (os "falsos
  desligamentos", como a semente 3) e ≤ −10 em 26% (a regra "bilateral"
  desliga a política em 1/4 do exercício do v4); estresse leve: EDA ≥ 3,5 em
  20%, resíduo ≥ 10 em 35%; estresse moderado/alto: 68–77% e 68–73%.
- Limitações a registrar no Passo 5 (pedido do usuário): (a) C03 e C06 com
  alerta em 96–99% do repouso por segundo (2 de 12 crianças com alerta quase
  o tempo todo; a solução, features relativas, depende de dados com crises
  agitadas); (b) barulho sem crise continua 40/60; (c) o E4d foi ajustado no
  simulador e precisa de validação com dados reais no piloto; (d) a
  calibração individual com rótulo exigiria sessão supervisionada (~10 min em
  repouso e ~5 min de atividade).

Testes depois de tudo (política desligada): site 67/67, lint 0, simulador
30/30, `verificar.js` padrão idêntico à referência (fora as linhas novas),
`cenarios.mjs` idêntico.

**Encontrado e não alterado:** às 03:17 de 09/11 alguém rodou
`git reset HEAD~1` na branch `estudo-exercicio` (reflog): o HEAD dela foi
para `c8f1f3d` e o conteúdo do commit `a520460` (Etapa 4) voltou a aparecer
como alterações não commitadas (forest.json, train.py, testes.md,
pulseira.md, apresentacao.md, comparar_*.py/mjs). Nada se perdeu: a `main`
continua em `a520460` e a árvore = `a520460` + este estudo. Para voltar o
ponteiro sem mexer na árvore: `git reset a520460` (decisão do usuário).

- Na árvore ao criar a branch: `.gitignore` modificado pelo usuário
  (plataformas do Flutter ignoradas), não é deste estudo.
- Ambiente Python: o venv da Etapa 4
  (`C:\Users\muril\AppData\Local\Temp\claude\b5482cacf0edafbe\0c3f5ef8-564c-4f0f-82e4-542346fac298\scratchpad\venv`,
  scikit-learn 1.9.1) ainda funciona.
- Primeira medição (v4): 47 inícios calmo → brincadeira_ativa e 17
  atividade_leve → brincadeira_ativa (64 inícios; 3.840 s nos 60 s
  seguintes, 149 deles com estresse). Há exemplos de início de exercício no
  treino: a suspeita principal passa a ser diferença simulador × dataset
  (a confirmar no Passo 1). 1.146 dos 8.631 s de estresse têm movimento
  alto e irregular (giroscópio > 60, regularidade < 0,4).

### Passo 5 — feito (09/11/2026, sem commit)

- `contexto.js`: `POLITICA = { tipo: 'persistencia', n: 20, bilateral: true,
  teto: 'atencao_eda' }`. `comparar_episodios.mjs` e `validar_sementes.mjs`:
  `--politica null` desliga (sem a opção, vale a do `contexto.js`).
- `docs/modelo.md`: seção "Estudo: exercício x crise" (fundamentação,
  diagnóstico, experimentos, tabelas por segundo e por episódio com os
  negativos, validação 101–300, origem dos limites, decisão e limitações
  a–f + dados sintéticos, risco de ajustar o gerador e de esconder crises
  agitadas); "Modelo em produção" e "Arquivos" atualizados.
- `docs/testes.md`: tabelas do `verificar.js` trocadas pelas novas (com a
  política), texto do exercício e da `demo`, seção "Cenários novos nas 3
  intensidades". `docs/pulseira.md` (cenários novos, `--nivel`),
  `docs/gatilho.md` (13 cenários), `docs/apresentacao.md` (exercício da
  `demo` sem "possível crise"; resumo com 2–3 episódios). Links: 0 quebrados.

### Escolha de N (09/11/2026, pedido do usuário)

Validação 101–300 por N (perdidas contra o modelo sem política · engolidas ·
exercício com alarme · atraso máx. e ciclos acima de +30 s no
exercicio_e_crise leve e na agitada leve): 10 s — 0 · 2/2/2 · 269/409 ·
+36 s (1/600) e +45 s (3/600); 20 s — 0 · 2/2/2 · 234/409 · iguais; 30 s —
0 · 1/1/1 · 224/409 · iguais. Regra do usuário (trocar para 10 s só sem
atraso acima de +30 s): **mantido o E4d 20 s**. `docs/modelo.md`: decisão
reescrita (critério de 0 engolidas não cumprido; mantida por reduzir
engolidas de 30–37 para 2 e alarmes do exercício em 43% sem perder crise;
custo: atrasos até 45 s, acima de +30 s em 1 + 3 de 600 ciclos de crise
leve). `docs/apresentacao.md`: "quase nunca Possível crise".

### Troca para N = 30 s (09/11/2026, pedido do usuário)

- `contexto.js`: `n: 30` (comentário atualizado).
- Hipótese do usuário "os atrasos vêm do teto pela EDA" **não confirmada**:
  nos 8 ciclos atrasados (agitada leve 102/142/202/220 e exercicio_e_crise
  leve 173/182/189/245, ciclo 3), só o teto (n = 1) dá os mesmos tempos do
  modelo sem política; a persistência (com ou sem teto, N = 10 ou 30) dá
  54/61/70/67/45/44/47/30 s. A probabilidade oscila perto de 0,4 e a
  persistência nunca se completa: o alerta sai quando a condição da política
  desliga (EDA ≥ 3,5 ou batimento fora de ±10). Registrado assim no
  `modelo.md`.
- `docs/modelo.md` (decisão: N = 30 escolhido depois da validação 101–300;
  engolidas 1/1/1, semente 143; exercício −45%; atrasos até 45 s, iguais
  para N = 10/20/30 e por quê; tabelas com a linha em produção; limitação
  (a) 95–99%), `docs/testes.md` (tabelas do `verificar.js` regeradas com
  N = 30; exercício 57/96), `docs/apresentacao.md` ("espera 30 s").
- Emulador: com o E4d a semente 15 não testa mais a subida (a crise abre
  episódio próprio em possível crise às 3:43). Nova semente: **253**
  (`npm run exercicio-e-crise -- --uma-vez --seed 253`): "Atenção" às 2:59
  (toca), outro atenção às 3:13 (não toca), "Possível crise" às 3:43 (a mesma
  notificação toca de novo); 5:47 atenção do mesmo episódio (não toca); 7:02
  episódio novo, atenção (notificação nova).

## Próximo passo

Estudo exercício x crise: concluído, sem commit (revisão do usuário). Etapa
4 aguardando revisão; depois, Etapa 5 (relatório final). S2 e S3 continuam
fora.

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
| 2. Remoções aprovadas — parte 1 | **concluída — aguardando revisão** |
| 3. Simplificação do código | não iniciada |
| 4. Modelo mais simples | não iniciada |
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

## Etapa 2, parte 1 — feito (sem commit)

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

Encontrado e **não** alterado (precisa de aprovação, texto visível):
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

## Próximo passo

Aguardando revisão da parte 1. Pendentes de decisão: S2, S3, S6, o texto do
Início citado acima, e a Etapa 4.

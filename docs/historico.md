# Histórico de episódios

Quem detecta os episódios e guarda o histórico é a **pulseira**
(processamento na borda, ver [mqtt.md](mqtt.md#por-que-o-processamento-fica-na-pulseira)).

- Código: `frontend/src/model/episodes.js` (lógica pura),
  `frontend/src/model/metricas.js` (métricas dos sinais por episódio),
  `simulator/borda.js` (a pulseira chamando a lógica a cada leitura) e
  `simulator/historico.js` (arquivo).
- Telas: o app do cuidador e, se estiver aberto,
  `frontend/src/components/EpisodeHistory.jsx` (painel do site).
- Testes: `frontend/src/model/episodes.test.js`,
  `simulator/testes/historico.test.js` e `simulator/testes/metricas.test.js`.

O histórico aparece no app do cuidador e no painel do site, logo abaixo do
gráfico. A pulseira publica os 50 episódios mais recentes em
`puzzleband/<id>/historico`. O painel mostra esses 50; o app guarda todos os
que recebe num banco SQLite no celular (por padrão até 1 ano ou 5.000
episódios; o cuidador escolhe 1 ano, 2 anos ou "até eu apagar"), então
o calendário e os gráficos do app continuam completos depois que um episódio
sai da lista da pulseira ([app.md](app.md#armazenamento)).

## O que é um episódio

- **Começa** na primeira leitura em que o nível do modelo sai de
  `baixo_risco` (vai para `atencao` ou `alto_risco`). Nesse instante é
  calculado o provável gatilho ([gatilho.md](gatilho.md)).
- **Termina** quando o nível volta para `baixo_risco` e **permanece** assim
  por pelo menos 30 s seguidos (histerese). Uma queda curta, como 10 s em
  baixo risco seguidos de outra subida, continua sendo o mesmo episódio, para
  não partir uma crise em vários pedaços. O `fim` registrado é o instante em
  que o nível voltou ao normal, não o fim dos 30 s de confirmação.
- **Interrompido**: se o monitoramento para no meio (pulseira desligada com
  Ctrl+C, `--duracao` atingida, processo encerrado ou queda de energia), o
  episódio é fechado com o que se sabe até ali e marcado como `interrompido`.
  Com Ctrl+C, a pulseira fecha e publica na hora. Se o processo cair, o
  episódio aberto vira `interrompido` quando a pulseira lê o arquivo na
  próxima execução.

Enquanto não termina, o episódio aparece como "em andamento" e a duração
parcial é mostrada. O painel atualiza essa duração com o estado ao vivo,
porque o histórico só é republicado quando o episódio muda. O tempo é contado
em leituras, 1 por segundo (mesma premissa do modelo).

## Métricas por episódio

Desde 11/2026, a pulseira calcula, para cada episódio, as médias dos sinais
em três janelas e grava no campo opcional `metricas` (formato em
[mqtt.md](mqtt.md#historico-pulseira--app-e-site)). É a base do relatório em
Excel do app ([app.md](app.md#relatório-em-excel)).

| Janela | O que entra | Valores |
|---|---|---|
| `antes` | As leituras dos **120 s antes** do início, tiradas da memória de sinais da pulseira no instante em que o episódio abre | média |
| `durante` | Do início até o **começo dos 30 s calmos finais** | média, mínimo e máximo |
| `recuperacao` | Os **30 s calmos** que encerram o episódio | média |

- **Sinais:** BPM (`bpm`), VFC (`hrv_ms`), EDA (`eda_uS`), movimento do
  giroscópio (`gyro_mag_dps`), luz (`luz_lux`) e ruído (`ruido_db`).
- **Contagem:** cada janela registra quantas leituras entraram
  (`n_leituras`) e, por sinal, quantas tinham valor válido (`n`). Um sinal
  sem valor fica fora da média.
- **Episódio longo:** o `durante` é calculado leitura a leitura (somas,
  contagens, mínimo e máximo), sem depender do buffer de 300 leituras.
  Assim, um episódio de mais de 5 minutos tem a média do episódio inteiro, e
  o pico do começo continua contando.
- **Poucas leituras antes:** se a pulseira acabou de ligar, o `antes` tem
  menos de 120 leituras, e o `n_leituras` mostra quantas. Com nenhuma, os
  sinais ficam `null`.
- **Calma curta no meio:** um trecho calmo de menos de 30 s seguido de outra
  subida continua sendo o mesmo episódio (histerese), e as leituras dele
  voltam para o `durante`. Só o trecho calmo que fecha o episódio vira
  `recuperacao`, e o número de leituras do `durante` é igual a `duracao_s`.
- **Em andamento:** as métricas são atualizadas a cada leitura e vão no
  histórico quando ele é republicado. A `recuperacao` é o trecho calmo em
  curso, ou seja, parcial.
- **Interrompido:** guarda o que havia. A `recuperacao` fica parcial (menos
  de 30 leituras) ou vazia.
- **Episódio antigo** (gravado antes de 11/2026, ou vindo de uma pulseira
  antiga): sem `metricas` (`null`). Continua válido; no relatório, as
  células dessas colunas ficam vazias.

## Campos guardados

| Campo | Conteúdo |
|---|---|
| `id` | Identificador do episódio |
| `crianca` | `CHILD_ID` da pulseira (ex.: `C01`) |
| `fonte` | `pulseira` (cenário) ou `manual` (modo controle, valores do painel). Episódios antigos podem ter `mqtt`, o nome antigo de `pulseira` |
| `inicio` / `fim` | Data e hora (ISO 8601); `fim` vazio enquanto está em andamento |
| `duracao_s` | Duração em segundos |
| `encerramento` | `normalizou`, `interrompido` ou vazio (em andamento) |
| `nivel_maximo` | `atencao` ou `alto_risco` |
| `probabilidade_maxima` | Maior probabilidade estimada pelo modelo no episódio (0–1) |
| `gatilho` | Objeto completo da regra de gatilho (tipo, texto, linha de base, detalhes por sinal). No tópico `historico` vai só tipo + texto |
| `avaliacao_cuidador` | `pendente`, `confirmado` ou `descartado` |
| `observacao` | Texto livre opcional (até 200 caracteres) |
| `avaliacao_origem` | Quem avaliou por último: `app` (app do cuidador) ou `site` (painel); os dois chegam pelo MQTT |
| `avaliacao_em` | Quando avaliou (ISO 8601) |
| `visto_pelo_cuidador_em` | Quando o cuidador tocou "Estou ciente" no app (ISO 8601) |
| `metricas` | Opcional (11/2026): médias dos sinais antes, durante e na recuperação ([Métricas por episódio](#métricas-por-episódio)). `null` em episódio antigo |

Os três últimos campos, assim como a avaliação e a observação, só mudam por
ação do cuidador. Quando o rastreador atualiza um episódio em andamento, eles
são preservados (`CAREGIVER_FIELDS` em `model/episodes.js`).

## Avaliação do cuidador

No app e no painel, cada episódio tem os botões **Confirmar gatilho** e
**Descartar**, além de um campo curto de observação (ex.: "sirene da escola
tocou antes"). Os dois publicam em `puzzleband/<id>/avaliacao`, e quem
aplica é a pulseira. Ela grava no arquivo e republica o histórico, e o painel
e o app atualizam.

- No painel, clicar no botão já ativo desfaz a escolha (`pendente`). A
  observação vai junto com a avaliação, ao sair do campo; por isso o campo só
  é liberado depois de confirmar ou descartar. Com a pulseira offline, os
  botões ficam desativados.
- O estado aparece em texto e ícone ("✓ confirmado pelo cuidador",
  "✕ descartado pelo cuidador", "○ pendente"), não só pela cor. Os botões
  usam `aria-pressed`.
- O cuidador pode avaliar um episódio ainda em andamento; a avaliação é
  preservada enquanto o episódio continua sendo atualizado.
- **Pelo app do cuidador**: a avaliação feita no app aparece no painel com
  a etiqueta "avaliado pelo app às HH:MM". Quando o cuidador toca "Estou
  ciente" no app (`puzzleband/<id>/ack`), a pulseira grava o horário, e o
  episódio e o banner de alerta do painel mostram "Alerta visto pelo
  cuidador às HH:MM". Ver [mqtt.md](mqtt.md).

A avaliação não altera o modelo nem a regra: é um registro para o cuidador
(e para o TCC) de quantas indicações fizeram sentido na prática. É a base
para recalibrar os limites da regra com dados reais no futuro.

## Resumo de padrões

No topo do histórico há um resumo **por criança**:

- total de episódios e duração média (só dos episódios encerrados
  normalmente; os interrompidos têm duração parcial);
- distribuição dos gatilhos, por exemplo "Ruído como provável gatilho:
  7 de 10 episódios · 3 confirmados pelo cuidador". Um episódio com
  `ruido_e_luminosidade` conta nas duas linhas;
- contagem das avaliações: confirmados, descartados e pendentes.

## Exportar CSV

O botão **Exportar CSV** do painel baixa
`puzzleband_historico_AAAAMMDD_HHMMSS.csv` com os episódios recebidos da
pulseira (os 50 mais recentes). Como o tópico leva o gatilho resumido, as
colunas de detalhe dos sinais (`ruido_*`, `luz_*`, `baseline_confiavel`,
`fisiologia_sinal`) saem vazias no CSV do painel; o detalhe completo fica no
arquivo da pulseira. O formato segue o padrão do Excel em português:

- separador `;` e vírgula decimal (`0,873`);
- UTF-8 com BOM (os acentos abrem corretamente no Excel);
- datas no horário local, `AAAA-MM-DD HH:MM:SS`;
- textos começando com `=`, `+`, `-` ou `@` recebem um `'` na frente, para
  o Excel não interpretar como fórmula.

Colunas: `id`, `crianca`, `fonte`, `inicio`, `fim`, `duracao_s`,
`encerramento`, `nivel_maximo`, `probabilidade_maxima`, `gatilho_tipo`,
`gatilho_texto`, `baseline_confiavel`, `fisiologia_sinal`, `ruido_status`,
`ruido_linha_base_db`, `ruido_pico_db`, `ruido_antecedencia_s`,
`luz_status`, `luz_linha_base_lux`, `luz_pico_lux`, `luz_variacao_pct`,
`luz_antecedencia_s`, `avaliacao_cuidador`, `observacao`.

Para abrir no Python: `pd.read_csv(arquivo, sep=';', decimal=',')`.

## Limpar histórico

O painel não apaga mais o histórico: quem guarda é a pulseira. Para começar
do zero, há dois caminhos. Exporte o CSV antes se quiser guardar.

- `--limpar-historico` (por exemplo, `npm start -- --limpar-historico`): a
  pulseira esvazia o arquivo e publica a lista vazia em `historico`. O painel
  fica vazio. **O app não apaga mais o seu histórico com a lista vazia**
  (mudança de 11/2026: ele acumula os episódios no banco local); para limpar
  o app também, use `npm run resetar` ou, no celular, **Ajustes → Apagar
  dados deste aparelho**.
- `npm run resetar` (com a pulseira desligada), para uma apresentação: apaga
  o arquivo, os retidos no broker e manda o app e o site apagarem os dados
  locais pela ordem em `comando`. No app saem o histórico (com as
  métricas), o resumo de cada minuto, os episódios notificados e os
  lembretes (as tabelas do banco local) e os gráficos
  (e, com `--tudo`, as preferências). Ver [apresentacao.md](apresentacao.md#resetar-para-uma-apresentação) e
  [mqtt.md](mqtt.md#ordem-de-reset-npm-run-resetar).

O app só aceita um `historico` com `"origem": "pulseira"`. Uma aba antiga do
site, de quando ele guardava o histórico, não traz mais os episódios velhos
de volta.

## Persistência

- **Na pulseira**: arquivo `simulator/data/historico_<id>.json` (fora do Git:
  `simulator/.gitignore`). Usa a mesma interface `getItem`/`setItem` que o
  `localStorage` usava, então `loadEpisodes`/`createEpisodeStore` de
  `episodes.js` funcionam sem mudança.
- A gravação é atômica (arquivo temporário + troca) e agrupada (no máximo uma
  a cada 2 s, porque com um episódio aberto o histórico muda a cada segundo),
  com uma gravação final ao encerrar.
- **Ao iniciar sem o arquivo**, a pulseira recupera os episódios da mensagem
  retida em `puzzleband/<id>/historico` (espera até 5 s) antes de publicar a
  sua lista. Assim, nada se perde ao trocar de computador ou apagar a pasta
  `data/`. O que vem do tópico tem o gatilho resumido. Só vale a mensagem com
  `"origem": "pulseira"`, e uma ordem de reset retida com `id` novo manda
  começar vazia em vez de recuperar.
- Um arquivo corrompido é guardado como
  `historico_<id>.corrompido-<data>.json` e a pulseira segue sem ele.
- Limite de 200 episódios: ao passar disso, os mais antigos saem.
- **No app do cuidador**: um banco SQLite local (`files/banco/puzzleband.db`,
  pacote `drift`), tabela `episodios`, e as métricas de cada episódio na
  tabela `episodio_metricas`. Cada lista recebida entra por upsert
  pelo id do episódio; os que saem da lista de 50 da pulseira continuam no
  banco, e uma lista vazia não apaga nada. A avaliação feita no app fica
  "pendente de confirmação" até a pulseira devolver o mesmo `avaliacao_em`
  (a pulseira guarda o horário da mensagem sem mudança). Retenção: a opção
  "Guardar histórico por" (1 ano / 5.000 episódios por padrão, 2 anos /
  10.000 ou até o cuidador apagar). Detalhes: [app.md](app.md#armazenamento).

## Privacidade (LGPD)

- **Onde os dados ficam.**
  - O histórico completo (até 200 episódios, com o gatilho detalhado) fica
    **na pulseira**, no arquivo local.
  - Os **50 mais recentes**, resumidos (sem as leituras brutas e com o
    gatilho reduzido a tipo + texto), são publicados no broker MQTT em
    `puzzleband/<id>/historico` com *retain*, para o app do cuidador e o
    painel. Ficam então também no broker (até a próxima publicação).
  - No **celular do cuidador**, o app acumula os episódios recebidos (com
    as métricas dos sinais) num banco SQLite local, por **1 ano** por padrão
    (no máximo 5.000; o cuidador pode escolher 2 anos ou "até eu apagar", e
    a tela explica que guardar menos protege a privacidade da criança),
    além do resumo de cada minuto (90 dias), dos lembretes e dos episódios
    já notificados. O banco fica fora do backup do
    Android e da transferência entre aparelhos (`allowBackup="false"` e
    regras de exclusão). Não é criptografado: SQLCipher fica como trabalho
    futuro ([app.md](app.md#limitações-do-armazenamento)).
  - O acesso ao tópico é controlado por usuário e senha e pela ACL do broker
    (ver [mqtt.md](mqtt.md#acl-sugerida-menor-privilégio)).
  - O painel do site não guarda nada.
- **Processamento na borda** (LGPD, art. 6º, III, princípio da necessidade):
  o modelo roda na pulseira, e o que trafega para o app é só o resultado.
  Quanto menos dado de saúde sai do aparelho, menor a exposição. As leituras
  brutas ainda são publicadas, mas só para o painel do desenvolvedor; numa
  pulseira real, elas poderiam ficar só no aparelho.
- **Minimização**: o histórico guarda só o resumo de cada episódio
  (horários, nível, probabilidade, gatilho, avaliação e as médias dos sinais
  em três janelas), não as leituras brutas dos sensores. O app guarda também
  a média de cada minuto (não cada leitura), por 90 dias. A criança é identificada por um código (`C01`), não
  pelo nome.
- **Dados sensíveis e de crianças.** Informações de saúde são dados pessoais
  sensíveis (art. 5º, II) e o tratamento de dados de crianças exige
  consentimento específico de um dos pais ou responsável (art. 14). Num uso
  real, isso deve ser coletado antes do monitoramento.
- **Eliminação**: `--limpar-historico` esvazia o arquivo da pulseira e
  republica a lista vazia no broker; o histórico do app **não** é apagado por
  ela. `npm run resetar` apaga também as mensagens retidas no broker e, pela
  ordem em `comando`, os dados guardados no celular (as tabelas do banco,
  com `secure_delete`, inclusive as métricas e o resumo de cada minuto). No
  app, **Ajustes → Apagar dados deste aparelho** apaga só o celular. A
  retenção apaga sozinha o que passou do período escolhido (1 ano por
  padrão) e o resumo de cada minuto com mais de 90 dias.
- **Cuidados**: o arquivo da pulseira não é criptografado. Qualquer pessoa
  com acesso ao computador onde a pulseira simulada roda consegue ler os
  dados. Numa pulseira real, a memória do ESP32 deveria ser criptografada
  (*flash encryption*). O CSV exportado pelo painel e o relatório em Excel do
  app viram arquivos comuns e devem ser guardados com o mesmo cuidado. Antes
  de compartilhar o relatório, o app avisa: "Este arquivo contém dados de
  saúde da criança. Compartilhe só com quem cuida dela."
- **MQTT**: a conexão é sempre com TLS (`mqtts://` na pulseira e no app,
  `wss://` no painel). Detalhes e ACL: [mqtt.md](mqtt.md).

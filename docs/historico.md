# Histórico de episódios

Quem detecta os episódios e guarda o histórico é a **pulseira**
(processamento na borda, ver [mqtt.md](mqtt.md#por-que-o-processamento-fica-na-pulseira)).

- Código: `frontend/src/model/episodes.js` (lógica pura), `simulator/borda.js`
  (a pulseira chamando a lógica a cada leitura) e `simulator/historico.js`
  (arquivo).
- Telas: o app do cuidador e, se estiver aberto,
  `frontend/src/components/EpisodeHistory.jsx` (painel do site).
- Testes: `frontend/src/model/episodes.test.js` e
  `simulator/testes/historico.test.js`.

O histórico aparece no app do cuidador e no painel do site, logo abaixo do
gráfico, com os 50 episódios mais recentes que a pulseira publica em
`puzzleband/<id>/historico`.

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
  pulseira esvazia o arquivo e publica a lista vazia em `historico`, que
  substitui a cópia do app.
- `npm run resetar` (com a pulseira desligada), para uma apresentação: apaga
  o arquivo, os retidos no broker e manda o app e o site apagarem os dados
  locais pela ordem em `comando`. No app saem a cópia do histórico, os
  episódios notificados, os lembretes e os gráficos (e, com `--tudo`, as
  preferências). Ver README, "Resetar para uma apresentação", e
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

## Privacidade (LGPD)

- **Onde os dados ficam.**
  - O histórico completo (até 200 episódios, com o gatilho detalhado) fica
    **na pulseira**, no arquivo local.
  - Os **50 mais recentes**, resumidos (sem as leituras brutas e com o
    gatilho reduzido a tipo + texto), são publicados no broker MQTT em
    `puzzleband/<id>/historico` com *retain*, para o app do cuidador e o
    painel. Ficam então também no broker (até a próxima publicação) e no
    celular do cuidador (`shared_preferences`).
  - O acesso ao tópico é controlado por usuário e senha e pela ACL do broker
    (ver [mqtt.md](mqtt.md#acl-sugerida-menor-privilégio)).
  - O painel do site não guarda nada.
- **Processamento na borda** (LGPD, art. 6º, III, princípio da necessidade):
  o modelo roda na pulseira, e o que trafega para o app é só o resultado.
  Quanto menos dado de saúde sai do aparelho, menor a exposição. As leituras
  brutas ainda são publicadas, mas só para o painel do desenvolvedor; numa
  pulseira real, elas poderiam ficar só no aparelho.
- **Minimização**: o histórico guarda só o resumo de cada episódio
  (horários, nível, probabilidade, gatilho e avaliação), não as leituras
  brutas dos sensores. A criança é identificada por um código (`C01`), não
  pelo nome.
- **Dados sensíveis e de crianças.** Informações de saúde são dados pessoais
  sensíveis (art. 5º, II) e o tratamento de dados de crianças exige
  consentimento específico de um dos pais ou responsável (art. 14). Num uso
  real, isso deve ser coletado antes do monitoramento.
- **Eliminação**: `--limpar-historico` esvazia o arquivo da pulseira e
  republica a lista vazia no broker. A cópia salva no celular é substituída
  quando o app recebe a nova lista. `npm run resetar` apaga também as
  mensagens retidas no broker e, pela ordem em `comando`, os dados guardados
  no celular. No app, **Ajustes → Apagar dados deste aparelho** apaga só o
  celular.
- **Cuidados**: o arquivo da pulseira não é criptografado. Qualquer pessoa
  com acesso ao computador onde a pulseira simulada roda consegue ler os
  dados. Numa pulseira real, a memória do ESP32 deveria ser criptografada
  (*flash encryption*). O CSV exportado vira um arquivo comum e deve ser
  guardado com o mesmo cuidado.
- **MQTT**: a conexão é sempre com TLS (`mqtts://` na pulseira e no app,
  `wss://` no painel). Detalhes e ACL: [mqtt.md](mqtt.md).

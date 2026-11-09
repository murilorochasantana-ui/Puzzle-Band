# Apresentação: reset e roteiros de demonstração

Como preparar uma apresentação do Puzzle Band: apagar os dados de
demonstrações anteriores (`npm run resetar`), o roteiro com o app do
cuidador e o roteiro do cenário `demo`. Comandos e opções da pulseira:
[pulseira.md](pulseira.md).

## Resetar para uma apresentação

`npm run resetar` (em `simulator/`) apaga os episódios e os dados de
demonstrações anteriores na pulseira, no broker, no app do cuidador e no site.
Não é preciso mexer no celular. Usa as credenciais do `simulator/.env`.

**Ordem certa:**

1. **Encerre a pulseira** com Ctrl+C no terminal dela. Com a pulseira
   rodando, o reset recusa, porque ela regravaria o arquivo e republicaria o
   histórico. Ele confere a trava `data/pulseira_<id>.lock` e o `status`
   retido.
2. **Deixe o app aberto no celular**, conectado, para ver a confirmação. Se o
   app estiver fechado, ele aplica o reset quando abrir, porque a ordem fica
   guardada no broker.
3. Rode o reset:

   ```bash
   cd simulator
   npm run resetar -- --simular   # opcional: só mostra o que vai apagar
   npm run resetar                # mostra, pede para digitar RESETAR e apaga
   ```

4. Espere a mensagem **"App limpo"** (até 30 s). No celular aparece "Dados
   apagados para uma nova apresentação.". Se aparecer "O app não
   respondeu", abra o app: ele aplica ao conectar.
5. **Inicie a pulseira** para a apresentação, por exemplo
   `npm run demo -- --ciclos 1` ou `npm run controle`. O site, se estiver
   aberto, limpa a tela sozinho.

**O que é apagado:**

| Onde | Sempre | Também com `--tudo` |
|---|---|---|
| Pulseira (`simulator/`) | `data/historico_<id>.json` (e as cópias `.corrompido-*` e `.tmp`) | `logs/` (gabaritos) |
| Broker | as mensagens retidas `estado`, `historico`, `status` e `app/status`. Depois, `historico` volta retido com a lista vazia e a ordem fica retida em `comando` | — |
| App do cuidador | cópia do histórico, episódios já notificados, alertas recebidos, lembretes (e os avisos agendados deles) e gráficos | preferências: nome da criança, aparência e alertas sonoros voltam ao padrão |
| Site (painel) | o que está na tela | — |

**Opções:**

| Opção | O que faz |
|---|---|
| `--simular` | Só mostra o que seria apagado (e quantos episódios há no broker). Não apaga nem publica nada |
| `--sim` | Não pede para digitar `RESETAR` |
| `--tudo` | Também apaga os logs/gabaritos e volta as preferências do app ao padrão (`manter_preferencias: false`) |
| `--id C05` | Outra criança (padrão: `CHILD_ID` do `simulator/.env`) |
| `--forcar` | Não confere se a pulseira está rodando. Útil se a trava ou o `status` ficaram de uma queda. Se ela estiver rodando de verdade, também aplica a ordem e republica a lista vazia |

**Como funciona.** A ordem `{"acao": "resetar", "id": "<uuid>", ...}` vai
retida em `puzzleband/<id>/comando`. Cada um a aplica **uma vez por id**:
- a pulseira guarda o id em `data/reset_<id>.json`;
- o app guarda o id no `shared_preferences`.

Assim a ordem não é reaplicada a cada conexão. Ao iniciar, a pulseira espera
até 5 s pela ordem retida: se o id for novo (por exemplo, o reset rodou em
outro computador), ela começa com o histórico vazio. O app confirma em
`comando/resposta`. Detalhes, QoS e a ACL necessária:
[docs/mqtt.md](mqtt.md#comando-terminal--pulseira-app-e-site). Se o
broker recusar uma publicação (ACL), o reset para ali e diz o que já foi
feito.

**Sem terminal.** No app, **Ajustes → Dados deste aparelho → Apagar dados
deste aparelho** faz a mesma limpeza, só no celular, com uma confirmação na
tela. A opção "Também voltar as preferências ao padrão" vem desmarcada. Os
episódios guardados na pulseira voltam a aparecer quando ela publicar de
novo.

**Pelo cabo (sem MQTT).** Com o celular em depuração USB e o `adb` do Android
SDK (platform-tools):

```bash
adb shell pm clear br.unimar.puzzleband
```

O `applicationId` está em `mobile/android/app/build.gradle.kts`. O comando
apaga **todos** os dados do app, como uma reinstalação: histórico, lembretes
(o Android cancela os avisos agendados junto), preferências, o registro de
que a permissão de notificação já foi pedida (o app volta a pedir na
primeira abertura) e o id do último reset. Por isso, na próxima conexão o app aplica a ordem retida mais uma vez,
sem efeito, porque já está vazio. O comando não mexe na pulseira nem no
broker.

## Roteiro com o app (pulseira + app + painel)

Antes: `simulator/.env`, `frontend/.env` e `mobile/env.json` preenchidos,
internet no computador e no celular, e notificações do app permitidas. Para
começar sem episódios nem lembretes de demonstrações anteriores, rode o
[reset](#resetar-para-uma-apresentação) com a pulseira desligada e o app
aberto.

Para conferir a troca de mensagens sem o celular, use
`npm run verificar-app` em `simulator/`. Ele faz o papel do app pelo
terminal (ver [docs/mqtt.md](mqtt.md#verificar-pelo-terminal-verificar-app)).

1. **Pulseira no modo controle + painel + app.**
   - Em `simulator/`, rode `npm run controle`.
   - Em `frontend/`, rode `npm run dev` e abra o site.
   - No celular, abra o app e toque em **Entrar**.

   O painel mostra "Pulseira: online", "App do cuidador: conectado" e, no
   "Controle da pulseira", "Pulseira no modo controle". O app mostra
   **Calmo** e o BPM (em Ajustes: "Servidor: conectado" e "Análise
   (pulseira): ao vivo"). Mexa no
   BPM no painel: o número muda no celular e no painel em poucos segundos,
   com transição de 20 s.
2. **Crise pelos controles → notificação → "Estou ciente".**
   - Deixe tudo calmo por **~2 min**: a regra de gatilho precisa de 60 s de
     linha de base antes da janela de análise de 60 s.
   - Suba o **ruído** para ~90 dB.
   - Uns 10 s depois, suba **BPM** (~140) e **EDA** (~12 µS) e baixe a
     **HRV** (~20 ms).

   A pulseira detecta e publica. O painel mostra o alerta "Provável gatilho:
   ruído". No celular chega a notificação com esse texto, e a Home mostra o
   card do alerta. Toque em **Estou ciente**: o banner do painel passa a
   mostrar "Alerta visto pelo cuidador às HH:MM".

   Esse roteiro foi conferido com o modelo real pelo modo controle (com as
   rampas): 20 de 20 sementes deram gatilho "ruído" com linha de base
   confiável. Durante a crise o nível oscila entre atenção e possível crise,
   mas o app notifica uma vez só.
3. **Confirmar o gatilho no app → histórico atualiza.** Volte os controles
   ao normal e espere o episódio fechar: 30 s depois de o nível voltar ao
   normal. No app, abra **Histórico**, escreva uma observação e toque em
   **Confirmar gatilho**. A pulseira aplica e republica, e no painel o
   episódio passa a "✓ confirmado pelo cuidador", com a etiqueta "avaliado
   pelo app às HH:MM" e a observação.
4. **O app funciona sem o site.**
   - Feche a aba do painel e pare a pulseira (Ctrl+C).
   - Rode `npm run crise-ruido`: os indicadores mostram "Pulseira: online"
     no app.
   - Depois de ~2 min calmos, o ruído sobe, a pulseira alerta e o celular
     notifica "Provável gatilho: ruído (45 → 88 dB, …)", sem nenhum site
     aberto.
   - Ctrl+C na pulseira: "Pulseira: offline" no app.

## Roteiro do cenário `demo` (10,5 min)

> Com o app do cuidador no celular (notificação, "Estou ciente" e avaliação
> pelo app), siga o roteiro em 4 passos do
> [roteiro com o app](#roteiro-com-o-app-pulseira--app--painel). Durante o `demo`
> abaixo, o app aberto recebe o mesmo estado, os alertas e o histórico, com
> ou sem o painel do site aberto.

O roteiro do cenário `demo` dura **10,5 minutos** (630 s), com o nome da fase
em cada linha do log. Com `--ciclos 1` ele roda uma vez, sem variação (o 1º
ciclo é sempre o nominal), e encerra depois de uma pausa calma final:

```
0 s calmo → 60 s exercício → 150 s calmo → 210 s crise com ruído
→ 330 s recuperação → 420 s crise sem gatilho → 540 s recuperação
→ 565 s pausa calma final → 685 s fim
```

### Antes de começar

1. `simulator/.env` e `frontend/.env` configurados, com o mesmo `CHILD_ID`
   (e o `mobile/env.json`, se for usar o app).
2. Terminal 1: `cd frontend` e `npm run dev`. Abra o painel. O status deve
   mostrar "Broker: conectado".
3. Se quiser guardar os episódios anteriores, exporte o CSV no painel antes.
   Depois, com o app aberto no celular, rode `npm run resetar` em
   `simulator/`: apaga o histórico da pulseira, os retidos no broker e os dados
   do app e do site, e mostra "App limpo" (ver
   [Resetar para uma apresentação](#resetar-para-uma-apresentação)).
4. Terminal 2: `cd simulator` e
   `npm run demo -- --ciclos 1 --limpar-historico`.
   - O `--limpar-historico` começa o histórico vazio, para a plateia ver só os
     episódios da demo. Depois do `npm run resetar` ele não é necessário (a
     pulseira já começa vazia), mas não atrapalha.
   - A pausa final de 2 min garante que o último episódio feche antes de a
     pulseira parar. Sem `--ciclos 1`, a demo recomeça em loop, já com
     variação.
   - Ao parar, a pulseira publica "offline", e o painel e o app mostram
     "Pulseira: offline".

### Linha do tempo

Os tempos são contados desde o início do simulador e variam ±3 s com o ruído
dos sensores.

| Tempo | Fase no log | O que aparece no painel (e no app) | O que mostrar ou dizer |
|---|---|---|---|
| 0:00–1:00 | `demo 1/7 · calmo` | "Sem sinais de crise"; o modelo começa a avaliar após 31 s de leituras | Os 7 sensores; o modelo roda na própria pulseira (processamento na borda) |
| 1:00–2:30 | `demo 2/7 · exercício` | BPM, EDA e movimento sobem juntos. Na maior parte do tempo, "Sem sinais de crise"; às vezes aparece um **"Atenção"** curto e quase nunca "Possível crise" | A pulseira reconhece o exercício (movimento irregular sem EDA elevada) e espera 30 s antes de alertar; limitação real: a EDA também sobe no exercício, por isso o sistema é apoio e o cuidador avalia |
| 2:30–3:30 | `demo 3/7 · calmo` | Volta ao normal; um eventual alerta do exercício vira 1 episódio encerrado no histórico | Histerese: o episódio só fecha após 30 s calmos |
| 3:30 | `demo 4/7 · crise com ruído: ruído subindo` | O ruído sobe para ~88 dB; o modelo continua em baixo risco | O ambiente mudou, mas a criança ainda está bem |
| 3:47 | `… fisiologia subindo` | BPM e EDA sobem de repente (em ~10 s), HRV cai | — |
| ~3:49 | ainda `… fisiologia subindo` (a fase `demo 4/7 · crise com ruído` começa às 3:57) | **"Possível crise"** + *"Provável gatilho: ruído (45 → 87 dB, cerca de 11 s antes da alteração fisiológica)"* (ou "… antes do alerta do modelo", quando o modelo alerta antes de BPM e EDA passarem da margem); episódio "em andamento" no histórico | Detectar a crise (modelo) × indicar o provável gatilho (regra explicável); "provável", nunca causa |
| 5:30 | `demo 5/7 · recuperação` | Sinais voltam ao normal; o alerta some por volta de 6:20 | — |
| ~6:50 | — | O episódio encerra no histórico (~2 min 30 s) | Clicar em **Confirmar gatilho** e escrever uma observação ("som alto na sala") |
| 7:00 | `demo 6/7 · crise sem gatilho` | Por volta de 7:02: **"Possível crise"** + *"Sem gatilho ambiental aparente: luz e ruído estáveis. A causa pode ser outra (social, rotina, desconforto físico)."* | O sistema não inventa uma causa quando o ambiente não mudou |
| 9:00 | `demo 7/7 · recuperação` | O alerta some por volta de 9:50; o episódio encerra por volta de 10:20 | — |
| 9:25–11:25 | `pausa calma final · encerra em … s` | Resumo de padrões, por exemplo "Ruído como provável gatilho: 1 de 3 episódios · 1 confirmado pelo cuidador" | Clicar em **Exportar CSV** (registro de testes do TCC); o histórico fica guardado na pulseira (LGPD) |

O total do resumo costuma ser 2 ou 3 episódios: as duas crises e, às
vezes, 1 alerta curto do exercício. Se ele aparecer, dá para clicar em
**Descartar** durante a fala sobre limitações e mostrar a avaliação do
cuidador.

### Plano B (sem internet ou sem broker)

O painel e o app dependem do broker, e a pulseira só começa a contar o
roteiro depois de conectar. Depois de conectada, ela continua processando se
a conexão cair. Antes, o modo "Simulador manual" rodava o modelo no próprio
navegador, sem rede; esse modo deixou de existir, porque o site não processa
mais nada. Sem broker, mostre os resultados offline, que passam pelo mesmo
processamento da pulseira:

1. `cd simulator` e `npm run verificar -- --cenario demo --sementes 5`: a
   tabela mostra, para cada ciclo do `demo`, os episódios, o nível máximo e o
   gatilho identificado.
2. `cd frontend` e `node scripts/cenarios.mjs`: o relatório dos cenários de
   ponta a ponta (quantas vezes o gatilho certo foi identificado).
3. Mostre um histórico já gravado em `simulator/data/historico_<id>.json`
   (de uma execução anterior) ou um CSV exportado antes.

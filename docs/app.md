# App do cuidador (`mobile/`)

App Android em Flutter para o cuidador acompanhar a criança pelo celular. Ele
**não roda o modelo**: recebe da **pulseira** o estado já processado, pelo
broker MQTT, e devolve a ela o "Estou ciente" e a avaliação do gatilho. A
pulseira roda o modelo, os episódios e o gatilho (processamento na borda), então
o app **funciona com o site fechado**. O site é só o painel do desenvolvedor.
Tópicos e formatos: [mqtt.md](mqtt.md).

O app não precisou de nenhuma mudança quando o processamento saiu do site e
foi para a pulseira: os tópicos e os formatos das mensagens são os mesmos.
Isso foi conferido com `npm run verificar-app` com a pulseira ligada e o site
fechado ([testes.md](testes.md#app-do-cuidador-sem-o-site-verificar-app)).

As telas (login, home, gráficos, configurações) vieram do repositório
[mariafernandarsantos/puzzleband](https://github.com/mariafernandarsantos/puzzleband)
(pasta `frontend/`). Os dados fixos foram trocados pelos dados reais e o
necessário foi acrescentado. Depois, o visual foi redesenhado para o público
(cuidadores de crianças com TEA), com tema único, acessibilidade e tema
escuro: [design-app.md](design-app.md).

## O que o app faz

- **Estado ao vivo**: Calmo / Atenção / Possível crise, com cor **e** ícone,
  BPM atual e média dos últimos 5 minutos.
- **Alerta**: quando há um episódio em andamento, a Home mostra um card com o
  provável gatilho e o botão **Estou ciente**. O toque mostra "Ciente às
  HH:MM" por 5 s, e o botão não volta para o mesmo episódio. A pulseira
  grava o horário no episódio e, se o painel do site estiver aberto, ele
  mostra "Alerta visto pelo cuidador às HH:MM".
- **Painel do dia**: o botão **Hoje: X episódios** abre, na própria Home,
  todos os episódios de hoje (do mais recente para o mais antigo) com um
  relatório curto de cada um. Tocar num episódio abre o detalhe, com
  **Confirmar gatilho** / **Descartar**.
- **Lembretes e nome da criança**: o cuidador deixa lembretes curtos (de um
  episódio ou do dia), com aviso opcional no celular, e escolhe o nome que
  aparece na Home. Isso fica **só no celular** (ver
  [Lembretes](#lembretes-e-nome-da-criança)).
- **Notificação** com som e vibração quando chega um alerta de atenção ou de
  possível crise, com no máximo uma por episódio, **mesmo com o app
  fechado** (serviço em primeiro plano; detalhes abaixo).
- **Configurar alertas**: na primeira abertura, uma tela com passos
  numerados (notificações, bateria e, em Samsung, "Apps em suspensão") para
  os alertas chegarem com o app fechado (ver
  [Configuração na primeira abertura](#configuração-na-primeira-abertura)).
- **Gráficos**: os sinais dos últimos 5 minutos (BPM, suor, HRV, movimento,
  regularidade, luz, ruído e probabilidade, uma métrica por vez), com um
  balão que mostra todas as métricas do instante tocado, e as crises dos
  últimos 7 dias pela avaliação do cuidador.
- **Histórico** dos episódios (os 50 mais recentes que a pulseira publica),
  separado por dia, com um **calendário** do mês no topo. Cada episódio é um
  cartão resumido que abre no lugar, com **Confirmar gatilho** / **Descartar**
  e uma observação curta. A avaliação volta para a pulseira, que aplica e
  republica o histórico (o painel do site mostra "avaliado pelo app"). A
  última cópia fica salva no celular para consulta offline.
- **Indicadores de conexão** (Ajustes): servidor, pulseira (online/offline)
  e "Análise (pulseira)" (ao vivo ou sem dados), que indica se o **estado
  publicado pela pulseira** está chegando ao vivo. O modelo roda na pulseira;
  não depende do site estar aberto.
- **Presença**: o app publica `online`/`offline` (com Last Will) em
  `puzzleband/<id>/app/status`. O painel do site mostra "App do cuidador:
  conectado/desconectado". Com o monitoramento ligado, quem publica é o
  serviço em primeiro plano (o app continua "conectado" com ele fechado).

## Telas

| Tela | Conteúdo |
|---|---|
| Login | Só navega para a tela Início (antes, na primeira abertura, para **Configurar alertas**). Mostra o aviso "Versão de demonstração: qualquer usuário e senha entram". |
| Configurar alertas | Passos numerados, cada um com um botão que abre a janela certa do sistema e um ✓ verde quando concedido (conferido de novo ao voltar para o app): **Permitir notificações**, **Rodar sem restrição de bateria** e, só em celulares Samsung, **Tirar dos "Apps em suspensão"** (com "Já fiz"). **Começar** fica destacado quando tudo tem ✓; **Continuar sem isso** entra assim mesmo, depois de um aviso. Ver [Configuração na primeira abertura](#configuração-na-primeira-abertura). |
| Início | Segue o modelo do Figma ([design-app.md](design-app.md#71-início-a-partir-do-modelo-do-figma)). De cima para baixo: o **nome da criança**; o aviso fixo **"Alertas com o app fechado desativados — Corrigir"** (só enquanto o monitoramento com o app fechado não estiver funcionando); a linha de conexão ("Tudo conectado" ou o aviso da pulseira); a **faixa de estado**, com o nível (ícone + palavra + cor), o BPM ao vivo e, ao lado, "Ao vivo" com a média de 5 min; o **cartão do episódio** em andamento (desde quando, nível mais alto, provável gatilho em linguagem simples com o texto do gatilho abaixo e o botão **Estou ciente**) ou, sem episódio, o cartão **Nenhum episódio agora** com o último episódio; a probabilidade estimada e a fonte; e o botão **Hoje: X episódios**, que abre o painel do dia. Sem estado ao vivo, a faixa diz o motivo e o que fazer (conectando, sem conexão, pulseira parou de enviar, aguardando a pulseira, configuração incompleta). |
| Episódio (detalhe) | Aberto pelo painel do dia ou pelo cartão "Nenhum episódio agora". Mesmo cartão do Histórico (com **Confirmar gatilho** / **Descartar**), o horário de início e fim e o lembrete do episódio. |
| Gráficos | **Sinais da criança**: as leituras dos últimos 5 minutos recebidas no tópico `estado`. Um seletor no topo escolhe a métrica (batimentos, suor/EDA, HRV, movimento, regularidade, luz, ruído ou probabilidade); o gráfico troca a série, o eixo e a cor. Faixas de fundo marcam os momentos em Atenção e Possível crise. Abaixo, a leitura atual, a mínima, a máxima e a média. Tocar ou arrastar no gráfico abre um balão com **todas** as métricas daquele instante. Com a pulseira parada ou sem conexão, o gráfico fica congelado, com um aviso. **Crises nos últimos 7 dias**: barras empilhadas com as crises confirmadas (cor sólida) e as aguardando confirmação (listradas). Os descartados não entram. Tocar numa barra mostra os totais e a duração somada do dia. |
| Histórico | Calendário do mês (recolhível, ver [Calendário do Histórico](#calendário-do-histórico)) e a lista separada por dia ("Hoje", "Ontem", "Ter, 3 de nov."), com o número de episódios no cabeçalho, que fica fixo ao rolar. Cada episódio é um cartão resumido: horário (início–fim), nível (ícone + texto), duração, gatilho em linguagem simples e a avaliação. Tocar abre o cartão no lugar, um por vez: texto técnico do gatilho, probabilidade máxima, "alerta visto às HH:MM", lembrete do episódio, observação (até 200 caracteres) e os botões **Confirmar gatilho** / **Descartar**. Avisa quando está mostrando a cópia salva. |
| Ajustes | Criança monitorada (campo **Nome da criança** e o `CHILD_ID`), conexões (servidor/broker com o erro, pulseira e análise ao vivo da pulseira), **Alertas**: **Alertas sonoros** (liga/desliga, salva no celular), **Monitorar com o app fechado** (ligada por padrão; inicia e para o serviço em primeiro plano) e **Configurar alertas** (abre a mesma tela da primeira abertura), **Aparência** (Seguir o sistema, Claro ou Escuro), **Apagar dados deste aparelho** (ver [Apagar os dados](#apagar-os-dados-reset-para-uma-apresentação)), versão e licenças. |

O app respeita a fonte ampliada e o "Remover animações" do Android. Detalhes
em [design-app.md](design-app.md).

### Tema claro ou escuro

**No app.**

1. Abra **Ajustes** (última aba) e role até **Aparência**.
2. Toque em **Seguir o sistema** (o padrão: usa o tema escolhido no Android),
   **Claro** ou **Escuro**.

- O tema muda na hora, sem reiniciar o app. A barra de status e a barra de
  navegação do Android acompanham o tema escolhido.
- A escolha fica salva **só neste celular** (`shared_preferences`, como o
  nome da criança). Ela não vai para o MQTT nem para o site.
- A tela de abertura, que aparece por um instante antes do app carregar,
  segue sempre o tema do Android.

**No site (painel).**

1. No cabeçalho, ao lado de **Fonte dos dados**, use o grupo **Tema**:
   **◐ Sistema** (o padrão), **☀ Claro** ou **☾ Escuro**.

- A escolha fica salva no navegador (`localStorage`) e vale nas próximas
  vezes que a página for aberta.
- Se o navegador bloquear o armazenamento, o tema volta a seguir o sistema.
- O tema do site e o do app são independentes.

Paleta, contrastes e decisões do tema escuro:
[design-app.md](design-app.md#8-tema-escuro).

### Estado "ao vivo"

A pulseira publica o estado 1×/s com retain. Se a pulseira desligar, o broker
guarda o último estado, que pode ser antigo. O app só considera o estado **ao vivo** se
ele chegou nos últimos 6 s (para a mensagem retida, vale o horário dela). Fora
disso, a Home mostra **Sem dados** (cinza, ícone de sensor desligado) e o
horário da última atualização. Assim, um estado velho não aparece como se
fosse atual.

### Notificações

- Chegou um alerta de `atencao` ou `alto_risco`: notificação local com
  título **Atenção** ou **Possível crise** e o texto do gatilho. Usa um canal
  Android de alta importância, com som e vibração.
- **Com o app fechado.** Um **serviço em primeiro plano** do Android
  (pacote `flutter_foreground_task`) mantém a sua própria conexão MQTT (as
  mesmas credenciais do `env.json`, embutidas pelo `--dart-define`, e a
  mesma reconexão) e continua rodando quando o app é tirado dos recentes.
  Ele mostra uma notificação fixa e discreta, **"Puzzle Band: monitorando
  <nome>"**, num canal próprio de baixa importância (sem som), separado dos
  alertas. Ele assina só `alertas`, `historico` e `status` (não o `estado`,
  que chega 1 vez por segundo) e mantém a cópia salva do histórico em dia.
  Código: `lib/services/monitor_segundo_plano.dart`.
- **Tipo do serviço: `specialUse`.** No Android 14 e 15 todo serviço em
  primeiro plano declara um tipo. O `dataSync` não serve: no Android 15 ele
  roda no máximo 6 h a cada 24 h e não pode ser iniciado no BOOT_COMPLETED.
  `remoteMessaging` é para mensagens de texto entre aparelhos, `health` exige
  permissão de sensores do corpo e `connectedDevice`, ligação direta com o
  dispositivo (a pulseira chega pelo servidor). O `specialUse` cobre "casos
  válidos não cobertos pelos outros tipos", sem pré-requisito nem limite de
  tempo; a justificativa fica no manifesto (só é revisada na Play Store; o
  app é distribuído por APK).
- **Quem notifica: só um.** Com o serviço rodando, **só ele** notifica os
  alertas (mesmo com o app aberto) e publica a presença do app; a conexão
  das telas entra sem Last Will e não notifica. Sem o serviço (opção
  desligada ou parado pelo sistema), o app aberto volta a notificar e a
  publicar "online" com Last Will **na hora**. O app confere o serviço ao
  abrir, ao voltar para a frente e a cada 5 s enquanto aberto; se ele parou e
  a opção está ligada, inicia de novo. As **mesmas regras** valem para os
  dois lados (`lib/services/regra_de_notificacao.dart`): como app e serviço
  rodam em isolates separados, cada um relê do disco a lista de episódios
  notificados (e a opção de som) antes de decidir e grava logo depois de
  notificar.
- **No máximo uma por episódio, mais a subida.** Se o mesmo episódio subir
  de atenção para possível crise, a mesma notificação é substituída por
  "Possível crise" e **toca de novo** (pode ser uma crise começando dentro de
  um episódio que já estava aberto, por exemplo durante um exercício).
  Alerta repetido no mesmo nível ou descendo não notifica. Os episódios já
  notificados ficam salvos, então reabrir o app não repete a notificação.
  Alertas com mais de 10 minutos não notificam.
- **Alertas sonoros** desligado: a notificação aparece num canal sem som e
  sem vibração. O Android não deixa mudar o som de um canal depois de criado,
  por isso existem dois canais.
- No Android 13 ou mais novo, a permissão de notificação
  (`POST_NOTIFICATIONS`) é pedida no passo 1 de **Configurar alertas**. Se o
  cuidador negar duas vezes, o Android não mostra mais a janela; o botão
  passa a abrir os ajustes de notificação do app.
- **"Monitoramento pausado — toque para corrigir"** (canal **Avisos do
  monitoramento**, alta importância): aparece se a notificação ou a isenção
  de bateria forem revogadas (o serviço confere a cada 5 min) ou se o
  serviço morrer e não voltar. Para este caso há um vigia: a cada 5 min o
  serviço reagenda o aviso para dali a 15 min, em modo **inexato**
  (`inexactAllowWhileIdle`, sem a permissão de alarme exato); se o serviço
  morrer, o aviso dispara sozinho (o Android pode atrasá-lo até ~10 min).
  Tocar abre o app, que leva a **Configurar alertas**. Desligar a opção nos
  Ajustes desarma o vigia e apaga o aviso.
- **Depois de reiniciar o celular**, o serviço volta sozinho, se a opção
  estava ligada (o pacote não religa um serviço que o app parou). Se o
  sistema matar o processo, o próprio Android religa o serviço (START_STICKY;
  conferido no emulador).
- Os avisos dos **lembretes** usam um terceiro canal, **Lembretes**, de
  importância normal, separado dos alertas (ver
  [Lembretes](#lembretes-e-nome-da-criança)).

### Configuração na primeira abertura

Depois do login, na primeira vez, o app mostra **Configurar alertas** antes
do Início. A tela explica em linguagem simples e tem um botão por passo, que
abre **exatamente** a janela do sistema:

1. **Permitir notificações** — a janela do sistema de `POST_NOTIFICATIONS`
   (Android 13+).
2. **Rodar sem restrição de bateria** — a janela do sistema
   `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` ("Permitir que o app rode
   sempre em segundo plano?"). Essa janela exige a permissão
   `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` no manifesto, que a Play Store só
   aceita em alguns tipos de app. **O Puzzle Band é distribuído por APK**,
   então ela pode ser usada; numa publicação na Play Store, o passo teria de
   abrir a lista de otimização de bateria e o tutor procuraria o app nela.
3. **Só em celulares Samsung** (pelo fabricante, `Build.MANUFACTURER`):
   "Configurações → Bateria → Limites de uso em segundo plano → retirar o
   Puzzle Band de 'Apps em suspensão'", com um botão que abre os detalhes do
   app (`ACTION_APPLICATION_DETAILS_SETTINGS`). O app não consegue conferir
   esse passo: o tutor confirma com **Já fiz**.

Cada passo ganha um **✓ verde** quando o app confere que foi concedido (de
novo a cada volta para o app, no `onResume`). **Começar** fica destacado
quando todos têm ✓, inicia o serviço e entra no app. **Continuar sem isso**
não bloqueia: abre um aviso ("sem esses passos, os alertas só chegam com o
app aberto") e o Início passa a mostrar o aviso fixo **"Alertas com o app
fechado desativados — Corrigir"** até resolver. Se depois algo se perder
(notificação ou bateria revogadas, ou o serviço parado e não religado), o
app mostra "Monitoramento pausado" (quando ainda pode notificar) e, ao
abrir, leva direto a **Configurar alertas**. A mesma tela abre pelos
Ajustes (**Configurar alertas**) e pelo **Corrigir** do Início. Código:
`lib/screens/configurar_alertas_screen.dart`,
`lib/services/configuracao_de_alertas.dart` e
`lib/services/sistema_android.dart` (com o canal nativo em
`android/.../MainActivity.kt`).

### Lembretes e nome da criança

**Nome da criança.** Em **Ajustes → Criança monitorada → Nome da criança**,
digite o nome (até 40 caracteres). Ele aparece no alto da tela Início e é
salvo a cada letra. Com o campo vazio, a Início mostra o `CHILD_ID`.

**Lembrete do dia.**

1. Na Início, toque em **Hoje: X episódios** para abrir o painel.
2. Toque em **Adicionar lembrete do dia**, escreva (até 120 caracteres) e
   toque em **Salvar lembrete**.
3. Para mudar ou apagar, toque em **Editar** no lembrete e depois em
   **Salvar lembrete** ou **Apagar lembrete**.

O lembrete do dia vale só para aquele dia: no dia seguinte, o painel começa
sem lembrete. Os de dias anteriores são apagados depois de 30 dias.

**Lembrete de um episódio.**

1. No painel do dia, toque no episódio para abrir o detalhe.
2. Em **Lembrete**, toque em **Adicionar lembrete**, escreva e salve.
3. O lembrete aparece no detalhe e no painel, embaixo do episódio. No
   detalhe, use **Editar lembrete** ou **Apagar lembrete**.

**Aviso no celular (opcional).**

- No editor do lembrete, toque em **Escolher horário**. Um horário que já
  passou hoje vale para amanhã. Para tirar o aviso, toque no **X** ao lado
  do horário.
- No horário, o celular mostra uma notificação no canal **Lembretes**, com
  som normal e sem tela cheia, mesmo com o app fechado. Só não funciona se o
  app for "forçado a parar" nas configurações do Android.
- O aviso é **inexato**: o Android pode atrasar alguns minutos para
  economizar bateria. Ele não pede a permissão de "alarme exato".
- Com a tela bloqueada por PIN, padrão ou digital, o Android **não mostra
  nada do lembrete**: o celular toca, e o texto aparece depois de
  desbloquear.
- O aviso continua agendado depois que o celular reinicia.
- Precisa da permissão de notificação do app. Se o aparelho não conseguir
  agendar, o app avisa e salva o lembrete sem aviso.
- Apagar o lembrete, ou salvar sem horário, cancela o aviso.

**Privacidade (decisão do projeto).**

- Os lembretes e o nome da criança ficam **só neste celular**, no
  `shared_preferences`.
- Eles **não são enviados pelo MQTT** (não há tópico nem campo novo nas
  mensagens), não aparecem no site e não vão para outro aparelho.
- Motivo: são anotações pessoais do cuidador sobre a criança, e o broker é
  compartilhado com a pulseira e o painel, com uma credencial que fica dentro
  do APK (ver
  [Limitações](#limitações)).
- Consequência: limpar os dados do app, desinstalar ou trocar de celular
  apaga os lembretes, e outro cuidador não vê os lembretes deste. A
  notificação do aviso não leva o nome da criança.

### Apagar os dados (reset para uma apresentação)

Há três jeitos de apagar o que o app guarda, do mais completo ao mais local:

- **Pelo terminal, sem mexer no celular:** `npm run resetar` em
  `simulator/`, com a pulseira desligada (passo a passo em [apresentacao.md](apresentacao.md#resetar-para-uma-apresentação)). O app assina `puzzleband/<id>/comando`. Ao receber
  a ordem `resetar` com um `id` que ainda não aplicou:
  - apaga a cópia do histórico, os episódios já notificados, os alertas
    recebidos, os lembretes (e cancela os avisos agendados deles) e o buffer
    dos gráficos;
  - com `manter_preferencias: false` (`npm run resetar -- --tudo`), também
    volta ao padrão o nome da criança, a aparência e os alertas sonoros;
  - mostra o SnackBar "Dados apagados para uma nova
    apresentação." e confirma em `comando/resposta`, e o terminal mostra
    "App limpo".

  O id aplicado fica salvo (`reset_aplicado_id`). Como a ordem é retida, ela
  chega a cada conexão, mas só é aplicada uma vez. Com o app fechado durante
  o reset, ele aplica quando abrir. Detalhes em
  [mqtt.md](mqtt.md#ordem-de-reset-npm-run-resetar).
- **Pelo app:** **Ajustes → Dados deste aparelho → Apagar dados deste
  aparelho**. Faz a mesma limpeza local, depois de uma confirmação na tela.
  A opção "Também voltar as preferências ao padrão" vem desmarcada. Não
  publica nada, então os episódios guardados na pulseira voltam a aparecer
  quando ela publicar de novo.
- **Pelo cabo:** `adb shell pm clear br.unimar.puzzleband` (o
  `applicationId` de `android/app/build.gradle.kts`). Apaga tudo, como uma
  reinstalação.

O app só aceita um `historico` com `"origem": "pulseira"`. Uma lista de
outra origem, como a de uma aba antiga do site que republicava o
`localStorage`, não substitui a cópia salva.

### Calendário do Histórico

O calendário conta pela **sua avaliação**, não pelo nível que o modelo deu:

| Você marcou o episódio como | No calendário |
|---|---|
| Confirmado (**Confirmar gatilho**) | Conta como **crise** no dia, qualquer que tenha sido o nível |
| Pendente (ainda não avaliou) | **Possível crise aguardando confirmação**: não entra na contagem nem na cor |
| Descartado (**Descartar**) | Não aparece no calendário de forma nenhuma (nem no gráfico de 7 dias) |

**Como ler um dia.**

- **Fundo amarelo**: de 1 a 5 crises confirmadas no dia.
- **Fundo vermelho**: mais de 5 crises confirmadas.
- **Sem cor**: nenhuma crise confirmada.
- **Número pequeno** embaixo do dia: quantas crises você confirmou. A cor
  nunca é a única informação.
- **Bolinha azul** ao lado do número: o dia só tem possíveis crises
  aguardando sua confirmação (nenhuma confirmada). É um lembrete para
  revisar esses episódios. Se o dia já tem alguma crise confirmada, a
  bolinha não aparece.
- **Contorno**: o dia de hoje.

O leitor de tela fala o dia inteiro, por exemplo "3 de novembro: 4 crises
confirmadas" ou "5 de novembro: 2 possíveis crises aguardando confirmação".

**Usar o calendário.**

- Tocar num dia mostra só os episódios dele ("Mostrando só 3 de
  novembro."). **Ver todos** (ou tocar de novo no mesmo dia) volta à lista
  inteira.
- As setas trocam o mês, do primeiro mês com episódio até o mês atual.
- O botão com a seta para cima recolhe o calendário; recolhido, ele mostra
  só o mês e o total ("Em novembro: 9 crises confirmadas e 2 aguardando sua
  confirmação.").

**"Possível crise" tem dois sentidos, e o app separa os dois.**

- O **nível do modelo** "Possível crise" (`alto_risco`) aparece numa pílula
  cheia e tingida, com o ícone do nível, ao lado do horário do episódio.
- A **avaliação pendente** aparece sempre como **"Possível crise · a
  confirmar"**: uma pílula só com contorno azul, com uma ampulheta, no fim do
  cartão. Tocar nela abre o cartão já nos botões de avaliação.

**Confirmar e descartar.**

- **Confirmar gatilho** diz que o episódio foi mesmo uma crise. Ele passa a
  contar no calendário e no gráfico de 7 dias, e o botão vira
  **Confirmado**. Confirmar também ajuda o Puzzle Band a aprender os padrões
  desta criança em versões futuras. Por enquanto o app só envia a
  avaliação; nenhum aprendizado roda no celular.
- **Descartar** diz que a indicação não fazia sentido. O botão fica
  vermelho, com o texto **Descartado**, e o cartão mostra o selo
  "Descartado". O episódio continua na lista, mas sai do calendário e do
  gráfico de 7 dias.
- Dá para mudar de ideia: tocar no outro botão reenvia a avaliação à
  pulseira (tópico `avaliacao`, como antes). Sem conexão, o app avisa que não
  enviou.

## Configuração (`env.json`)

As credenciais não ficam no código. Elas entram na compilação por
`--dart-define-from-file`:

```bash
cd mobile
copy env.example.json env.json     # Windows (Linux/macOS: cp env.example.json env.json)
```

Preencha `MQTT_PASS` com a senha do usuário `app` no EMQX Cloud:

```json
{
  "MQTT_HOST": "g12cbd17.ala.us-east-1.emqxsl.com",
  "MQTT_PORT": "8883",
  "MQTT_USER": "app",
  "MQTT_PASS": "senha-do-usuario-app",
  "CHILD_ID": "C01"
}
```

- `CHILD_ID` precisa ser igual ao `CHILD_ID` da pulseira (`simulator/.env`)
  e ao `VITE_CHILD_ID` do `frontend/.env`, se usar o painel.
- O `env.json` está no `.gitignore` e **não vai para o Git**. O
  `env.example.json` (sem senha) vai.
- Sem `env.json` (ou com campo vazio), o app abre normalmente, mas mostra
  "Broker: não configurado" e, em Configurações, qual variável falta.
- Os valores são lidos **na compilação**. Depois de mudar o `env.json`, pare
  o app e rode de novo (o *hot reload* não basta).

## Como rodar

Pré-requisitos: Flutter SDK (o projeto foi validado com o Flutter 3.47.9),
Android Studio com os plugins Flutter e Dart, e um Android SDK. O celular
precisa de internet, porque o broker está na nuvem. Não é preciso estar na
mesma rede Wi-Fi do computador.

### Pelo Android Studio

1. **File → Open** e escolha a pasta `Puzzle-Band/mobile`. Se pedir, clique
   em **Pub get** (ou rode `flutter pub get` no terminal da IDE).
2. Crie o `env.json` (seção acima).
3. **Run → Edit Configurations…** → selecione a configuração Flutter
   (`main.dart`) → em **Additional run args** coloque
   `--dart-define-from-file=env.json` → **OK**.
4. Escolha o dispositivo na barra de ferramentas e clique em **Run ▶**.

**Emulador**: **Tools → Device Manager → Create Virtual Device**. Use uma
imagem com Android 13 (API 33) ou mais novo para testar o pedido de
permissão de notificação. O emulador usa a internet do computador.

**Celular físico**:

1. No celular: **Configurações → Sobre o telefone →** toque 7 vezes em
   **Número da versão** para liberar as **Opções do desenvolvedor**. Lá,
   ative a **Depuração USB**.
2. Ligue o celular no computador pelo cabo USB e aceite o pedido "Permitir
   depuração USB?". Ele aparece na lista de dispositivos do Android Studio.
   No Android 11 ou mais novo também dá para usar a **Depuração por Wi-Fi**
   (Device Manager → Pair Devices Using Wi-Fi).
3. Para a demonstração, desative a otimização de bateria do app
   (**Configurações → Apps → Puzzle Band → Bateria → Sem restrições**).
   Assim o Android demora mais para encerrar o app em segundo plano.

### Pelo terminal

```bash
cd mobile
flutter pub get
flutter devices                                    # lista emuladores e celulares
flutter run --dart-define-from-file=env.json       # roda no dispositivo conectado
flutter run -d emulator-5554 --dart-define-from-file=env.json   # escolhe um dispositivo
```

Para gerar um APK de teste (fica em `build/app/outputs/flutter-apk/app-debug.apk`):

```bash
flutter build apk --debug --dart-define-from-file=env.json
```

### Verificações

```bash
flutter analyze      # análise estática (deve dar "No issues found!")
flutter test         # parse das mensagens, resumos, notificação, telas, acessibilidade e imagens (golden)
flutter test --update-goldens test/goldens_test.dart   # só depois de mudar o visual de propósito
```

As imagens das telas ficam em `test/goldens/` (estados, tema escuro e fonte
1,3×). Elas foram geradas no Windows; em outro sistema, gere de novo antes
de comparar.

### Testar os alertas com o app fechado (emulador ou celular)

1. Gere e instale o APK de release (em `mobile/`):
   `flutter build apk --release --dart-define-from-file=env.json` e
   `adb install -r build/app/outputs/flutter-apk/app-release.apk` (ou copie
   o arquivo para o celular e abra). Num celular que já tinha o app, a tela
   de configuração só aparece na primeira abertura depois de instalar; para
   vê-la de novo, use Ajustes → Configurar alertas.
2. Abra o app, entre e faça a **Configurar alertas**: **Permitir
   notificações** → Permitir; **Liberar a bateria** → Permitir; num Samsung,
   **Abrir os ajustes do app**, siga o caminho da tela e toque em **Já
   fiz**. Toque em **Começar**. Na gaveta de notificações deve aparecer
   "Puzzle Band: monitorando <nome>" (entre as silenciosas).
3. Tire o app dos recentes (botão de apps recentes → deslize o Puzzle Band
   para cima). A notificação fixa continua.
4. No computador: `cd simulator` e `npm run crise-ruido -- --uma-vez`.
5. Por volta de 2 min 18 s, a notificação **Possível crise** (com o texto do
   gatilho) chega com o app fechado.
6. Opcional: com o app aberto no Início, rode de novo o passo 4: deve
   aparecer **uma** notificação (a de atenção, trocada por "Possível crise"
   na subida), não duas. No emulador, `adb logcat -s flutter` mostra quem
   notificou ("notificado pelo servico").
7. Opcional: reinicie o celular sem abrir o app; depois de ligar, a
   notificação "monitorando" volta sozinha (pode levar alguns segundos).

Resultado no emulador (Android API 37, 09/11/2026): os passos 2 a 6
funcionaram (a "Possível crise" chegou com o app fechado e, com o app
aberto, só o serviço notificou: atenção e a subida, na mesma notificação).
Sem a isenção de bateria, o serviço mostrou "Monitoramento pausado" na
conferência seguinte (~5 min); tocar nele abriu o app e, depois do login,
a **Configurar alertas** com o passo da bateria pendente. Um crash do
processo (`adb shell am crash`) foi religado pelo próprio Android na hora.
`adb shell am stopservice` não para o serviço (não exportado) e
`am force-stop` cancela tudo (ver Limitações).

## Estrutura

```
mobile/
├── env.example.json            # modelo do env.json (sem senha)
├── assets/fonts/               # Atkinson Hyperlegible Next (licença OFL)
├── lib/
│   ├── main.dart               # inicializa serviços, rotas, barra inferior, ciclo de vida
│   ├── config/app_config.dart  # MQTT_HOST, MQTT_PORT, MQTT_USER, MQTT_PASS, CHILD_ID e tópicos
│   ├── models/models.dart      # parse validado de estado, alertas e histórico
│   ├── models/resumo.dart      # contagens por dia/mês/7 dias pela avaliação do cuidador; lista por dia
│   ├── models/sinais.dart      # leituras dos últimos 5 min (todas as métricas), faixas de eixo e trechos de nível
│   ├── services/
│   │   ├── mqtt_service.dart        # conexão MQTT (ChangeNotifier): papel "app" (telas) ou "serviço"
│   │   ├── notification_service.dart# notificações locais dos alertas, "Monitoramento pausado" e canais Android
│   │   ├── regra_de_notificacao.dart# regra das notificações e quem notifica (app aberto x serviço)
│   │   ├── monitor_segundo_plano.dart# serviço em primeiro plano: controle e a tarefa com o app fechado
│   │   ├── configuracao_de_alertas.dart# passos de "Configurar alertas" e a opção "Monitorar com o app fechado"
│   │   ├── sistema_android.dart     # janelas do sistema, fabricante e o serviço (interface + Android)
│   │   ├── app_scope.dart           # entrega o serviço às telas (InheritedNotifier)
│   │   ├── preferencias_locais.dart # nome da criança e lembretes (só no celular)
│   │   └── aviso_de_lembrete.dart   # aviso agendado do lembrete (canal "Lembretes")
│   ├── theme/                  # tema único: cores (claro/escuro), tipografia, medidas, movimento
│   ├── screens/                # login, início, detalhe do episódio, gráficos, histórico, ajustes
│   ├── widgets/                # faixa de estado, cartões do episódio (completo e resumido), calendário, selo da avaliação, painel do dia, lembretes, nível, gatilho, cabeçalho...
│   └── utils/                  # datas, horas, durações; relógio das telas
└── test/                       # flutter test (apoio/ = serviço falso, cenários e fontes; goldens/ = imagens)
```

Pacote Android: `br.unimar.puzzleband`. O `AndroidManifest.xml` principal
declara `INTERNET`, `POST_NOTIFICATIONS`, `VIBRATE` e `RECEIVE_BOOT_COMPLETED`.
Esta última, junto com os dois receivers do `flutter_local_notifications`,
reagenda os avisos dos lembretes depois que o celular reinicia (e religa o
serviço em primeiro plano). Para os alertas com o app fechado:
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE` (o serviço, com a
justificativa em `PROPERTY_SPECIAL_USE_FGS_SUBTYPE`), `WAKE_LOCK` e
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (a janela do passo 2; ver
[Configuração na primeira abertura](#configuração-na-primeira-abertura)).

**Bateria.** O serviço segura um **wake lock parcial** (a CPU fica
acordada; a tela, não). Ele é necessário: com a tela desligada a CPU
dorme, o ping do MQTT (a cada 60 s) atrasa e o servidor derruba a conexão,
e aí nenhum alerta chega. Por isso o consumo é contínuo e maior que o de um
app parado: a CPU não entra em sono profundo enquanto o monitoramento estiver
ligado. O tráfego, ao contrário, é pequeno (o ping, os alertas, o
histórico e o status; não o estado de 1 mensagem por segundo). O consumo
real precisa ser medido no piloto (Configurações → Bateria); quem não
precisar dos alertas com o app fechado pode desligar a opção nos Ajustes. Antes,
`INTERNET` só existia no manifesto de debug, então um APK de release não teria
rede.

## Limitações

- **Os alertas chegam com o app fechado**, pelo serviço em primeiro plano,
  mas **não depois de "Forçar parada"** (Configurações → Apps → Puzzle Band):
  ela para o serviço, cancela o vigia e o religamento automático, e o app só
  volta a monitorar quando for aberto. Também não chegam se o sistema
  bloquear o app por bateria (sem a isenção, ou com restrições do fabricante,
  como os "Apps em suspensão" da Samsung): por isso os passos da
  **Configurar alertas**. O aviso "Monitoramento pausado" cobre a perda das
  permissões e a morte do serviço sem volta, mas pode atrasar até ~25 min.
- **A pulseira precisa estar ligada** (o site não). O modelo e a regra de
  gatilho rodam nela. Com a pulseira desligada não há estado, alertas nem
  histórico novos, e o app mostra "Pulseira: offline" e "Painel: sem dados".
- **Push via Firebase Cloud Messaging fica como trabalho futuro.** Ele
  dispensaria o serviço em primeiro plano (sem notificação fixa nem wake
  lock) e funcionaria mesmo depois de "Forçar parada", mas exige um
  servidor sempre ligado assinando os alertas da pulseira e enviando o push
  (o modelo já roda na pulseira, então esse servidor não precisaria
  processar nada).
- **Login sem autenticação real.** A tela de login só navega. Qualquer pessoa
  com o app vê os dados da criança configurada. Num produto real, seria
  preciso conta por cuidador e autorização por criança.
- **As credenciais do app ficam dentro do APK.** O `--dart-define` embute
  `MQTT_USER`/`MQTT_PASS` no binário, e dá para extrair. A ACL do broker
  ([mqtt.md](mqtt.md#acl-sugerida-menor-privilégio)) limita o que essa
  credencial pode fazer. A solução definitiva é a autenticação por usuário
  (tokens emitidos por um backend).
- O histórico do app tem só os 50 episódios mais recentes que a pulseira publicou.
  Por isso o calendário, o total do mês e o gráfico de 7 dias contam apenas
  esses: com muitos episódios, os meses mais antigos ficam incompletos.
- A média de BPM é a dos últimos 5 minutos calculada pela pulseira, não a do dia
  inteiro. O app guarda as leituras dos últimos 5 minutos só na memória,
  para o gráfico: fechar o app apaga essas leituras.
- **Lembretes só no celular.** Por decisão de privacidade, eles não têm
  cópia na pulseira, no site nem no broker: limpar os dados do app (ou o
  `npm run resetar`) ou trocar de celular apaga os lembretes. O aviso é inexato (pode atrasar alguns minutos).
- Só Android. A pasta `ios/` veio do projeto original e não foi configurada
  (o bundle id ainda é o de exemplo, e as notificações não foram ajustadas
  para iOS).

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
  possível crise, com no máximo uma por episódio (detalhes abaixo).
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
- **Indicadores de conexão**: broker, pulseira (online/offline) e "Painel" (ao
  vivo ou sem dados). O nome "Painel" ficou da versão em que o site
  processava. Hoje ele indica se o **estado publicado pela pulseira** está
  chegando ao vivo; não depende do site estar aberto.
- **Presença**: o app publica `online`/`offline` (com Last Will) em
  `puzzleband/<id>/app/status`. O painel do site mostra "App do cuidador:
  conectado/desconectado".

## Telas

| Tela | Conteúdo |
|---|---|
| Login | Só navega para a tela Início. Mostra o aviso "Versão de demonstração: qualquer usuário e senha entram". |
| Início | Segue o modelo do Figma ([design-app.md](design-app.md#71-início-a-partir-do-modelo-do-figma)). De cima para baixo: o **nome da criança**; a linha de conexão ("Tudo conectado" ou o aviso da pulseira); a **faixa de estado**, com o nível (ícone + palavra + cor), o BPM ao vivo e, ao lado, "Ao vivo" com a média de 5 min; o **cartão do episódio** em andamento (desde quando, nível mais alto, provável gatilho em linguagem simples com o texto do gatilho abaixo e o botão **Estou ciente**) ou, sem episódio, o cartão **Nenhum episódio agora** com o último episódio; a probabilidade estimada e a fonte; e o botão **Hoje: X episódios**, que abre o painel do dia. Sem estado ao vivo, a faixa diz o motivo e o que fazer (conectando, sem conexão, painel parado, aguardando o painel, configuração incompleta). |
| Episódio (detalhe) | Aberto pelo painel do dia ou pelo cartão "Nenhum episódio agora". Mesmo cartão do Histórico (com **Confirmar gatilho** / **Descartar**), o horário de início e fim e o lembrete do episódio. |
| Gráficos | **Sinais da criança**: as leituras dos últimos 5 minutos recebidas no tópico `estado`. Um seletor no topo escolhe a métrica (batimentos, suor/EDA, HRV, movimento, regularidade, luz, ruído ou probabilidade); o gráfico troca a série, o eixo e a cor. Faixas de fundo marcam os momentos em Atenção e Possível crise. Abaixo, a leitura atual, a mínima, a máxima e a média. Tocar ou arrastar no gráfico abre um balão com **todas** as métricas daquele instante. Com o painel parado ou sem conexão, o gráfico fica congelado, com um aviso. **Crises nos últimos 7 dias**: barras empilhadas com as crises confirmadas (cor sólida) e as aguardando confirmação (listradas). Os descartados não entram. Tocar numa barra mostra os totais e a duração somada do dia. |
| Histórico | Calendário do mês (recolhível, ver [Calendário do Histórico](#calendário-do-histórico)) e a lista separada por dia ("Hoje", "Ontem", "Ter, 3 de nov."), com o número de episódios no cabeçalho, que fica fixo ao rolar. Cada episódio é um cartão resumido: horário (início–fim), nível (ícone + texto), duração, gatilho em linguagem simples e a avaliação. Tocar abre o cartão no lugar, um por vez: texto técnico do gatilho, probabilidade máxima, "alerta visto às HH:MM", lembrete do episódio, observação (até 200 caracteres) e os botões **Confirmar gatilho** / **Descartar**. Avisa quando está mostrando a cópia salva. |
| Ajustes | Criança monitorada (campo **Nome da criança** e o `CHILD_ID`), conexões (servidor/broker com o erro, pulseira e painel), opção **Alertas sonoros** (liga/desliga, salva no celular), **Aparência** (Seguir o sistema, Claro ou Escuro), versão e licenças. |

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

A tela de GPS (vazia) saiu da navegação. O arquivo `gps_screen.dart`
continua no projeto e mostra "em breve".

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
- **No máximo uma por episódio.** Se o mesmo episódio subir de atenção para
  possível crise, a mesma notificação é atualizada para "Possível crise" sem
  tocar de novo. Os episódios já notificados ficam salvos, então reabrir o app
  não repete a notificação. Alertas com mais de 10 minutos não notificam.
- **Alertas sonoros** desligado: a notificação aparece num canal sem som e
  sem vibração. O Android não deixa mudar o som de um canal depois de criado,
  por isso existem dois canais.
- No Android 13 ou mais novo, o app pede a permissão de notificação
  (`POST_NOTIFICATIONS`) na primeira abertura. Se o cuidador negar, dá para
  liberar depois em Configurações do Android → Apps → Puzzle Band →
  Notificações.
- Os avisos dos **lembretes** usam um terceiro canal, **Lembretes**, de
  importância normal, separado dos alertas (ver
  [Lembretes](#lembretes-e-nome-da-criança)).

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

- `CHILD_ID` precisa ser igual ao `VITE_CHILD_ID` do `frontend/.env`.
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
│   │   ├── mqtt_service.dart        # serviço MQTT único (ChangeNotifier)
│   │   ├── notification_service.dart# notificações locais dos alertas e canais Android
│   │   ├── app_scope.dart           # entrega o serviço às telas (InheritedNotifier)
│   │   ├── preferencias_locais.dart # nome da criança e lembretes (só no celular)
│   │   └── aviso_de_lembrete.dart   # aviso agendado do lembrete (canal "Lembretes")
│   ├── theme/                  # tema único: cores (claro/escuro), tipografia, medidas, movimento
│   ├── screens/                # login, início, detalhe do episódio, gráficos, histórico, ajustes (+ gps "em breve")
│   ├── widgets/                # faixa de estado, cartões do episódio (completo e resumido), calendário, selo da avaliação, painel do dia, lembretes, nível, gatilho, cabeçalho...
│   └── utils/                  # datas, horas, durações; relógio das telas
└── test/                       # flutter test (apoio/ = serviço falso, cenários e fontes; goldens/ = imagens)
```

Pacote Android: `br.unimar.puzzleband`. O `AndroidManifest.xml` principal
declara `INTERNET`, `POST_NOTIFICATIONS`, `VIBRATE` e `RECEIVE_BOOT_COMPLETED`.
Esta última, junto com os dois receivers do `flutter_local_notifications`,
reagenda os avisos dos lembretes depois que o celular reinicia. Antes,
`INTERNET` só existia no manifesto de debug, então um APK de release não teria
rede.

## Limitações

- **O app só recebe com o processo vivo**, ou seja, aberto ou em segundo
  plano recente. O Android pode encerrar o app em segundo plano (economia de
  bateria). A partir daí ele não recebe nada até ser aberto de novo. O "Sem
  restrições" de bateria ajuda, mas não garante.
- **A pulseira precisa estar ligada** (o site não). O modelo e a regra de
  gatilho rodam nela. Com a pulseira desligada não há estado, alertas nem
  histórico novos, e o app mostra "Pulseira: offline" e "Painel: sem dados".
- **Notificação com o app fechado** exigiria push (Firebase Cloud Messaging)
  e um serviço sempre ligado assinando os alertas da pulseira e enviando o
  push. O modelo já roda na pulseira, então esse serviço não precisaria
  processar nada. Fica como trabalho futuro.
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
  cópia na pulseira, no site nem no broker: limpar os dados do app ou trocar de celular
  apaga os lembretes. O aviso é inexato (pode atrasar alguns minutos).
- Só Android. A pasta `ios/` veio do projeto original e não foi configurada
  (o bundle id ainda é o de exemplo, e as notificações não foram ajustadas
  para iOS).

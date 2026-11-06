# App do cuidador (`mobile/`)

App Android em Flutter para o cuidador acompanhar a criança pelo celular. Ele
**não roda o modelo**: recebe do site (o painel, que é o "servidor") o estado
já processado, pelo broker MQTT, e devolve o "Estou ciente" e a avaliação do
gatilho. Tópicos e formatos: [mqtt.md](mqtt.md).

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
  HH:MM" por 5 s, e o botão não volta para o mesmo episódio. O site então
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
- **Histórico** dos episódios (os 50 mais recentes do site), com **Confirmar
  gatilho** / **Descartar** e uma observação curta. A avaliação volta para o
  site, que mostra "avaliado pelo app". A última cópia fica salva no celular
  para consulta offline.
- **Indicadores de conexão**: broker, pulseira (online/offline) e painel/site
  (ao vivo ou sem dados).
- **Presença**: o app publica `online`/`offline` (com Last Will) em
  `puzzleband/<id>/app/status`. O site mostra "App do cuidador:
  conectado/desconectado".

## Telas

| Tela | Conteúdo |
|---|---|
| Login | Só navega para a tela Início. Mostra o aviso "Versão de demonstração: qualquer usuário e senha entram". |
| Início | Segue o modelo do Figma ([design-app.md](design-app.md#71-início-a-partir-do-modelo-do-figma)). De cima para baixo: o **nome da criança**; a linha de conexão ("Tudo conectado" ou o aviso da pulseira); a **faixa de estado**, com o nível (ícone + palavra + cor), o BPM ao vivo e, ao lado, "Ao vivo" com a média de 5 min; o **cartão do episódio** em andamento (desde quando, nível mais alto, provável gatilho em linguagem simples com o texto do site abaixo e o botão **Estou ciente**) ou, sem episódio, o cartão **Nenhum episódio agora** com o último episódio; a probabilidade estimada e a fonte; e o botão **Hoje: X episódios**, que abre o painel do dia. Sem estado ao vivo, a faixa diz o motivo e o que fazer (conectando, sem conexão, painel parado, aguardando o painel, configuração incompleta). |
| Episódio (detalhe) | Aberto pelo painel do dia ou pelo cartão "Nenhum episódio agora". Mesmo cartão do Histórico (com **Confirmar gatilho** / **Descartar**), o horário de início e fim e o lembrete do episódio. |
| Gráficos | BPM dos últimos 5 minutos recebidos no tópico `estado` (ao vivo) e episódios por dia nos últimos 7 dias (barra = número de episódios; cor = nível mais alto do dia), com uma frase-resumo (últimos 7 dias e mês). Sem dados, mostra uma mensagem em vez do gráfico. |
| Histórico | Lista dos episódios: nível máximo, dia e hora ("Hoje, 14:32"), duração, provável gatilho, "alerta visto às HH:MM", avaliação em destaque, botões **Confirmar gatilho** / **Descartar** e uma observação opcional (até 200 caracteres, em "Adicionar observação"). Avisa quando está mostrando a cópia salva. |
| Ajustes | Criança monitorada (campo **Nome da criança** e o `CHILD_ID`), conexões (servidor/broker com o erro, pulseira e painel), opção **Alertas sonoros** (liga/desliga, salva no celular), versão e licenças. |

O tema segue o do sistema (claro ou escuro) e respeita a fonte ampliada e o
"Remover animações" do Android. Detalhes em [design-app.md](design-app.md).

A tela de GPS (vazia) saiu da navegação. O arquivo `gps_screen.dart`
continua no projeto e mostra "em breve".

### Estado "ao vivo"

O site publica o estado 1×/s com retain. Se o site fechar, o broker guarda o
último estado, que pode ser antigo. O app só considera o estado **ao vivo** se
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
  compartilhado com o site, com uma credencial que fica dentro do APK (ver
  [Limitações](#limitações)).
- Consequência: limpar os dados do app, desinstalar ou trocar de celular
  apaga os lembretes, e outro cuidador não vê os lembretes deste. A
  notificação do aviso não leva o nome da criança.

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
│   ├── models/resumo.dart      # episódios do dia, do mês e dos últimos 7 dias
│   ├── services/
│   │   ├── mqtt_service.dart        # serviço MQTT único (ChangeNotifier)
│   │   ├── notification_service.dart# notificações locais dos alertas e canais Android
│   │   ├── app_scope.dart           # entrega o serviço às telas (InheritedNotifier)
│   │   ├── preferencias_locais.dart # nome da criança e lembretes (só no celular)
│   │   └── aviso_de_lembrete.dart   # aviso agendado do lembrete (canal "Lembretes")
│   ├── theme/                  # tema único: cores (claro/escuro), tipografia, medidas, movimento
│   ├── screens/                # login, início, detalhe do episódio, gráficos, histórico, ajustes (+ gps "em breve")
│   ├── widgets/                # faixa de estado, cartões do episódio, painel do dia, lembretes, nível, gatilho, cabeçalho...
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
- **O site precisa estar aberto.** O modelo e a regra de gatilho rodam no
  navegador. Sem o site aberto não há estado, alertas nem histórico novos. O
  app mostra "Painel: sem dados".
- **Notificação com o app fechado** exigiria push (Firebase Cloud Messaging)
  e um servidor sempre ligado rodando o modelo, ou pelo menos assinando os
  alertas e enviando o push. Fica como trabalho futuro.
- **Login sem autenticação real.** A tela de login só navega. Qualquer pessoa
  com o app vê os dados da criança configurada. Num produto real, seria
  preciso conta por cuidador e autorização por criança.
- **As credenciais do app ficam dentro do APK.** O `--dart-define` embute
  `MQTT_USER`/`MQTT_PASS` no binário, e dá para extrair. A ACL do broker
  ([mqtt.md](mqtt.md#acl-sugerida-menor-privilégio)) limita o que essa
  credencial pode fazer. A solução definitiva é a autenticação por usuário
  (tokens emitidos por um backend).
- O histórico do app tem só os 50 episódios mais recentes que o site enviou.
  Por isso "Picos de estresse no mês" conta apenas esses.
- A média de BPM é a dos últimos 5 minutos calculada pelo site, não a do dia
  inteiro: o app não guarda as leituras.
- **Lembretes só no celular.** Por decisão de privacidade, eles não têm
  cópia no site nem no broker: limpar os dados do app ou trocar de celular
  apaga os lembretes. O aviso é inexato (pode atrasar alguns minutos).
- Só Android. A pasta `ios/` veio do projeto original e não foi configurada
  (o bundle id ainda é o de exemplo, e as notificações não foram ajustadas
  para iOS).

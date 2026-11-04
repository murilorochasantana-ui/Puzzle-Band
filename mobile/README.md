# Puzzle Band — app do cuidador (Flutter)

App Android que mostra o estado da criança ao vivo, notifica alertas e mostra
o histórico. Recebe tudo do site (painel) pelo broker MQTT. Documentação
completa: [../docs/app.md](../docs/app.md). Tópicos:
[../docs/mqtt.md](../docs/mqtt.md).

## Configurar (uma vez)

```bash
copy env.example.json env.json     # Windows (Linux/macOS: cp env.example.json env.json)
```

Preencha `MQTT_PASS` (usuário `app` do EMQX Cloud) no `env.json`. Ele está no
`.gitignore` e nunca vai para o Git.

## Rodar

**Android Studio:** abra a pasta `mobile/` → **Run → Edit Configurations…** →
configuração Flutter `main.dart` → **Additional run args**:
`--dart-define-from-file=env.json` → **OK** → escolha o emulador ou o
celular → **Run ▶**.

**Terminal:**

```bash
flutter pub get
flutter run --dart-define-from-file=env.json
```

Telas originais: [mariafernandarsantos/puzzleband](https://github.com/mariafernandarsantos/puzzleband).

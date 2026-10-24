<#
.SYNOPSIS
    Desbostificar.ps1 - otimização do Windows 11 feita sob medida para ESTE PC.

.DESCRIPTION
    PC alvo (do diagnostico_pc.txt):
      Ryzen 5 5500 | RTX 3060 | 16 GB | Gigabyte A520M DS3H | Windows 11 Home 25H2 (build 26200)
      C: SSD ADATA 1 TB (~85% cheio) | F: SSD Netac 256 GB (vazio) | E: HD Seagate 1 TB (Riot Games)
    Perfil deduzido: jogos + programação + design. Antivírus: só o Microsoft Defender.

    NÍVEIS (cada um inclui o anterior):
      LEVE      Telemetria e propagandas desligadas, apps-lixo removidos, launchers de jogos
                fora do boot, apps sem segundo plano, plano de energia ajustado, limpeza de temporários.
      MÉDIO     + Steam/Discord/Notion fora do boot, serviços inúteis em Manual, tarefas de
                telemetria desligadas, mais apps removidos, Bing fora do Iniciar, caches de
                navegador/Discord/Steam, limpeza de componentes do Windows Update (DISM).
      AGRESSIVO + plano Desempenho Máximo, apps removidos também para novos usuários,
                todos os apps da Microsoft sem segundo plano, DISM /ResetBase, caches de npm/pip/NuGet.

    O QUE ESTE SCRIPT NUNCA TOCA:
      Windows Update (serviços/configurações), Microsoft Defender/Firewall/SmartScreen, drivers
      (NVIDIA, AMD, Realtek, Wacom, Corsair, Logitech), Microsoft Store, Riot Vanguard, WSL,
      Gaming Services/Xbox Identity (Minecraft e Game Pass dependem deles).

    SEGURANÇA:
      - Abre em MODO SIMULAÇÃO: mostra tudo o que faria sem alterar nada. Tecle S no menu para aplicar.
      - Antes de aplicar, cria um ponto de restauração do sistema.
      - Toda alteração é anotada em C:\Desbostificar\desfazer.jsonl com o valor ANTIGO,
        e a opção "Desfazer tudo" usa esse arquivo para voltar exatamente ao que era.
      - Logs de cada execução ficam em C:\Desbostificar\logs\.

.PARAMETER Nivel
    Roda direto, sem menu: Leve, Medio, Agressivo, Limpeza, Desfazer ou Relatorio.

.PARAMETER Aplicar
    Sem este parâmetro o script SEMPRE simula. Com ele, aplica de verdade (usado junto com -Nivel).

.EXAMPLE
    .\Desbostificar.ps1                      # menu interativo (começa em simulação)
.EXAMPLE
    .\Desbostificar.ps1 -Nivel Medio         # simula o nível Médio
.EXAMPLE
    .\Desbostificar.ps1 -Nivel Medio -Aplicar
#>
[CmdletBinding()]
param(
    [ValidateSet('Leve', 'Medio', 'Agressivo', 'Limpeza', 'Desfazer', 'Relatorio')]
    [string]$Nivel,
    [switch]$Aplicar
)

#region ======================= 0. PRÉ-REQUISITOS =======================
# Precisa do Windows PowerShell 5.1 (o que já vem no Windows) rodando como administrador:
# o ponto de restauração (Checkpoint-Computer) e a remoção de apps (Appx) não funcionam
# direito no PowerShell 7. Se abriu do jeito errado, o script se reabre sozinho do jeito certo.
$ehAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if ($PSVersionTable.PSEdition -eq 'Core' -or -not $ehAdmin) {
    $ps51 = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argumentos = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Nivel)   { $argumentos += " -Nivel $Nivel" }
    if ($Aplicar) { $argumentos += ' -Aplicar' }
    try {
        Start-Process -FilePath $ps51 -ArgumentList $argumentos -Verb RunAs -ErrorAction Stop
    } catch {
        Write-Host 'Não consegui abrir como administrador (o aviso do UAC foi recusado?).' -ForegroundColor Red
        Write-Host 'Clique com o botão direito no EXECUTAR-Desbostificar.bat > Executar como administrador.' -ForegroundColor Red
        Read-Host 'Enter para sair' | Out-Null
    }
    exit
}

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'   # barras de progresso deixam os cmdlets de Appx bem mais lentos
try { $Host.UI.RawUI.WindowTitle = 'Desbostificar' } catch { }
#endregion

#region ======================= 1. CONFIGURAÇÃO (EDITE AQUI) =======================
# Marque $true no que você USA. Os valores abaixo foram deduzidos do diagnóstico;
# na dúvida o script MANTÉM a coisa funcionando.
$Config = @{
    # Minecraft (Bedrock + Launcher) e Gaming Services estão instalados: o app Xbox e a
    # Game Bar ficam. Mude para $false se não usa Game Pass nem o app Xbox.
    UsaXbox       = $true

    # O OneDrive está abrindo no boot e pode estar sincronizando Área de Trabalho/Documentos,
    # então o script NÃO desliga. Mude para $false para tirá-lo da inicialização (nada é desinstalado).
    UsaOneDrive   = $true

    # Tem o complemento de reuniões do Teams instalado, o que sugere conta de faculdade/trabalho.
    # Com $true o Teams fica, mas sai do boot no nível Médio. Com $false ele é removido.
    UsaTeams      = $true

    # Copilot e Widgets: desligados por padrão (o painel de Widgets é notícia + propaganda).
    UsaCopilot    = $false
    UsaWidgets    = $false

    # Não há software de impressora no diagnóstico, mas Photoshop/Illustrator às vezes reclamam
    # sem o serviço de impressão, e desligá-lo economiza quase nada. Só mude se quiser mesmo.
    UsaImpressora = $true
}
# Bluetooth: a A520M DS3H não tem Bluetooth na placa e o serviço só liga quando um adaptador
# é conectado, então não há nada a ganhar mexendo nele. O script não toca no Bluetooth.

$PastaDados     = Join-Path $env:SystemDrive 'Desbostificar'
$PastaLogs      = Join-Path $PastaDados 'logs'
$ArquivoJournal = Join-Path $PastaDados 'desfazer.jsonl'
#endregion

#region ======================= 2. O QUE CADA NÍVEL FAZ (TABELAS) =======================
# N = nível mínimo (1 Leve, 2 Médio, 3 Agressivo). Se = condição vinda da CONFIGURAÇÃO.
# Para tirar um item, comente a linha com #. Para mudar o nível dele, troque o N.

$CDM = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'  # motor das "sugestões"/propagandas
$ADV = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

# ---------- 2.1 Registro: telemetria, propagandas, sugestões, jogos ----------
$TweaksRegistro = @(
    # TELEMETRIA: no Windows Home o mínimo aceito é "Obrigatório"; o valor 0 força esse mínimo.
    @{ N = 1; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; K = 'AllowTelemetry'; V = 0; D = 'Telemetria no mínimo possível' }
    @{ N = 1; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; K = 'DoNotShowFeedbackNotifications'; V = 1; D = 'Sem pop-ups pedindo feedback' }
    @{ N = 1; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; K = 'AllowDeviceNameInTelemetry'; V = 0; D = 'Não mandar o nome do PC junto com a telemetria' }
    @{ N = 1; P = 'HKCU:\Software\Microsoft\Siuf\Rules'; K = 'NumberOfSIUFInPeriod'; V = 0; D = 'Frequência de pedidos de feedback: nunca' }
    @{ N = 1; P = 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows'; K = 'CEIPEnable'; V = 0; D = 'Programa de Aperfeiçoamento (CEIP) desligado' }
    @{ N = 1; P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; K = 'TailoredExperiencesWithDiagnosticDataEnabled'; V = 0; D = 'Sem "experiências personalizadas" com seus dados de diagnóstico' }
    @{ N = 1; P = 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent'; K = 'DisableTailoredExperiencesWithDiagnosticData'; V = 1; D = '(política) idem acima' }

    # RASTREIO PARA ANÚNCIOS
    @{ N = 1; P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; K = 'Enabled'; V = 0; D = 'ID de anúncio desligado (apps não te rastreiam para propaganda)' }
    @{ N = 1; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'; K = 'DisabledByGroupPolicy'; V = 1; D = '(política) ID de anúncio desligado' }
    @{ N = 1; P = 'HKCU:\Control Panel\International\User Profile'; K = 'HttpAcceptLanguageOptOut'; V = 1; D = 'Sites não leem sua lista de idiomas' }
    @{ N = 1; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; K = 'EnableActivityFeed'; V = 0; D = 'Histórico de atividades desligado' }
    @{ N = 1; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; K = 'PublishUserActivities'; V = 0; D = 'Não registrar atividades' }
    @{ N = 1; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; K = 'UploadUserActivities'; V = 0; D = 'Não enviar atividades para a nuvem' }

    # PROPAGANDAS E "SUGESTÕES" (Iniciar, Configurações, tela de bloqueio, notificações)
    @{ N = 1; P = $CDM; K = 'SilentInstalledAppsEnabled'; V = 0; D = 'Windows não instala apps patrocinados sozinho' }
    @{ N = 1; P = $CDM; K = 'PreInstalledAppsEnabled'; V = 0; D = 'Não reinstalar apps "promocionais"' }
    @{ N = 1; P = $CDM; K = 'PreInstalledAppsEverEnabled'; V = 0; D = 'idem' }
    @{ N = 1; P = $CDM; K = 'OemPreInstalledAppsEnabled'; V = 0; D = 'idem (apps de fabricante)' }
    @{ N = 1; P = $CDM; K = 'SystemPaneSuggestionsEnabled'; V = 0; D = 'Sem sugestões de apps no Iniciar' }
    @{ N = 1; P = $CDM; K = 'SubscribedContent-338388Enabled'; V = 0; D = 'Sem sugestões ocasionais no Iniciar' }
    @{ N = 1; P = $CDM; K = 'SoftLandingEnabled'; V = 0; D = 'Sem notificações de "dicas e truques"' }
    @{ N = 1; P = $CDM; K = 'SubscribedContent-338389Enabled'; V = 0; D = 'Sem dicas e sugestões ao usar o Windows' }
    @{ N = 1; P = $CDM; K = 'SubscribedContent-310093Enabled'; V = 0; D = 'Sem tela de "boas-vindas" depois de atualizações' }
    @{ N = 1; P = $CDM; K = 'SubscribedContent-338393Enabled'; V = 0; D = 'Sem conteúdo sugerido no app Configurações' }
    @{ N = 1; P = $CDM; K = 'SubscribedContent-353694Enabled'; V = 0; D = 'idem' }
    @{ N = 1; P = $CDM; K = 'SubscribedContent-353696Enabled'; V = 0; D = 'idem' }
    @{ N = 1; P = $CDM; K = 'SubscribedContent-338387Enabled'; V = 0; D = 'Sem "curiosidades" na tela de bloqueio' }
    @{ N = 1; P = $CDM; K = 'RotatingLockScreenOverlayEnabled'; V = 0; D = 'idem (textos sobre a imagem da tela de bloqueio)' }
    @{ N = 1; P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; K = 'ScoobeSystemSettingEnabled'; V = 0; D = 'Sem a tela "vamos terminar de configurar seu PC"' }
    @{ N = 1; P = $ADV; K = 'Start_IrisRecommendations'; V = 0; D = 'Iniciar sem recomendações de apps e dicas' }
    @{ N = 1; P = $ADV; K = 'Start_AccountNotifications'; V = 0; D = 'Iniciar sem avisos de conta (propaganda de OneDrive/M365)' }
    @{ N = 1; P = $ADV; K = 'ShowSyncProviderNotifications'; V = 0; D = 'Explorador de Arquivos sem propaganda de OneDrive/M365' }
    @{ N = 1; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; K = 'DisableWindowsConsumerFeatures'; V = 1; D = '(política) sem apps de "experiência do consumidor"' }
    @{ N = 1; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; K = 'DisableSoftLanding'; V = 1; D = '(política) sem dicas do Windows' }
    @{ N = 1; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; K = 'DisableConsumerAccountStateContent'; V = 1; D = '(política) sem avisos de conta' }
    @{ N = 1; P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; K = 'IsDynamicSearchBoxEnabled'; V = 0; D = 'Pesquisa sem "destaques" (doodles e notícias)' }
    @{ N = 1; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; K = 'EnableDynamicContentInWSB'; V = 0; D = '(política) idem' }

    # COPILOT E WIDGETS (conforme a CONFIGURAÇÃO)
    @{ N = 1; Se = (-not $Config.UsaCopilot); P = 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'; K = 'TurnOffWindowsCopilot'; V = 1; D = 'Copilot desligado (usuário)' }
    @{ N = 1; Se = (-not $Config.UsaCopilot); P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; K = 'TurnOffWindowsCopilot'; V = 1; D = 'Copilot desligado (máquina)' }
    @{ N = 1; Se = (-not $Config.UsaCopilot); P = $ADV; K = 'ShowCopilotButton'; V = 0; D = 'Sem botão do Copilot na barra de tarefas' }
    @{ N = 1; Se = (-not $Config.UsaWidgets); P = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; K = 'AllowNewsAndInterests'; V = 0; D = 'Widgets (notícias/clima com anúncios) desligados' }

    # JOGOS: você já grava com ShadowPlay/OBS, então a gravação contínua do Windows só gasta GPU/disco.
    @{ N = 1; P = 'HKCU:\System\GameConfigStore'; K = 'GameDVR_Enabled'; V = 0; D = 'Game DVR (gravação contínua em segundo plano) desligado' }
    @{ N = 1; P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; K = 'AppCaptureEnabled'; V = 0; D = 'Captura da Xbox Game Bar desligada' }
    @{ N = 1; P = 'HKCU:\Software\Microsoft\GameBar'; K = 'AutoGameModeEnabled'; V = 1; D = 'Modo de Jogo LIGADO (prioriza o jogo; sem reinício/driver no meio da partida)' }

    # ---------------- MÉDIO ----------------
    # Pesquisa do Iniciar só com o que está no PC (mais rápida, sem Bing). Também some o histórico de pesquisas.
    @{ N = 2; P = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; K = 'DisableSearchBoxSuggestions'; V = 1; D = 'Pesquisa do Iniciar sem resultados da web/Bing' }
    @{ N = 2; P = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'; K = 'BingSearchEnabled'; V = 0; D = 'Bing desligado na pesquisa' }
    # Personalização de escrita: coleta o que você digita e escreve com a caneta (Wacom) para "melhorar" o reconhecimento.
    @{ N = 2; P = 'HKCU:\Software\Microsoft\InputPersonalization'; K = 'RestrictImplicitInkCollection'; V = 1; D = 'Não coletar sua escrita com caneta' }
    @{ N = 2; P = 'HKCU:\Software\Microsoft\InputPersonalization'; K = 'RestrictImplicitTextCollection'; V = 1; D = 'Não coletar o que você digita' }
    @{ N = 2; P = 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore'; K = 'HarvestContacts'; V = 0; D = 'Não coletar contatos' }
    @{ N = 2; P = 'HKCU:\Software\Microsoft\Personalization\Settings'; K = 'AcceptedPrivacyPolicy'; V = 0; D = 'Personalização de escrita/digitação desligada' }
    @{ N = 2; P = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'; K = 'HasAccepted'; V = 0; D = 'Reconhecimento de voz online desligado (o ditado Win+H para de funcionar)' }
    @{ N = 2; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; K = 'AITEnable'; V = 0; D = 'Telemetria de compatibilidade de apps desligada' }
    @{ N = 2; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; K = 'DisableInventory'; V = 1; D = 'Lista de programas instalados não é enviada' }
    @{ N = 2; P = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting'; K = 'Disabled'; V = 1; D = 'Relatórios de erro não são enviados para a Microsoft' }
    # Edge: não é removido (o Windows e o WebView2 precisam dele), só para de rodar escondido.
    # Efeito colateral: o Edge mostra "gerenciado pela sua organização". É normal.
    @{ N = 2; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; K = 'StartupBoostEnabled'; V = 0; D = 'Edge não fica pré-carregado desde o boot' }
    @{ N = 2; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; K = 'BackgroundModeEnabled'; V = 0; D = 'Edge não continua rodando depois de fechado' }
    @{ N = 2; P = 'HKCU:\Software\Microsoft\GameBar'; K = 'UseNexusForGameBarEnabled'; V = 0; D = 'Botão Guia do controle não abre a Game Bar no meio do jogo' }

    # ---------------- AGRESSIVO ----------------
    @{ N = 3; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; K = 'LimitDiagnosticLogCollection'; V = 1; D = 'Limita a coleta de logs de diagnóstico' }
    @{ N = 3; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; K = 'LimitDumpCollection'; V = 1; D = 'Limita o envio de dumps de memória' }
    @{ N = 3; P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; K = 'DisableOneSettingsDownloads'; V = 1; D = 'Não baixar configurações de telemetria (OneSettings)' }
)
# Recall/IA: este PC não tem NPU (não é Copilot+), então o Recall nem existe aqui. Nada a mexer.

# ---------- 2.2 Apps pré-instalados para remover (só os que estão no seu diagnóstico) ----------
$AppsRemover = @(
    # LEVE: lixo e propaganda pura
    @{ N = 1; Nome = 'Microsoft.BingNews';                         D = 'Notícias (Bing) - feed com anúncios' }
    @{ N = 1; Nome = 'Microsoft.BingWeather';                      D = 'Clima (Bing) - feed com anúncios' }
    @{ N = 1; Nome = 'Microsoft.GetHelp';                          D = 'Obter Ajuda' }
    @{ N = 1; Nome = 'Microsoft.MicrosoftSolitaireCollection';     D = 'Paciência da Microsoft (com anúncios)' }
    @{ N = 1; Nome = 'TREECARDGAMES.SPIDERSOLITAIRECOLLECTIONFREE'; D = 'Spider Solitaire grátis (com anúncios)' }
    @{ N = 1; Nome = 'Microsoft.MicrosoftOfficeHub';               D = '"Microsoft 365" - só atalho/propaganda; você usa o WPS Office' }
    @{ N = 1; Nome = 'Microsoft.WindowsFeedbackHub';               D = 'Hub de Feedback' }
    @{ N = 1; Nome = 'MicrosoftCorporationII.MicrosoftFamily';     D = 'Microsoft Family (controle parental)' }
    @{ N = 1; Nome = 'Clipchamp.Clipchamp';                        D = 'Clipchamp (editor de vídeo online)' }
    @{ N = 1; Se = (-not $Config.UsaCopilot); Nome = 'Microsoft.Copilot'; D = 'Copilot' }
    # MÉDIO: apps que algumas pessoas usam, mas que não aparecem no seu fluxo
    @{ N = 2; Nome = 'Microsoft.BingSearch';                       D = 'Bing Search (resultados da web no Iniciar)' }
    @{ N = 2; Nome = 'Microsoft.Edge.GameAssist';                  D = 'Edge Game Assist (navegador dentro da Game Bar)' }
    @{ N = 2; Nome = 'Microsoft.Windows.DevHome';                  D = 'Dev Home (descontinuado pela Microsoft)' }
    @{ N = 2; Nome = 'Microsoft.Todos';                            D = 'Microsoft To Do (você usa Notion/Obsidian)' }
    @{ N = 2; Nome = 'Microsoft.OutlookForWindows';                D = 'Novo Outlook' }
    @{ N = 2; Nome = 'Microsoft.PowerAutomateDesktop';             D = 'Power Automate' }
    @{ N = 2; Nome = 'Microsoft.YourPhone';                        D = 'Vincular ao Celular' }
    @{ N = 2; Nome = 'MicrosoftCorporationII.QuickAssist';         D = 'Assistência Rápida (suporte remoto)' }
    @{ N = 2; Se = (-not $Config.UsaTeams); Nome = 'MSTeams';        D = 'Microsoft Teams' }
    @{ N = 2; Se = (-not $Config.UsaXbox);  Nome = 'Microsoft.GamingApp'; D = 'App Xbox' }
    # AGRESSIVO
    @{ N = 3; Nome = 'Microsoft.ZuneMusic';                        D = 'Media Player (você tem o VLC)' }
    @{ N = 3; Nome = 'Microsoft.WindowsSoundRecorder';             D = 'Gravador de Som' }
    @{ N = 3; Nome = 'Microsoft.WindowsAlarms';                    D = 'Relógio e Alarmes' }
    @{ N = 3; Nome = 'Microsoft.MicrosoftStickyNotes';             D = 'Notas Autoadesivas' }
    @{ N = 3; Se = (-not $Config.UsaXbox);  Nome = 'Microsoft.XboxGamingOverlay'; D = 'Xbox Game Bar' }
)

# Trava de segurança: nada que bata com esta lista é removido, mesmo que alguém coloque na lista acima.
$AppsProtegidos = @(
    'Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller',   # Store e winget
    'Microsoft.SecHealthUI', 'Microsoft.Windows.Apprep.ChxApp',                                # Defender e SmartScreen
    'Microsoft.Xbox.TCUI', 'Microsoft.XboxIdentityProvider', 'Microsoft.GamingServices',       # login Xbox (Minecraft/Game Pass)
    'Microsoft.4297127D64EC6', 'Microsoft.MinecraftUWP',                                       # Minecraft Launcher e Bedrock
    'Microsoft.MicrosoftEdge*', 'Microsoft.VCLibs*', 'Microsoft.UI.Xaml*', 'Microsoft.NET.*', '*WinAppRuntime*',
    'Microsoft.*Extension*',                                                                   # codecs HEVC/AV1/VP9/WebP/HEIF/RAW
    'Microsoft.WindowsTerminal', 'Microsoft.WindowsNotepad', 'Microsoft.WindowsCalculator',
    'Microsoft.Paint', 'Microsoft.ScreenSketch', 'Microsoft.Windows.Photos',
    'NVIDIACorp.*', 'RealtekSemiconductorCorp.*', 'MicrosoftWindows.*', 'Microsoft.OneDriveSync',
    'Microsoft.WidgetsPlatformRuntime', 'MicrosoftCorporationII.WindowsSubsystemForLinux'
)

# ---------- 2.3 Apps que ficam, mas sem rodar em segundo plano ----------
# São apps da Store que acordam sozinhos para atualizar bloco, notificar ou sincronizar.
# Abrem e funcionam normalmente quando você clica.
$AppsSemSegundoPlano = @(
    'Microsoft.Windows.Photos', 'Microsoft.WindowsCalculator', 'Microsoft.Paint', 'Microsoft.WindowsCamera',
    'Microsoft.ZuneMusic', 'Microsoft.WindowsSoundRecorder', 'Microsoft.MicrosoftStickyNotes', 'Microsoft.Todos',
    'Microsoft.OutlookForWindows', 'Microsoft.PowerAutomateDesktop', 'Microsoft.Windows.DevHome',
    'Microsoft.BingWeather', 'Microsoft.BingNews', 'Microsoft.GetHelp', 'Microsoft.WindowsFeedbackHub',
    'Microsoft.MicrosoftOfficeHub', 'Clipchamp.Clipchamp', 'Microsoft.Edge.GameAssist',
    'MicrosoftCorporationII.QuickAssist', 'MicrosoftCorporationII.MicrosoftFamily', 'Microsoft.MicrosoftSolitaireCollection'
)
# No Agressivo, TODOS os apps da Microsoft perdem o segundo plano, menos estes (precisam dele para funcionar):
$SegundoPlanoManter = @(
    'Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller', 'Microsoft.SecHealthUI',
    'Microsoft.WindowsAlarms', 'Microsoft.YourPhone', 'Microsoft.GamingApp', 'Microsoft.Xbox*', 'Microsoft.GamingServices',
    'MSTeams', 'Microsoft.OneDriveSync', 'Microsoft.WindowsTerminal', 'Microsoft.ScreenSketch',
    'Microsoft.4297127D64EC6', 'Microsoft.MinecraftUWP', 'Microsoft.WidgetsPlatformRuntime', 'Microsoft.MicrosoftEdge*',
    'Microsoft.VisualStudioCode', '*WinAppRuntime*', 'MicrosoftCorporationII.WindowsSubsystemForLinux',
    'Microsoft.LanguageExperiencePack*', 'Microsoft.Ink.*', '*Extension*', 'Microsoft.ApplicationCompatibilityEnhancements',
    'Microsoft.StartExperiencesApp'
)
# Apps de terceiros (WhatsApp, Spotify, Claude, Trello...) nunca são tocados aqui.

# ---------- 2.4 Programas que abrem junto com o Windows ----------
# É desligado do mesmo jeito que o Gerenciador de Tarefas > Aplicativos de inicialização faz,
# então dá para religar por lá também. Nada é desinstalado.
$InicializacaoDesativar = @(
    # LEVE
    @{ N = 1; Padrao = 'MicrosoftEdgeAutoLaunch_*'; D = 'Edge pré-carregado (seu navegador é o Chrome)' }
    @{ N = 1; Padrao = 'GoogleChromeAutoLaunch_*';  D = 'Chrome em segundo plano desde o boot (era o maior consumo de RAM no diagnóstico)' }
    @{ N = 1; Padrao = 'ut';                        D = 'µTorrent (anúncios + upload rodando escondido)' }
    @{ N = 1; Padrao = 'RobloxPlayerBeta';          D = 'Roblox na bandeja' }
    @{ N = 1; Padrao = 'EpicGamesLauncher';         D = 'Epic Games Launcher' }
    @{ N = 1; Padrao = 'EADM';                      D = 'EA app' }
    @{ N = 1; Padrao = 'RiotClient';                D = 'Riot Client (o Vanguard continua ativo e o jogo abre normal)' }
    @{ N = 1; Padrao = 'nefarius_HidHide_Updater';  D = 'atualizador do HidHide (o HidHide continua funcionando)' }
    @{ N = 1; Se = (-not $Config.UsaTeams); Padrao = 'Teams'; D = 'Teams' }
    # MÉDIO
    @{ N = 2; Padrao = 'Steam';                     D = 'Steam (abre quando você clicar; jogos não são afetados)' }
    @{ N = 2; Padrao = 'Discord';                   D = 'Discord' }
    @{ N = 2; Padrao = 'electron.app.Notion';       D = 'Notion' }
    @{ N = 2; Padrao = 'Figma Agent';               D = 'Figma Agent (só serve para fontes locais no Figma pelo navegador)' }
    @{ N = 2; Se = [bool]$Config.UsaTeams; Padrao = 'Teams'; D = 'Teams (abre quando você clicar)' }
    @{ N = 2; Se = (-not $Config.UsaOneDrive); Padrao = 'OneDrive'; D = 'OneDrive' }
)
# Ficam ligados de propósito: iCUE (RGB/ventoinhas Corsair), LGHUB (perfis do mouse Logitech),
# Riot Vanguard (anti-cheat), RtkAudUService (áudio Realtek), SecurityHealth (Defender).
$InicializacaoProtegida = @('SecurityHealth', 'RtkAudUService', 'Riot Vanguard', '*Defender*')

# ---------- 2.5 Serviços ----------
# "Manual" = só liga se algum programa pedir (seguro). "Desativado" = não liga nunca.
$ServicosAjustar = @(
    @{ N = 1; Nome = 'DiagTrack';             Tipo = 'Desativado'; D = 'Telemetria (Experiências do Usuário Conectado)' }
    @{ N = 1; Nome = 'MapsBroker';            Tipo = 'Desativado'; D = 'Mapas offline (o app Mapas nem está instalado)' }
    @{ N = 1; Nome = 'RetailDemo';            Tipo = 'Desativado'; D = 'Modo demonstração de loja' }
    @{ N = 2; Nome = 'dmwappushservice';      Tipo = 'Desativado'; D = 'Roteamento de mensagens WAP (usado pela telemetria)' }
    @{ N = 2; Nome = 'TrkWks';                Tipo = 'Manual';     D = 'Rastreamento de atalhos em rede (inútil em PC doméstico)' }
    @{ N = 2; Nome = 'SQLWriter';             Tipo = 'Manual';     D = 'SQL Server VSS Writer (o LocalDB do Visual Studio não precisa dele ligado)' }
    @{ N = 2; Nome = 'AdobeUpdateService';    Tipo = 'Manual';     D = 'Atualizador da Adobe (o Creative Cloud atualiza quando aberto)' }
    @{ N = 2; Nome = 'GigabyteUpdateService'; Tipo = 'Manual';     D = 'Atualizador da Gigabyte (não é driver; ficava rodando 24 h)' }
    @{ N = 2; Nome = 'Fax';                   Tipo = 'Desativado'; D = 'Fax' }
    @{ N = 2; Se = (-not $Config.UsaImpressora); Nome = 'Spooler'; Tipo = 'Manual'; D = 'Spooler de impressão ("Imprimir para PDF" do Windows deixa de funcionar)' }
    @{ N = 3; Nome = 'PcaSvc';                Tipo = 'Manual';     D = 'Assistente de Compatibilidade de Programas' }
    @{ N = 3; Nome = 'WSAIFabricSvc';         Tipo = 'Manual';     D = 'Componentes de IA do Windows (seu PC não é Copilot+)' }
)
# Ficam como estão de propósito:
#   SysMain  - pré-carrega jogos e programas na RAM; ajuda muito o HD E: (Riot Games).
#   WSearch  - sem ele a pesquisa do Iniciar fica lenta.
#   iphlpsvc - usado pelo multiplayer do Xbox/Game Pass (Teredo).
#   Inicialização Rápida - continua ligada (ajuda o "lento ao ligar").
# Trava de segurança: nunca alterados, mesmo que entrem na lista acima.
$ServicosProtegidos = @(
    'wuauserv', 'UsoSvc', 'WaaSMedicSvc', 'BITS', 'DoSvc', 'TrustedInstaller',                       # Windows Update
    'WinDefend', 'MDCoreSvc', 'WdNisSvc', 'SecurityHealthService', 'wscsvc', 'mpssvc', 'Sense',      # Defender/Firewall
    'webthreatdefsvc', 'AppXSvc', 'ClipSVC', 'InstallService', 'LicenseManager', 'wlidsvc',          # Store
    'TokenBroker', 'StorSvc', 'vgc', 'vgk', 'NVDisplay.ContainerLocalSystem', 'NvContainerLocalSystem',
    'GamingServices', 'GamingServicesNet', 'XboxGipSvc', 'VSS', 'swprv'                              # VSS = pontos de restauração
)

# ---------- 2.6 Tarefas agendadas ----------
$TarefasDesativar = @(
    @{ N = 1; Pasta = '\Microsoft\Windows\Maps\'; Nome = 'Maps*'; D = 'Mapas (app não instalado)' }
    @{ N = 1; Pasta = '\SoftLanding\*'; Nome = '*'; D = '"Dicas" e propaganda do Windows' }
    @{ N = 1; Pasta = '\'; Nome = 'OneDrive Reporting Task-*'; D = 'Relatórios/telemetria do OneDrive (ele continua funcionando)' }
    @{ N = 1; Pasta = '\'; Nome = 'WpsExternal_*'; D = 'Pop-ups e propaganda do WPS Office' }
    @{ N = 1; Pasta = '\'; Nome = 'nefarius_HidHide_Updater'; D = 'Atualizador do HidHide' }
    @{ N = 1; Pasta = '\Microsoft\Windows\Feedback\Siuf\'; Nome = 'DmClient*'; D = 'Coleta de feedback' }
    @{ N = 1; Pasta = '\Microsoft\Windows\Customer Experience Improvement Program\'; Nome = '*'; D = 'CEIP (telemetria)' }
    @{ N = 2; Pasta = '\Microsoft\Windows\Application Experience\'; Nome = 'Microsoft Compatibility Appraiser*'; D = 'Telemetria de compatibilidade (pesada, roda todo dia)' }
    @{ N = 2; Pasta = '\Microsoft\Windows\Application Experience\'; Nome = 'ProgramDataUpdater'; D = 'Telemetria de programas' }
    @{ N = 2; Pasta = '\Microsoft\Windows\Application Experience\'; Nome = 'MareBackup'; D = 'Backup de dados de telemetria' }
    @{ N = 2; Pasta = '\Microsoft\Windows\Autochk\'; Nome = 'Proxy'; D = 'Envio de dados do CEIP' }
    @{ N = 2; Pasta = '\Microsoft\Windows\DiskDiagnostic\'; Nome = 'Microsoft-Windows-DiskDiagnosticDataCollector'; D = 'Diagnóstico de disco enviado à Microsoft' }
    @{ N = 2; Pasta = '\Microsoft\Windows\Windows Error Reporting\'; Nome = 'QueueReporting'; D = 'Envio de relatórios de erro' }
    @{ N = 2; Pasta = '\Microsoft\Windows\PI\'; Nome = 'Sqm-Tasks'; D = 'Telemetria SQM' }
    @{ N = 2; Pasta = '\Microsoft\Windows\NetTrace\'; Nome = 'GatherNetworkInfo'; D = 'Coleta de dados de rede para o CEIP' }
    @{ N = 2; Pasta = '\Microsoft\Windows\Device Information\'; Nome = 'Device*'; D = 'Coleta de informações do dispositivo' }
    @{ N = 2; Pasta = '\GoogleUserPEH\'; Nome = '*'; D = 'Google "Platform Experience Helper" (métricas)' }
    @{ N = 2; Pasta = '\Ubisoft\'; Nome = 'Ubisoft Connect Background Update'; D = 'Atualização escondida do Ubisoft Connect' }
    @{ N = 2; Pasta = '\'; Nome = 'WpsUpdateTask_*'; D = 'Atualizador do WPS Office' }
    @{ N = 2; Se = (-not $Config.UsaOneDrive); Pasta = '\'; Nome = 'OneDrive Startup Task-*'; D = 'Reabertura automática do OneDrive' }
    @{ N = 3; Pasta = '\Microsoft\Windows\Flighting\FeatureConfig\'; Nome = 'UsageData*'; D = 'Relatórios de uso de recursos do Windows' }
)
# Ficam: atualizadores de NVIDIA, Zoom, OneDrive, Chrome e Edge (são correções de segurança),
# MSI Afterburner e a tarefa "Inicializar" (o script só mostra o que ela faz no Relatório).

$NomesNivel = @{ 1 = 'Leve'; 2 = 'Médio'; 3 = 'Agressivo' }
$GuidRegex  = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
#endregion

#region ======================= 3. LOG E REGISTRO DE ALTERAÇÕES =======================
$Script:Simular      = -not $Aplicar
$Script:SemPerguntas = [bool]$Nivel
$Script:Utf8         = New-Object System.Text.UTF8Encoding($false)
$Script:ArquivoLog   = $null
$Script:Stats        = @{ Feitos = 0; Simulados = 0; JaOk = 0; Erros = 0 }

# Mostra na tela (com cor) e grava no log da execução.
function Write-Linha {
    param(
        [string]$Mensagem,
        [ValidateSet('Info', 'Ok', 'Feito', 'Sim', 'Aviso', 'Erro', 'Titulo')][string]$Tipo = 'Info'
    )
    $cores    = @{ Info = 'Gray'; Ok = 'DarkGray'; Feito = 'Green'; Sim = 'Cyan'; Aviso = 'Yellow'; Erro = 'Red'; Titulo = 'Magenta' }
    $prefixos = @{ Info = ''; Ok = '[ok]       '; Feito = '[FEITO]    '; Sim = '[SIMULAÇÃO] '; Aviso = '[AVISO]    '; Erro = '[ERRO]     '; Titulo = '' }
    if ($Tipo -eq 'Titulo') {
        $texto = "=== $Mensagem ==="
        Write-Host ''
    } else {
        $texto = $prefixos[$Tipo] + $Mensagem
    }
    Write-Host $texto -ForegroundColor $cores[$Tipo]
    switch ($Tipo) {
        'Feito' { $Script:Stats.Feitos++ }
        'Sim'   { $Script:Stats.Simulados++ }
        'Ok'    { $Script:Stats.JaOk++ }
        'Erro'  { $Script:Stats.Erros++ }
    }
    if ($Script:ArquivoLog) {
        try { [System.IO.File]::AppendAllText($Script:ArquivoLog, ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $texto) + "`r`n", $Script:Utf8) } catch { }
    }
}

# Anota uma alteração (com o valor ANTIGO) no arquivo usado pelo "Desfazer tudo".
# Uma linha JSON por alteração: se o script for interrompido, o que já foi feito continua anotado.
function Add-Journal {
    param([hashtable]$Entrada)
    $Entrada['Quando']   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $Entrada['Execucao'] = $Script:IdExecucao
    $json = New-Object PSObject -Property $Entrada | ConvertTo-Json -Compress -Depth 3
    [System.IO.File]::AppendAllText($ArquivoJournal, $json + "`r`n", $Script:Utf8)
}

# Valores binários e de várias linhas viram texto para caber no JSON (e voltam no Desfazer).
function ConvertTo-ValorJournal {
    param($Valor, [string]$Tipo)
    if ($null -eq $Valor) { return $null }
    switch ($Tipo) {
        'Binary'      { return [Convert]::ToBase64String([byte[]]$Valor) }
        'MultiString' { return ([string[]]$Valor) -join [string][char]0 }
        default       { return $Valor }
    }
}
function ConvertFrom-ValorJournal {
    param($Valor, [string]$Tipo)
    switch ($Tipo) {
        'Binary'      { return , [Convert]::FromBase64String([string]$Valor) }
        'MultiString' { return , ([string]$Valor).Split([char]0) }
        'DWord'       { return [int]$Valor }
        'QWord'       { return [long]$Valor }
        default       { return [string]$Valor }
    }
}

function Test-Coringa {
    param([string]$Texto, [string[]]$Padroes)
    foreach ($p in $Padroes) { if ($Texto -like $p) { return $true } }
    return $false
}

# Filtra uma tabela da seção 2 pelo nível escolhido e pelas condições da CONFIGURAÇÃO.
function Select-PorNivel {
    param($Lista, [int]$N)
    $Lista | Where-Object { $_.N -le $N -and $_.Se -ne $false }
}

function Start-Execucao {
    param([string]$Acao)
    if (-not (Test-Path -LiteralPath $PastaLogs)) { New-Item -ItemType Directory -Path $PastaLogs -Force | Out-Null }
    $Script:IdExecucao         = Get-Date -Format 'yyyyMMdd_HHmmss'
    $sufixo                    = if ($Script:Simular) { '_SIMULACAO' } else { '' }
    $Script:ArquivoLog         = Join-Path $PastaLogs ("{0}_{1}{2}.log" -f $Script:IdExecucao, $Acao, $sufixo)
    $Script:Stats              = @{ Feitos = 0; Simulados = 0; JaOk = 0; Erros = 0 }
    $Script:AppsRemovidos      = @()
    $Script:CacheTarefas       = $null
    $Script:CacheProvisionados = $null
    $Script:BytesLimpeza       = 0
    $modo = if ($Script:Simular) { 'SIMULAÇÃO (nada é alterado)' } else { 'APLICANDO' }
    Write-Linha "Desbostificar | $Acao | $modo | $(Get-Date)"
    Write-Linha "PC: $Script:ResumoPC | Windows build $([Environment]::OSVersion.Version.Build)"
}

function Confirm-Acao {
    param([string]$Pergunta)
    if ($Script:Simular -or $Script:SemPerguntas) { return $true }
    $r = Read-Host "$Pergunta Digite SIM para continuar"
    return ($r.Trim() -eq 'SIM')
}
#endregion

#region ======================= 4. FERRAMENTAS (cada uma anota o que muda) =======================

# ---- 4.1 Ponto de restauração ----
function New-PontoRestauracao {
    param([string]$Descricao)
    Write-Linha 'Ponto de restauração' Titulo
    if ($Script:Simular) { Write-Linha "Criaria o ponto de restauração 'Desbostificar: $Descricao'" Sim; return $true }
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop   # liga a Proteção do Sistema no C: se estiver desligada
    } catch {
        Write-Linha "Não consegui ligar a Proteção do Sistema: $($_.Exception.Message)" Aviso
    }
    # O Windows só permite 1 ponto a cada 24 h. Zeramos esse limite só durante a criação e devolvemos depois.
    $chave      = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $freqAntiga = (Get-ItemProperty -LiteralPath $chave -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
    New-ItemProperty -LiteralPath $chave -Name SystemRestorePointCreationFrequency -Value 0 -PropertyType DWord -Force | Out-Null
    $antes = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber | Select-Object -Last 1
    try {
        Write-Linha 'Criando ponto de restauração (pode levar 1 ou 2 minutos)...'
        Checkpoint-Computer -Description "Desbostificar: $Descricao" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    } catch {
        Write-Linha "Falha ao criar: $($_.Exception.Message)" Erro
    } finally {
        if ($null -eq $freqAntiga) {
            Remove-ItemProperty -LiteralPath $chave -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue
        } else {
            New-ItemProperty -LiteralPath $chave -Name SystemRestorePointCreationFrequency -Value $freqAntiga -PropertyType DWord -Force | Out-Null
        }
    }
    $depois = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object SequenceNumber | Select-Object -Last 1
    if ($depois -and (-not $antes -or $depois.SequenceNumber -gt $antes.SequenceNumber)) {
        Write-Linha "Ponto de restauração criado: '$($depois.Description)'" Feito
        return $true
    }
    Write-Linha 'NÃO consegui confirmar o ponto de restauração.' Erro
    if ($Script:SemPerguntas) { return $false }
    $r = Read-Host 'Continuar mesmo assim? (o "Desfazer tudo" continua funcionando) Digite SIM para continuar'
    return ($r.Trim() -eq 'SIM')
}

# ---- 4.2 Registro ----
function Set-Reg {
    param(
        [Parameter(Mandatory)][string]$Caminho,
        [Parameter(Mandatory)][string]$Nome,
        [Parameter(Mandatory)]$Valor,
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'Binary', 'MultiString')][string]$Tipo = 'DWord',
        [string]$Descricao
    )
    if (-not $Descricao) { $Descricao = "$Caminho\$Nome" }
    $chaveExiste = Test-Path -LiteralPath $Caminho
    $existia = $false; $antigo = $null; $tipoAntigo = $null
    if ($chaveExiste) {
        $chave = Get-Item -LiteralPath $Caminho -ErrorAction SilentlyContinue
        if ($chave -and ($chave.GetValueNames() -contains $Nome)) {
            $existia    = $true
            $antigo     = $chave.GetValue($Nome, $null, 'DoNotExpandEnvironmentNames')
            $tipoAntigo = $chave.GetValueKind($Nome).ToString()
        }
    }
    if ($existia -and $tipoAntigo -eq $Tipo -and ((@($antigo) -join ',') -eq (@($Valor) -join ','))) {
        Write-Linha "$Descricao (já estava assim)" Ok
        return
    }
    if ($Script:Simular) {
        $detalhe = ''
        if ($Tipo -ne 'Binary') {
            $de = if ($existia) { @($antigo) -join ',' } else { 'não existia' }
            $detalhe = "   [$($Nome): $de -> $(@($Valor) -join ',')]"
        }
        Write-Linha "$Descricao$detalhe" Sim
        return
    }
    try {
        if (-not $chaveExiste) { New-Item -Path $Caminho -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $Caminho -Name $Nome -Value $Valor -PropertyType $Tipo -Force -ErrorAction Stop | Out-Null
        Add-Journal @{ Tipo = 'Registro'; Caminho = $Caminho; Nome = $Nome; Existia = $existia; TipoAntigo = $tipoAntigo
                       ValorAntigo = (ConvertTo-ValorJournal $antigo $tipoAntigo); ChaveCriada = (-not $chaveExiste) }
        Write-Linha $Descricao Feito
    } catch {
        Write-Linha "$Descricao -> $($_.Exception.Message)" Erro
    }
}

function Restore-Reg {
    param($E)
    $desc = "Registro $($E.Caminho)\$($E.Nome)"
    if ($Script:Simular) { Write-Linha "Voltaria $desc ao valor antigo" Sim; return }
    try {
        if ($E.Existia) {
            if (-not (Test-Path -LiteralPath $E.Caminho)) { New-Item -Path $E.Caminho -Force | Out-Null }
            $valor = ConvertFrom-ValorJournal $E.ValorAntigo $E.TipoAntigo
            New-ItemProperty -LiteralPath $E.Caminho -Name $E.Nome -Value $valor -PropertyType $E.TipoAntigo -Force -ErrorAction Stop | Out-Null
        } elseif (Test-Path -LiteralPath $E.Caminho) {
            # o valor não existia antes: apaga (e apaga a chave, se fomos nós que criamos e ficou vazia)
            Remove-ItemProperty -LiteralPath $E.Caminho -Name $E.Nome -ErrorAction SilentlyContinue
            if ($E.ChaveCriada) {
                $k = Get-Item -LiteralPath $E.Caminho -ErrorAction SilentlyContinue
                if ($k -and $k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0) { Remove-Item -LiteralPath $E.Caminho -ErrorAction SilentlyContinue }
            }
        }
        Write-Linha "Restaurado: $desc" Feito
    } catch {
        Write-Linha "$desc -> $($_.Exception.Message)" Erro
    }
}

# ---- 4.3 Serviços ----
function Set-ServicoInicio {
    param([string]$Nome, [ValidateSet('Manual', 'Desativado')][string]$Tipo, [string]$Descricao)
    if ($ServicosProtegidos -contains $Nome) { Write-Linha "Serviço $Nome está na lista de protegidos; não mexo." Aviso; return }
    $svc = Get-Service -Name $Nome -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Linha "Serviço $Nome não existe neste PC (pulando)" Ok; return }
    $reg           = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$Nome" -ErrorAction SilentlyContinue
    $startAntigo   = [int]$reg.Start              # 2 = Automático, 3 = Manual, 4 = Desativado
    $delayedAntigo = [int]$reg.DelayedAutostart   # 1 = Automático (atraso)
    $startNovo     = if ($Tipo -eq 'Manual') { 3 } else { 4 }
    $nomes         = @{ 2 = 'Automático'; 3 = 'Manual'; 4 = 'Desativado' }
    if ($startAntigo -ge $startNovo) { Write-Linha "Serviço $Nome já está $($nomes[$startAntigo])" Ok; return }
    $descr = "Serviço $Nome - $Descricao : $($nomes[$startAntigo]) -> $Tipo"
    if ($Script:Simular) { Write-Linha $descr Sim; return }
    $arg   = if ($Tipo -eq 'Manual') { 'demand' } else { 'disabled' }
    $saida = & sc.exe config $Nome start= $arg 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Linha "$descr -> sc.exe: $saida" Erro; return }
    Add-Journal @{ Tipo = 'Servico'; Nome = $Nome; StartAntigo = $startAntigo; DelayedAntigo = $delayedAntigo }
    if ($Tipo -eq 'Desativado' -and $svc.Status -eq 'Running') { Stop-Service -Name $Nome -Force -ErrorAction SilentlyContinue }
    Write-Linha $descr Feito
}

function Restore-Servico {
    param($E)
    $arg = switch ([int]$E.StartAntigo) {
        2       { if ([int]$E.DelayedAntigo -eq 1) { 'delayed-auto' } else { 'auto' } }
        3       { 'demand' }
        4       { 'disabled' }
        default { $null }
    }
    if (-not $arg) { Write-Linha "Serviço $($E.Nome): tipo antigo desconhecido ($($E.StartAntigo)); pulei." Aviso; return }
    if ($Script:Simular) { Write-Linha "Voltaria o serviço $($E.Nome) para '$arg'" Sim; return }
    & sc.exe config $E.Nome start= $arg | Out-Null
    if ($LASTEXITCODE -eq 0) {
        if ($arg -like '*auto') { Start-Service -Name $E.Nome -ErrorAction SilentlyContinue }
        Write-Linha "Serviço $($E.Nome) voltou para '$arg'" Feito
    } else {
        Write-Linha "Serviço $($E.Nome): sc.exe falhou (código $LASTEXITCODE)" Erro
    }
}

# ---- 4.4 Tarefas agendadas ----
function Get-TodasTarefas {
    if ($null -eq $Script:CacheTarefas) { $Script:CacheTarefas = @(Get-ScheduledTask -ErrorAction SilentlyContinue) }
    $Script:CacheTarefas
}

function Disable-Tarefa {
    param([string]$Pasta, [string]$Nome, [string]$Descricao)
    $achadas = @(Get-TodasTarefas | Where-Object { $_.TaskPath -like $Pasta -and $_.TaskName -like $Nome })
    if ($achadas.Count -eq 0) { Write-Linha "Tarefa $Pasta$Nome não existe neste PC (pulando)" Ok; return }
    foreach ($t in $achadas) {
        $id = "$($t.TaskPath)$($t.TaskName)"
        if ($t.State -eq 'Disabled') { Write-Linha "Tarefa $id já está desativada" Ok; continue }
        if ($Script:Simular) { Write-Linha "Desativar tarefa $id - $Descricao" Sim; continue }
        try {
            Disable-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -ErrorAction Stop | Out-Null
            Add-Journal @{ Tipo = 'Tarefa'; Pasta = $t.TaskPath; Nome = $t.TaskName }
            Write-Linha "Tarefa $id desativada - $Descricao" Feito
        } catch {
            Write-Linha "Tarefa $id -> $($_.Exception.Message)" Erro
        }
    }
}

function Restore-Tarefa {
    param($E)
    if ($Script:Simular) { Write-Linha "Religaria a tarefa $($E.Pasta)$($E.Nome)" Sim; return }
    try {
        Enable-ScheduledTask -TaskPath $E.Pasta -TaskName $E.Nome -ErrorAction Stop | Out-Null
        Write-Linha "Tarefa $($E.Pasta)$($E.Nome) religada" Feito
    } catch {
        Write-Linha "Tarefa $($E.Pasta)$($E.Nome) -> $($_.Exception.Message)" Erro
    }
}

# ---- 4.5 Inicialização ----
# O Windows guarda "ligado/desligado" de cada item em StartupApproved (o mesmo que o Gerenciador
# de Tarefas usa): primeiro byte par = ligado, ímpar = desligado. A entrada original não é apagada.
$FontesInicializacao = @(
    @{ Tipo = 'Run';   Origem = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Aprovacao = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
    @{ Tipo = 'Run';   Origem = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             Aprovacao = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
    @{ Tipo = 'Run';   Origem = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Aprovacao = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' }
    @{ Tipo = 'Pasta'; Origem = [Environment]::GetFolderPath('Startup');                           Aprovacao = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
    @{ Tipo = 'Pasta'; Origem = [Environment]::GetFolderPath('CommonStartup');                     Aprovacao = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
)

function Get-ItensInicializacao {
    foreach ($f in $FontesInicializacao) {
        if (-not $f.Origem -or -not (Test-Path -LiteralPath $f.Origem)) { continue }
        if ($f.Tipo -eq 'Run') {
            $nomes = (Get-Item -LiteralPath $f.Origem).GetValueNames() | Where-Object { $_ }
        } else {
            $nomes = Get-ChildItem -LiteralPath $f.Origem -File -Force -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -ne 'desktop.ini' } | ForEach-Object { $_.Name }
        }
        $aprov = Get-Item -LiteralPath $f.Aprovacao -ErrorAction SilentlyContinue
        foreach ($n in $nomes) {
            $desligado = $false
            if ($aprov -and ($aprov.GetValueNames() -contains $n)) {
                $bytes = [byte[]]$aprov.GetValue($n)
                $desligado = ($null -ne $bytes -and $bytes.Length -gt 0 -and ($bytes[0] -band 1) -eq 1)
            }
            [pscustomobject]@{ Nome = $n; Aprovacao = $f.Aprovacao; Desligado = $desligado }
        }
    }
}

function Disable-Inicializacao {
    param([string]$Padrao, [string]$Descricao)
    $itens = @(Get-ItensInicializacao | Where-Object { $_.Nome -like $Padrao })
    if ($itens.Count -eq 0) { Write-Linha "Inicialização: '$Padrao' não encontrado (pulando)" Ok; return }
    foreach ($i in $itens) {
        if (Test-Coringa $i.Nome $InicializacaoProtegida) { Write-Linha "Inicialização: $($i.Nome) é protegido; não mexo." Aviso; continue }
        if ($i.Desligado) { Write-Linha "Inicialização: $($i.Nome) já está desligado" Ok; continue }
        # 03 00 00 00 + data/hora = "desabilitado pelo usuário" (formato do Gerenciador de Tarefas)
        $valor = [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes([long](Get-Date).ToFileTimeUtc()))
        Set-Reg -Caminho $i.Aprovacao -Nome $i.Nome -Valor $valor -Tipo Binary -Descricao "Inicialização: desligar $($i.Nome) - $Descricao"
    }
}

# ---- 4.6 Apps (Appx) ----
function Get-ProvisionadosCache {
    if ($null -eq $Script:CacheProvisionados) { $Script:CacheProvisionados = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue) }
    $Script:CacheProvisionados
}

function Remove-AppBloat {
    param([string]$Nome, [string]$Descricao, [switch]$Desprovisionar)
    if (Test-Coringa $Nome $AppsProtegidos) { Write-Linha "App $Nome é protegido (Store/Defender/jogos/codecs); não removo." Aviso; return }
    $pacotes = @(Get-AppxPackage -Name $Nome -ErrorAction SilentlyContinue)
    if ($pacotes.Count -eq 0) { Write-Linha "App $Nome não está instalado (pulando)" Ok }
    foreach ($p in $pacotes) {
        $Script:AppsRemovidos += $p.Name
        if ($Script:Simular) { Write-Linha "Remover app $($p.Name) - $Descricao" Sim; continue }
        try {
            Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop
            Add-Journal @{ Tipo = 'App'; Nome = $p.Name; Familia = $p.PackageFamilyName; Pacote = $p.PackageFullName; Local = $p.InstallLocation }
            Write-Linha "App removido: $($p.Name) - $Descricao" Feito
        } catch {
            Write-Linha "App $($p.Name) -> $($_.Exception.Message)" Erro
        }
    }
    # Agressivo: também tira a "cópia de instalação" que o Windows usa para novos usuários e grandes
    # atualizações. Assim o app não volta sozinho, mas para reaver só pela Microsoft Store.
    if ($Desprovisionar) {
        foreach ($pp in @(Get-ProvisionadosCache | Where-Object { $_.DisplayName -eq $Nome })) {
            if ($Script:Simular) { Write-Linha "Desprovisionar $Nome (não volta em novos usuários/atualizações)" Sim; continue }
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null
                Add-Journal @{ Tipo = 'AppProvisionado'; Nome = $Nome; Pacote = $pp.PackageName }
                Write-Linha "Desprovisionado: $Nome" Feito
            } catch {
                Write-Linha "Desprovisionar $Nome -> $($_.Exception.Message)" Erro
            }
        }
    }
}

# Tenta reinstalar a partir dos arquivos que ainda estão no PC; se não der, o app vai para a lista da Store.
function Restore-App {
    param($E)
    if ($Script:Simular) { Write-Linha "Reinstalaria o app $($E.Nome)" Sim; return $true }
    if (Get-AppxPackage -Name $E.Nome -ErrorAction SilentlyContinue) { Write-Linha "App $($E.Nome) já está instalado" Ok; return $true }
    $manifestos = @()
    if ($E.Local) { $manifestos += Join-Path $E.Local 'AppxManifest.xml' }
    $manifestos += Get-AppxPackage -AllUsers -Name $E.Nome -ErrorAction SilentlyContinue |
                   Where-Object { $_.InstallLocation } | ForEach-Object { Join-Path $_.InstallLocation 'AppxManifest.xml' }
    $manifestos += Get-ProvisionadosCache | Where-Object { $_.DisplayName -eq $E.Nome -and $_.InstallLocation } |
                   ForEach-Object { [Environment]::ExpandEnvironmentVariables($_.InstallLocation) }
    foreach ($m in ($manifestos | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)) {
        try {
            Add-AppxPackage -DisableDevelopmentMode -Register $m -ErrorAction Stop
            Write-Linha "App reinstalado: $($E.Nome)" Feito
            return $true
        } catch { }
    }
    Write-Linha "Não consegui reinstalar $($E.Nome) com os arquivos locais; vai precisar da Microsoft Store." Aviso
    return $false
}

function Disable-SegundoPlano {
    param([string]$NomePacote)
    $p = Get-AppxPackage -Name $NomePacote -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { return }   # não instalado: nada a fazer
    # Mesmo efeito de Configurações > Apps > (app) > Opções avançadas > Permissões em segundo plano: Nunca
    $base = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\$($p.PackageFamilyName)"
    Set-Reg -Caminho $base -Nome 'Disabled'       -Valor 1 -Descricao "Segundo plano: bloquear $($p.Name)"
    Set-Reg -Caminho $base -Nome 'DisabledByUser' -Valor 1 -Descricao "Segundo plano: bloquear $($p.Name) (marca de 'escolha do usuário')"
}

# ---- 4.7 Plano de energia ----
function Get-PlanosEnergia {
    powercfg /list | ForEach-Object {
        if ($_ -match "($GuidRegex)\s+\((.+?)\)(\s*\*)?") {
            [pscustomobject]@{ Guid = $Matches[1].ToLower(); Nome = $Matches[2]; Ativo = [bool]$Matches[3] }
        }
    }
}

function Get-PlanoAtivo {
    $s = powercfg /getactivescheme | Out-String
    if ($s -match "($GuidRegex)\s+\((.+?)\)") { [pscustomobject]@{ Guid = $Matches[1].ToLower(); Nome = $Matches[2] } }
}

# Cria uma CÓPIA do plano base com 3 ajustes e ativa a cópia. Os planos originais do Windows não são editados,
# então desfazer é só voltar a ativar o plano antigo.
function Set-PlanoEnergia {
    param([int]$N)
    # Para Ryzen, a própria AMD recomenda o "Equilibrado" do Windows: o ganho real vem dos 3 ajustes abaixo.
    # No Médio entra o Alto desempenho (clock mínimo mais alto); no Agressivo, o Desempenho Máximo
    # (CPU nunca baixa o clock: alguns watts a mais em idle, sem ganho grande de FPS).
    $bases = @{
        1 = @{ Guid = '381b4222-f694-41f0-9685-ff5bb260df2e'; Nome = 'Equilibrado' }
        2 = @{ Guid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'; Nome = 'Alto desempenho' }
        3 = @{ Guid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'; Nome = 'Desempenho Maximo' }
    }
    $alvo      = $bases[$N]
    $nomePlano = 'Desbostificar - ' + ($NomesNivel[$N] -replace 'é', 'e')   # sem acento: o powercfg usa outra codificação
    Write-Linha 'Plano de energia' Titulo
    $ativo = Get-PlanoAtivo
    if ($ativo -and $ativo.Nome -eq $nomePlano) { Write-Linha "Plano '$nomePlano' já está ativo" Ok; return }
    $descr = "Plano de energia: '$($ativo.Nome)' -> '$nomePlano' (base $($alvo.Nome) + USB sem suspensão + PCIe sem economia + disco nunca desliga)"
    if ($Script:Simular) { Write-Linha $descr Sim; return }

    $novo = [regex]::Match((powercfg /duplicatescheme $alvo.Guid 2>&1 | Out-String), $GuidRegex).Value
    # (se o powercfg falhar e a mensagem repetir o GUID de origem, nunca renomeamos o plano original do Windows)
    if (-not $novo -or $novo -eq $alvo.Guid) {
        Write-Linha "Não consegui copiar o plano '$($alvo.Nome)'; vou usar o Equilibrado como base." Aviso
        $novo = [regex]::Match((powercfg /duplicatescheme 381b4222-f694-41f0-9685-ff5bb260df2e 2>&1 | Out-String), $GuidRegex).Value
        if (-not $novo -or $novo -eq '381b4222-f694-41f0-9685-ff5bb260df2e') { Write-Linha 'powercfg falhou ao criar o plano.' Erro; return }
    }
    $novo = $novo.ToLower()
    powercfg /changename $novo $nomePlano 'Criado pelo Desbostificar. Para voltar: menu Desfazer.' | Out-Null
    # USB: suspensão seletiva DESLIGADA. Evita mouse/teclado/headset Logitech/Corsair "piscando" ou demorando a responder.
    powercfg /setacvalueindex $novo 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null
    # PCI Express: economia de energia do link DESLIGADA. A RTX 3060 não perde tempo "acordando" o barramento.
    powercfg /setacvalueindex $novo 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 | Out-Null
    # Disco: NUNCA desligar. O HD Seagate (E:) guarda o Riot Games; quando ele "dorme" e o jogo
    # pede um arquivo, dá aquela travada de 3 a 8 segundos esperando o disco girar de novo.
    powercfg /setacvalueindex $novo 0012ee47-9041-4b5d-9b77-535fba8b1442 6738e2c4-e8a5-4a42-b16a-e040e769756e 0 | Out-Null
    powercfg /setactive $novo | Out-Null
    Add-Journal @{ Tipo = 'Energia'; GuidAntigo = $ativo.Guid; NomeAntigo = $ativo.Nome; GuidNovo = $novo }
    Write-Linha $descr Feito
    # apaga cópias antigas criadas por este script que ficaram sem uso
    Get-PlanosEnergia | Where-Object { $_.Nome -like 'Desbostificar*' -and $_.Guid -ne $novo } |
        ForEach-Object { powercfg /delete $_.Guid | Out-Null }
}

function Restore-Energia {
    param($E)
    if ($Script:Simular) { Write-Linha "Voltaria o plano de energia para '$($E.NomeAntigo)'" Sim; return }
    if (Get-PlanosEnergia | Where-Object { $_.Guid -eq $E.GuidAntigo }) {
        powercfg /setactive $E.GuidAntigo | Out-Null
        Write-Linha "Plano de energia voltou para '$($E.NomeAntigo)'" Feito
    } else {
        Write-Linha "Plano '$($E.NomeAntigo)' não existe mais (era uma cópia antiga deste script); seguindo." Ok
    }
}

# ---- 4.8 Limpeza ----
# Percorre a pasta SEM entrar em junções/links simbólicos: um atalho de pasta dentro do Temp
# apontando para outro lugar nunca é seguido, então só o conteúdo real da pasta é apagado.
function Get-ItensSemLinks {
    param([string]$Pasta)
    $pilha = New-Object System.Collections.Stack
    $pilha.Push($Pasta)
    while ($pilha.Count -gt 0) {
        $atual = $pilha.Pop()
        foreach ($item in (Get-ChildItem -LiteralPath $atual -Force -ErrorAction SilentlyContinue)) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $item
            if ($item.PSIsContainer) { $pilha.Push($item.FullName) }
        }
    }
}

function Clear-Pasta {
    param([string]$Pasta, [string]$Descricao, [int]$DiasMinimos = 0)
    if ([string]::IsNullOrWhiteSpace($Pasta) -or $Pasta.Length -lt 8 -or -not (Test-Path -LiteralPath $Pasta -PathType Container)) { return }
    $limite   = (Get-Date).AddDays(-$DiasMinimos)
    $itens    = @(Get-ItensSemLinks $Pasta)
    $arquivos = @($itens | Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt $limite })
    if ($arquivos.Count -eq 0) { Write-Linha "Limpeza: $Descricao - nada para apagar" Ok; return }
    $total = [double]($arquivos | Measure-Object -Property Length -Sum).Sum
    if ($Script:Simular) {
        Write-Linha ("Limpeza: apagaria {0} arquivos ({1:N1} MB) de {2}" -f $arquivos.Count, ($total / 1MB), $Descricao) Sim
        $Script:BytesLimpeza += $total
        return
    }
    $apagados = 0; $bytes = 0
    foreach ($a in $arquivos) {
        try { Remove-Item -LiteralPath $a.FullName -Force -ErrorAction Stop; $apagados++; $bytes += $a.Length } catch { }   # em uso = fica
    }
    # pastas que ficaram vazias (das mais fundas para as mais rasas; a pasta principal fica)
    $itens | Where-Object { $_.PSIsContainer } | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
        if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    $Script:BytesLimpeza += $bytes
    Write-Linha ("Limpeza: {0} - {1} de {2} arquivos apagados ({3:N1} MB; os que estavam em uso ficaram)" -f $Descricao, $apagados, $arquivos.Count, ($bytes / 1MB)) Feito
}

# Cache de apps baseados em Chromium: só limpa com o app FECHADO.
function Clear-CacheApp {
    param([string]$Processo, [string]$Nome, [string[]]$Pastas)
    if (Get-Process -Name $Processo -ErrorAction SilentlyContinue) {
        Write-Linha "Limpeza: $Nome está aberto; feche-o (inclusive da bandeja) para limpar o cache. Pulando." Aviso
        return
    }
    foreach ($p in $Pastas) { Clear-Pasta -Pasta $p -Descricao "cache do $Nome" }
}

function Get-PastasPerfisChromium {
    param([string]$UserData)
    if (-not (Test-Path -LiteralPath $UserData)) { return @() }
    Get-ChildItem -LiteralPath $UserData -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' } |
        ForEach-Object { (Join-Path $_.FullName 'Cache\Cache_Data'); (Join-Path $_.FullName 'Code Cache'); (Join-Path $_.FullName 'GPUCache') }
}

function Test-ReinicioPendente {
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
}

# Lixo do Windows Update. Não muda nenhuma configuração nem para o serviço: só apaga downloads
# com mais de 3 dias (os de uma atualização em andamento ficam) e o cache da Otimização de Entrega.
function Clear-LixoWindowsUpdate {
    if (Test-ReinicioPendente) {
        Write-Linha 'Tem atualização esperando reinício: não mexo no cache do Windows Update agora. Reinicie e rode a limpeza de novo.' Aviso
        return
    }
    Clear-Pasta -Pasta (Join-Path $env:windir 'SoftwareDistribution\Download') -Descricao 'downloads antigos do Windows Update' -DiasMinimos 3
    if ($Script:Simular) { Write-Linha 'Limpeza: esvaziaria o cache da Otimização de Entrega (cópias de atualizações já instaladas)' Sim; return }
    try {
        Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
        Write-Linha 'Limpeza: cache da Otimização de Entrega esvaziado' Feito
    } catch {
        Write-Linha "Limpeza: cache da Otimização de Entrega -> $($_.Exception.Message)" Aviso
    }
}

# DISM: apaga versões antigas de componentes substituídas por atualizações (pasta WinSxS).
# /ResetBase (Agressivo) libera mais espaço, mas as atualizações já instaladas NÃO podem mais ser desinstaladas.
function Invoke-LimpezaComponentes {
    param([switch]$ResetBase)
    if (Test-ReinicioPendente) { Write-Linha 'Atualização esperando reinício: pulei a limpeza de componentes (DISM).' Aviso; return }
    $argsDism = @('/Online', '/Cleanup-Image', '/StartComponentCleanup')
    if ($ResetBase) { $argsDism += '/ResetBase' }
    $descr = "Limpeza de componentes antigos do Windows Update: dism $($argsDism -join ' ')"
    if ($Script:Simular) { Write-Linha $descr Sim; return }
    Write-Linha "$descr  (pode levar de 5 a 20 minutos; não feche a janela)"
    & dism.exe @argsDism
    if ($LASTEXITCODE -eq 0) { Write-Linha $descr Feito } else { Write-Linha "$descr -> código $LASTEXITCODE" Erro }
}

function Clear-Lixeira {
    if ($Script:Simular) { Write-Linha 'Perguntaria se pode esvaziar a Lixeira' Sim; return }
    if ($Script:SemPerguntas) { Write-Linha 'Lixeira mantida (execução sem perguntas).' Info; return }
    $r = Read-Host 'Esvaziar a Lixeira também? O que está nela NÃO poderá ser recuperado. (S/N)'
    if ($r -notmatch '^[sS]') { Write-Linha 'Lixeira mantida.'; return }
    try { Clear-RecycleBin -Force -ErrorAction Stop; Write-Linha 'Lixeira esvaziada' Feito }
    catch { Write-Linha 'Lixeira já estava vazia' Ok }
}

# Agressivo: caches de pacotes de programação (o npm/pip/dotnet baixam de novo o que precisarem).
function Clear-CachesDev {
    $itens = @(
        @{ Nome = 'npm';            Cmd = 'npm';    Args = @('cache', 'clean', '--force') }
        @{ Nome = 'pip';            Cmd = 'py';     Args = @('-m', 'pip', 'cache', 'purge') }
        @{ Nome = 'NuGet (só o cache HTTP; pacotes dos projetos ficam)'; Cmd = 'dotnet'; Args = @('nuget', 'locals', 'http-cache', '--clear') }
    )
    foreach ($i in $itens) {
        if (-not (Get-Command $i.Cmd -ErrorAction SilentlyContinue)) { continue }
        $descr = "Limpeza: cache do $($i.Nome) ($($i.Cmd) $($i.Args -join ' '))"
        if ($Script:Simular) { Write-Linha $descr Sim; continue }
        & $i.Cmd @($i.Args) 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Linha $descr Feito } else { Write-Linha "$descr -> código $LASTEXITCODE" Aviso }
    }
}

function Get-LivreSistema {
    [double](Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'").FreeSpace
}
#endregion

#region ======================= 5. ETAPAS =======================
function Invoke-Privacidade {
    param([int]$N)
    Write-Linha 'Telemetria, propagandas, sugestões e jogos' Titulo
    foreach ($t in (Select-PorNivel $TweaksRegistro $N)) {
        $tipo = if ($t.T) { $t.T } else { 'DWord' }
        Set-Reg -Caminho $t.P -Nome $t.K -Valor $t.V -Tipo $tipo -Descricao $t.D
    }
}

function Invoke-Apps {
    param([int]$N)
    Write-Linha 'Apps pré-instalados' Titulo
    foreach ($a in (Select-PorNivel $AppsRemover $N)) {
        Remove-AppBloat -Nome $a.Nome -Descricao $a.D -Desprovisionar:($N -ge 3)
    }
}

function Invoke-SegundoPlano {
    param([int]$N)
    Write-Linha 'Apps em segundo plano' Titulo
    $nomes = @($AppsSemSegundoPlano)
    if ($N -ge 3) {
        $nomes += Get-AppxPackage -ErrorAction SilentlyContinue |
                  Where-Object { -not $_.IsFramework -and "$($_.SignatureKind)" -eq 'Store' -and $_.Publisher -like 'CN=Microsoft Corporation*' } |
                  ForEach-Object { $_.Name }
    }
    foreach ($nome in ($nomes | Sort-Object -Unique)) {
        if (Test-Coringa $nome $SegundoPlanoManter) { continue }
        if ($Script:AppsRemovidos -contains $nome) { continue }   # já foi (ou seria) removido acima
        Disable-SegundoPlano $nome
    }
}

function Invoke-Inicializacao {
    param([int]$N)
    Write-Linha 'Programas que abrem junto com o Windows' Titulo
    foreach ($i in (Select-PorNivel $InicializacaoDesativar $N)) { Disable-Inicializacao -Padrao $i.Padrao -Descricao $i.D }
}

function Invoke-Servicos {
    param([int]$N)
    Write-Linha 'Serviços' Titulo
    foreach ($s in (Select-PorNivel $ServicosAjustar $N)) { Set-ServicoInicio -Nome $s.Nome -Tipo $s.Tipo -Descricao $s.D }
}

function Invoke-Tarefas {
    param([int]$N)
    Write-Linha 'Tarefas agendadas' Titulo
    foreach ($t in (Select-PorNivel $TarefasDesativar $N)) { Disable-Tarefa -Pasta $t.Pasta -Nome $t.Nome -Descricao $t.D }
}

function Invoke-Limpeza {
    param([int]$N)
    Write-Linha 'Limpeza de temporários, caches e lixo do Windows Update' Titulo
    $livreAntes = Get-LivreSistema
    # NÃO limpamos de propósito:
    #  - Prefetch: o Windows usa para abrir programas e o boot mais rápido. Apagar deixa tudo MAIS lento.
    #  - Cache de shaders (NVIDIA DXCache/GLCache, D3DSCache, shadercache da Steam): sem ele os jogos
    #    recompilam shaders e dão travadas nas primeiras partidas.
    #  - Downloads, Área de Trabalho e Documentos: são seus arquivos.
    Clear-Pasta -Pasta ([IO.Path]::GetTempPath())                                       -Descricao 'Temp do usuário (mais de 1 dia)' -DiasMinimos 1
    Clear-Pasta -Pasta (Join-Path $env:windir 'Temp')                                   -Descricao 'Temp do Windows (mais de 1 dia)' -DiasMinimos 1
    Clear-Pasta -Pasta (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive') -Descricao 'relatórios de erro antigos'
    Clear-Pasta -Pasta (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue')   -Descricao 'relatórios de erro na fila'
    Clear-Pasta -Pasta (Join-Path $env:LOCALAPPDATA 'CrashDumps')                       -Descricao 'dumps de programas que travaram'
    Clear-LixoWindowsUpdate

    if ($N -ge 2) {
        Clear-CacheApp -Processo 'chrome'  -Nome 'Google Chrome' -Pastas (Get-PastasPerfisChromium (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'))
        Clear-CacheApp -Processo 'msedge'  -Nome 'Microsoft Edge' -Pastas (Get-PastasPerfisChromium (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'))
        Clear-CacheApp -Processo 'Discord' -Nome 'Discord' -Pastas @(
            (Join-Path $env:APPDATA 'discord\Cache\Cache_Data'), (Join-Path $env:APPDATA 'discord\Code Cache'), (Join-Path $env:APPDATA 'discord\GPUCache'))
        Clear-CacheApp -Processo 'steam'   -Nome 'Steam (navegador interno)' -Pastas @((Join-Path $env:LOCALAPPDATA 'Steam\htmlcache'))
        Invoke-LimpezaComponentes -ResetBase:($N -ge 3)
        Clear-Lixeira
    }
    if ($N -ge 3) { Clear-CachesDev }

    if ($Script:Simular) {
        Write-Linha ('Total que seria liberado (estimativa, sem contar o DISM): {0:N2} GB' -f ($Script:BytesLimpeza / 1GB))
    } else {
        Write-Linha ('Espaço livre no {0} antes: {1:N1} GB | agora: {2:N1} GB' -f $env:SystemDrive, ($livreAntes / 1GB), ((Get-LivreSistema) / 1GB)) Info
    }
}
#endregion

#region ======================= 6. MENU: AÇÕES =======================
function Show-Avisos {
    param([int]$N)
    Write-Linha 'Antes de continuar, saiba que' Titulo
    Write-Linha 'Nada é desinstalado da inicialização: só desligado (dá para religar no Gerenciador de Tarefas).'
    if ($N -ge 2) {
        Write-Linha 'Steam, Discord, Notion e Teams deixam de abrir sozinhos no boot.' Aviso
        Write-Linha 'A pesquisa do Iniciar passa a mostrar só o que está no PC (sem Bing).' Aviso
        Write-Linha 'O ditado por voz online (Win+H) é desligado.' Aviso
        Write-Linha 'O Edge vai mostrar "gerenciado pela sua organização" (são as políticas de não rodar escondido).' Aviso
    }
    if ($N -ge 3) {
        Write-Linha 'Apps removidos também saem da imagem do Windows: só voltam pela Microsoft Store.' Aviso
        Write-Linha 'DISM /ResetBase: atualizações já instaladas não poderão ser desinstaladas.' Aviso
        Write-Linha 'Plano Desempenho Máximo: CPU sempre no clock alto (mais consumo e calor em idle).' Aviso
        Write-Linha 'Todos os apps da Microsoft perdem o segundo plano (Alarmes, Celular, Xbox e Store ficam de fora).' Aviso
    }
}

function Show-ResumoFinal {
    Write-Linha 'Resumo' Titulo
    $s = $Script:Stats
    if ($Script:Simular) {
        Write-Linha "Itens que seriam alterados: $($s.Simulados) | já estavam ok: $($s.JaOk) | erros: $($s.Erros)"
        Write-Linha 'NADA foi alterado. Para aplicar, tecle S no menu e escolha o nível de novo.' Aviso
    } else {
        Write-Linha "Alterados: $($s.Feitos) | já estavam ok: $($s.JaOk) | erros: $($s.Erros)"
        Write-Linha "Registro para desfazer: $ArquivoJournal"
    }
    Write-Linha "Log desta execução: $Script:ArquivoLog"
    if (-not $Script:Simular -and $s.Feitos -gt 0) {
        Write-Linha 'Reinicie o PC para todas as mudanças valerem.' Aviso
        if (-not $Script:SemPerguntas) {
            $r = Read-Host 'Reiniciar agora? (S/N)'
            if ($r -match '^[sS]') { Restart-Computer -Force }
        }
    }
}

function Invoke-Nivel {
    param([int]$N)
    $nome = $NomesNivel[$N]
    Start-Execucao ($nome -replace 'é', 'e')
    Show-Avisos $N
    if (-not (Confirm-Acao "Vai aplicar o nível $nome de verdade.")) { Write-Linha 'Cancelado.' Aviso; return }
    if (-not (New-PontoRestauracao "antes do nível $nome")) { Write-Linha 'Cancelado: sem ponto de restauração.' Aviso; return }
    Invoke-Privacidade   $N
    Invoke-Apps          $N
    Invoke-SegundoPlano  $N
    Invoke-Inicializacao $N
    Invoke-Servicos      $N
    Invoke-Tarefas       $N
    Set-PlanoEnergia     $N
    Invoke-Limpeza       $N
    Show-ResumoFinal
}

function Invoke-SoLimpeza {
    Start-Execucao 'Limpeza'
    if (-not (Confirm-Acao 'Vai limpar temporários, caches e lixo do Windows Update (nível Médio de limpeza).')) { Write-Linha 'Cancelado.' Aviso; return }
    if (-not (New-PontoRestauracao 'antes da limpeza')) { Write-Linha 'Cancelado: sem ponto de restauração.' Aviso; return }
    Invoke-Limpeza 2
    Show-ResumoFinal
}

function Invoke-Desfazer {
    Start-Execucao 'Desfazer'
    Write-Linha 'Desfazer tudo' Titulo
    if (-not (Test-Path -LiteralPath $ArquivoJournal)) { Write-Linha 'Não há alterações registradas para desfazer.' Aviso; return }
    $entradas = New-Object System.Collections.ArrayList
    foreach ($linha in [IO.File]::ReadAllLines($ArquivoJournal, $Script:Utf8)) {
        if ([string]::IsNullOrWhiteSpace($linha)) { continue }
        try { [void]$entradas.Add(($linha | ConvertFrom-Json)) } catch { Write-Linha 'Linha inválida no registro de alterações (ignorada).' Aviso }
    }
    $entradas.Reverse()   # da mais nova para a mais antiga: cada valor volta exatamente ao que era antes
    Write-Linha "Alterações registradas: $($entradas.Count)"
    $entradas | Group-Object Tipo | ForEach-Object { Write-Linha "   $($_.Name): $($_.Count)" }
    Write-Linha 'Limpeza de arquivos não tem volta (eram temporários) e não aparece aqui.'
    if (-not (Confirm-Acao 'Vai desfazer TODAS as alterações acima.')) { Write-Linha 'Cancelado.' Aviso; return }
    if (-not (New-PontoRestauracao 'antes de desfazer')) { Write-Linha 'Cancelado: sem ponto de restauração.' Aviso; return }

    $appsStore = @()
    foreach ($e in $entradas) {
        switch ($e.Tipo) {
            'Registro'        { Restore-Reg $e }
            'Servico'         { Restore-Servico $e }
            'Tarefa'          { Restore-Tarefa $e }
            'Energia'         { Restore-Energia $e }
            'App'             { if (-not (Restore-App $e)) { $appsStore += $e } }
            'AppProvisionado' { Write-Linha "$($e.Nome) foi desprovisionado no Agressivo: para tê-lo de novo, instale pela Microsoft Store." Aviso }
        }
    }
    if (-not $Script:Simular) {
        # garante que nenhuma cópia de plano de energia do script fique ativa ou sobrando
        $ativo = Get-PlanoAtivo
        if ($ativo -and $ativo.Nome -like 'Desbostificar*') { powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e | Out-Null }
        Get-PlanosEnergia | Where-Object { $_.Nome -like 'Desbostificar*' -and -not $_.Ativo } | ForEach-Object { powercfg /delete $_.Guid | Out-Null }
        # o registro já foi usado: arquiva para um próximo "Desfazer" não repetir o processo
        Move-Item -LiteralPath $ArquivoJournal -Destination (Join-Path $PastaDados "desfeito_$($Script:IdExecucao).jsonl") -Force
    }
    if ($appsStore.Count -gt 0) {
        Write-Linha 'Apps que precisam ser reinstalados pela Microsoft Store:' Aviso
        foreach ($a in $appsStore) { Write-Linha "   $($a.Nome)  ->  ms-windows-store://pdp/?PFN=$($a.Familia)" Aviso }
        if (-not $Script:SemPerguntas -and (Read-Host 'Abrir a Store em cada um deles agora? (S/N)') -match '^[sS]') {
            foreach ($a in $appsStore) { Start-Process "ms-windows-store://pdp/?PFN=$($a.Familia)"; Start-Sleep -Seconds 2 }
        }
    }
    Write-Linha 'Se ainda algo ficar estranho, há também a Restauração do Sistema: Win+R > rstrui > escolha um ponto "Desbostificar".'
    Show-ResumoFinal
}

function Get-TipoDisco {
    param([string]$Unidade)   # ex.: 'E:'
    try {
        $num = (Get-Partition -DriveLetter $Unidade.TrimEnd(':') -ErrorAction Stop).DiskNumber
        $tipo = "$((Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq "$num" }).MediaType)"
        if ($tipo) { return $tipo }
    } catch { }
    return 'disco'
}

# Relatório só de leitura: discos, inicialização, plano de energia e pontos de atenção.
function Show-Relatorio {
    Start-Execucao 'Relatorio'
    Write-Linha 'Discos' Titulo
    $discos = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Sort-Object DeviceID |
                ForEach-Object { $_ | Add-Member -NotePropertyName Tipo -NotePropertyValue (Get-TipoDisco $_.DeviceID) -PassThru })
    foreach ($d in $discos) {
        Write-Linha ('{0} [{1}] {2,7:N1} GB livres de {3,7:N1} GB ({4:P0} usado)' -f $d.DeviceID, $d.Tipo, ($d.FreeSpace / 1GB), ($d.Size / 1GB), (1 - $d.FreeSpace / $d.Size))
    }
    $c        = $discos | Where-Object { $_.DeviceID -eq $env:SystemDrive }
    $ssdLivre = $discos | Where-Object { $_.DeviceID -ne $env:SystemDrive -and $_.Tipo -eq 'SSD' } | Sort-Object FreeSpace -Descending | Select-Object -First 1
    $destino  = if ($ssdLivre) { "o SSD $($ssdLivre.DeviceID) ($('{0:N0}' -f ($ssdLivre.FreeSpace / 1GB)) GB livres)" } else { 'outro disco' }
    if ($c -and ($c.FreeSpace / $c.Size) -lt 0.2) {
        Write-Linha ('O {0} está com mais de 80% de uso. SSD cheio grava mais devagar (o cache rápido dele encolhe).' -f $env:SystemDrive) Aviso
        Write-Linha "Mova bibliotecas de jogos para $destino (Steam > Configurações > Armazenamento > Mover; Epic/EA/Ubisoft também têm 'mover')." Aviso
    }
    foreach ($d in ($discos | Where-Object { $_.Tipo -eq 'HDD' })) {
        if (Test-Path -LiteralPath "$($d.DeviceID)\Riot Games") {
            Write-Linha "Riot Games (Valorant/LoL) está no HD $($d.DeviceID). Reinstalar em $destino deixa o carregamento bem mais rápido." Aviso
        }
    }

    Write-Linha 'Inicialização' Titulo
    Get-ItensInicializacao | Sort-Object Nome | ForEach-Object {
        Write-Linha ('  [{0}] {1}' -f $(if ($_.Desligado) { 'desligado' } else { 'LIGADO   ' }), $_.Nome)
    }

    Write-Linha 'Plano de energia' Titulo
    $p = Get-PlanoAtivo
    Write-Linha "Ativo: $($p.Nome) ($($p.Guid))"

    Write-Linha 'Pontos de atenção' Titulo
    $tarefa = Get-ScheduledTask -TaskPath '\' -TaskName 'Inicializar' -ErrorAction SilentlyContinue
    if ($tarefa) {
        foreach ($a in $tarefa.Actions) {
            Write-Linha "Tarefa agendada 'Inicializar' (sem fabricante identificado) executa: $($a.Execute) $($a.Arguments)" Aviso
        }
        Write-Linha 'Se não foi você que criou, vale passar o Defender: Segurança do Windows > Proteção contra vírus > Opções de verificação > Verificação offline.' Aviso
    }
    $overlays = @('RTSS', 'MSIAfterburner', 'NVIDIA Overlay', 'iCUE', 'lghub') | Where-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue }
    if ($overlays.Count -ge 3) { Write-Linha "Vários programas de overlay/monitoramento abertos juntos ($($overlays -join ', ')). Se houver travadas em jogo, teste com só um." Aviso }

    if (Test-Path -LiteralPath $ArquivoJournal) {
        $qtd = @([IO.File]::ReadAllLines($ArquivoJournal) | Where-Object { $_ }).Count
        Write-Linha "Alterações registradas e reversíveis pelo Desfazer: $qtd"
    } else {
        Write-Linha 'Nenhuma alteração do Desbostificar registrada ainda.'
    }
    Write-Linha "Relatório salvo em: $Script:ArquivoLog"
}
#endregion

#region ======================= 7. INÍCIO =======================
function Initialize-Contexto {
    $cpu = "$((Get-CimInstance Win32_Processor | Select-Object -First 1).Name)".Trim()
    $gpu = "$((Get-CimInstance Win32_VideoController | Where-Object { $_.Name -like '*NVIDIA*' } | Select-Object -First 1).Name)"
    $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    $Script:ResumoPC = "$cpu | $gpu | $ram GB"
    $Script:AvisosIniciais = @()
    if ($cpu -notlike '*Ryzen 5 5500*') {
        $Script:AvisosIniciais += "Este script foi montado para Ryzen 5 5500 + RTX 3060. Aqui tem: $cpu. Revise a CONFIGURAÇÃO antes de aplicar."
    }
    # Se o administrador que abriu o script não for o usuário logado, ajustes de usuário iriam para a conta errada.
    try {
        $explorer = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop | Select-Object -First 1
        if ($explorer) {
            $dono = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner -ErrorAction Stop
            if ($dono.User -and $dono.User -ne $env:USERNAME) {
                $Script:AvisosIniciais += "O Windows está logado como '$($dono.User)', mas o script roda como '$env:USERNAME'. Ajustes de usuário e remoção de apps iriam para a conta errada; rode a partir da conta '$($dono.User)' (ela precisa ser administradora)."
            }
        }
    } catch { }
}

function Show-Menu {
    Clear-Host
    Write-Host '==================================================================' -ForegroundColor DarkCyan
    Write-Host '   DESBOSTIFICAR - otimização sob medida' -ForegroundColor White
    Write-Host "   $Script:ResumoPC" -ForegroundColor DarkGray
    Write-Host '==================================================================' -ForegroundColor DarkCyan
    foreach ($a in $Script:AvisosIniciais) { Write-Host "   AVISO: $a" -ForegroundColor Yellow }
    if ($Script:Simular) {
        Write-Host '   Modo: SIMULAÇÃO  (só mostra o que faria; NADA é alterado)' -ForegroundColor Cyan
    } else {
        Write-Host '   Modo: APLICAR    (as alterações serão feitas de verdade)' -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host '   1) Leve       seguro: telemetria, propagandas, apps-lixo, launchers fora do boot, limpeza'
    Write-Host '   2) Médio      Leve + Steam/Discord fora do boot, serviços, tarefas, caches, DISM'
    Write-Host '   3) Agressivo  Médio + Desempenho Máximo, desprovisionar apps, ResetBase (leia os avisos)'
    Write-Host '   4) Só limpeza (temporários, caches, lixo do Windows Update)'
    Write-Host '   5) Desfazer tudo'
    Write-Host '   6) Relatório do PC (só leitura)'
    Write-Host '   L) Abrir a pasta de logs'
    Write-Host '   S) Alternar SIMULAÇÃO / APLICAR'
    Write-Host '   0) Sair'
    Write-Host ''
}

Initialize-Contexto
if (-not (Test-Path -LiteralPath $PastaDados)) { New-Item -ItemType Directory -Path $PastaDados -Force | Out-Null }

if ($Nivel) {
    # modo direto (sem menu): -Nivel X [-Aplicar]
    switch ($Nivel) {
        'Leve'      { Invoke-Nivel 1 }
        'Medio'     { Invoke-Nivel 2 }
        'Agressivo' { Invoke-Nivel 3 }
        'Limpeza'   { Invoke-SoLimpeza }
        'Desfazer'  { Invoke-Desfazer }
        'Relatorio' { Show-Relatorio }
    }
    Read-Host 'Enter para fechar' | Out-Null
    exit
}

$sair = $false
while (-not $sair) {
    Show-Menu
    $op = "$(Read-Host '   Escolha')".Trim().ToUpper()
    $pausar = $true
    switch ($op) {
        '1' { Invoke-Nivel 1 }
        '2' { Invoke-Nivel 2 }
        '3' { Invoke-Nivel 3 }
        '4' { Invoke-SoLimpeza }
        '5' { Invoke-Desfazer }
        '6' { Show-Relatorio }
        'L' { Start-Process explorer.exe $PastaDados; $pausar = $false }
        'S' { $Script:Simular = -not $Script:Simular; $pausar = $false }
        '0' { $sair = $true; $pausar = $false }
        default { $pausar = $false }
    }
    if ($pausar) { Read-Host "`nEnter para voltar ao menu" | Out-Null }
}
#endregion

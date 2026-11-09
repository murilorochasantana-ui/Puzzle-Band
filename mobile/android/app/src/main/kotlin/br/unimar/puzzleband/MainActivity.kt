package br.unimar.puzzleband

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Canal "br.unimar.puzzleband/sistema" (lib/services/sistema_android.dart):
// abre EXATAMENTE as janelas do sistema da tela "Configurar alertas" e
// responde o que o Dart nao consegue ler sozinho (fabricante, isencao de
// bateria).
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "br.unimar.puzzleband/sistema")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "fabricante" -> result.success(Build.MANUFACTURER ?: "")
                    "semRestricaoDeBateria" -> {
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    // Janela do sistema "Permitir que o app rode sempre em segundo
                    // plano?" (precisa de REQUEST_IGNORE_BATTERY_OPTIMIZATIONS no
                    // manifesto; o app e distribuido por APK, ver docs/app.md)
                    "pedirSemRestricaoDeBateria" -> result.success(
                        abrir(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, pacote()))
                            || abrir(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    )
                    // Detalhes do app (Samsung: Bateria -> retirar de "Apps em suspensao")
                    "abrirDetalhesDoApp" -> result.success(
                        abrir(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pacote()))
                    )
                    // Notificacoes do app (quando o Android nao mostra mais a janela
                    // de permissao, depois de duas recusas)
                    "abrirAjustesDeNotificacao" -> result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            abrir(
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            )
                        } else {
                            abrir(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pacote()))
                        }
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun pacote(): Uri = Uri.parse("package:$packageName")

    private fun abrir(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        false
    } catch (e: SecurityException) {
        false
    }
}

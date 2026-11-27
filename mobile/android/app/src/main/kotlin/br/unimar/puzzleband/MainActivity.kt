package br.unimar.puzzleband

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.DocumentsContract
import android.provider.Settings
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

// Canal "br.unimar.puzzleband/sistema" (lib/services/sistema_android.dart e
// lib/services/documentos_android.dart): abre EXATAMENTE as janelas do
// sistema da tela "Configurar alertas", responde o que o Dart nao consegue
// ler sozinho (fabricante, isencao de bateria) e, no relatorio em Excel, a
// janela "Salvar como" do sistema (Storage Access Framework, sem permissao
// de armazenamento) e o "Abrir" do arquivo salvo.
class MainActivity : FlutterActivity() {
    private val principal = Handler(Looper.getMainLooper())

    // "Salvar como" aberto: a resposta ao Dart e o arquivo a copiar. So um
    // por vez (um segundo pedido recebe erro; o primeiro continua).
    private var salvarPendente: MethodChannel.Result? = null
    private var arquivoPendente: String? = null

    // Arquivo de um "Salvar como" aberto por uma instancia anterior desta
    // Activity (recriada com a janela aberta): o resultado chega aqui, sem
    // ninguem no Dart esperando por ele.
    private var arquivoRestaurado: String? = null

    // O resultado chega antes do onResume, e o Android descarta um aviso
    // (Toast) de um app que ainda nao esta na frente: o "Relatorio salvo"
    // dessa situacao espera a Activity voltar.
    private var naFrente = false
    private var avisoDeSalvoPendente = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        arquivoRestaurado = savedInstanceState?.getString(CHAVE_ARQUIVO)
    }

    override fun onResume() {
        super.onResume()
        naFrente = true
        if (avisoDeSalvoPendente) {
            avisoDeSalvoPendente = false
            avisarSalvo()
        }
    }

    override fun onPause() {
        naFrente = false
        super.onPause()
    }

    private fun avisarSalvo() {
        // um instante depois: a janela do app ja esta visivel
        principal.postDelayed({ Toast.makeText(applicationContext, "Relatório salvo", Toast.LENGTH_LONG).show() }, 500)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        arquivoPendente?.let { outState.putString(CHAVE_ARQUIVO, it) }
    }

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
                    // Acesso ao "Nao perturbe" (passo opcional): para os canais de
                    // alerta ignorarem o modo (ACCESS_NOTIFICATION_POLICY no manifesto)
                    "abrirAcessoNaoPerturbe" -> result.success(
                        abrir(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
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
                    // Relatorio em Excel: "Salvar como" e "Abrir"
                    "salvarDocumento" -> salvarDocumento(call, result)
                    "abrirDocumento" -> result.success(abrirDocumento(call))
                    else -> result.notImplemented()
                }
            }
    }

    // -----------------------------------------------------------------------
    // Relatorio em Excel
    // -----------------------------------------------------------------------

    /// ACTION_CREATE_DOCUMENT com o nome preenchido e a pasta Download
    /// sugerida (Android 8+, quando o sistema aceita a sugestao). A resposta
    /// vem em onActivityResult: a URI escolhida ou null (cancelou).
    private fun salvarDocumento(call: MethodCall, result: MethodChannel.Result) {
        if (salvarPendente != null) {
            result.error("ocupado", "Ja ha um \"Salvar como\" aberto.", null)
            return
        }
        val caminho = call.argument<String>("caminho")
        val nome = call.argument<String>("nome")
        val tipo = call.argument<String>("tipo")
        if (caminho == null || nome == null || tipo == null) {
            result.error("argumentos", "caminho, nome e tipo sao obrigatorios.", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(tipo)
            .putExtra(Intent.EXTRA_TITLE, nome)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intent.putExtra(
                DocumentsContract.EXTRA_INITIAL_URI,
                DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", "primary:Download"),
            )
        }
        salvarPendente = result
        arquivoPendente = caminho
        try {
            startActivityForResult(intent, PEDIDO_SALVAR)
        } catch (e: ActivityNotFoundException) {
            salvarPendente = null
            arquivoPendente = null
            result.error("sem_janela", "O celular nao tem a janela \"Salvar como\".", null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PEDIDO_SALVAR) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val resposta = salvarPendente
        val caminho = arquivoPendente ?: arquivoRestaurado
        salvarPendente = null
        arquivoPendente = null
        arquivoRestaurado = null
        val destino = data?.data
        if (resultCode != Activity.RESULT_OK || destino == null) {
            responder(resposta) { it.success(null) } // cancelou: o Dart nao mostra nada
            return
        }
        // Copia fora da thread principal; a resposta ao Dart volta nela.
        Thread {
            val erro = copiar(caminho, destino)
            principal.post {
                if (resposta != null) {
                    responder(resposta) {
                        if (erro == null) it.success(destino.toString()) else it.error("copia", erro, null)
                    }
                } else if (erro == null) {
                    // A Activity foi recriada com a janela aberta: o Dart que pediu
                    // nao existe mais, mas o tutor escolheu a pasta. O arquivo foi
                    // salvo; avisa aqui.
                    if (naFrente) avisarSalvo() else avisoDeSalvoPendente = true
                } else {
                    // Sem o arquivo de origem: nao deixa um documento vazio para tras.
                    apagarDocumento(destino)
                }
            }
        }.start()
    }

    /// Activity indo embora com o "Salvar como" aberto (recriada, sem memoria):
    /// responde agora como "cancelado" para nenhuma chamada ficar sem resposta.
    /// O caminho do arquivo fica no estado salvo (onSaveInstanceState).
    override fun onDestroy() {
        val resposta = salvarPendente
        salvarPendente = null
        responder(resposta) { it.success(null) }
        super.onDestroy()
    }

    /// null = copiou; senao, o motivo (para o Dart mostrar o erro).
    private fun copiar(caminho: String?, destino: Uri): String? {
        if (caminho == null) return "Arquivo do relatorio desconhecido."
        val origem = File(caminho)
        if (!origem.isFile) return "O arquivo do relatorio nao existe mais."
        return try {
            val saida = contentResolver.openOutputStream(destino, "wt") ?: return "Nao foi possivel abrir o destino."
            saida.use { out -> origem.inputStream().use { it.copyTo(out) } }
            null
        } catch (e: Exception) {
            apagarDocumento(destino)
            e.message ?: e.javaClass.simpleName
        }
    }

    private fun apagarDocumento(uri: Uri) {
        try {
            DocumentsContract.deleteDocument(contentResolver, uri)
        } catch (_: Exception) {
        }
    }

    /// ACTION_VIEW no arquivo salvo, com permissao de leitura para o app que
    /// abrir. false = nenhum app abre planilhas (o Dart avisa).
    private fun abrirDocumento(call: MethodCall): Boolean {
        val uri = call.argument<String>("uri") ?: return false
        val tipo = call.argument<String>("tipo") ?: return false
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(Uri.parse(uri), tipo)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return abrir(intent)
    }

    /// Responde uma vez; se o motor do Flutter ja foi embora, ignora.
    private fun responder(resposta: MethodChannel.Result?, acao: (MethodChannel.Result) -> Unit) {
        if (resposta == null) return
        try {
            acao(resposta)
        } catch (_: Exception) {
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

    companion object {
        private const val PEDIDO_SALVAR = 4101
        private const val CHAVE_ARQUIVO = "puzzleband_salvar_arquivo"
    }
}

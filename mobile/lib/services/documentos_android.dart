// "Salvar no celular" e "Abrir" do relatorio em Excel, pelas janelas do
// proprio Android (Storage Access Framework): o tutor escolhe a pasta na
// janela "Salvar como" do sistema, sem permissao de armazenamento. O lado
// nativo fica no MainActivity.kt (canal br.unimar.puzzleband/sistema). Uma
// interface, para os testes usarem um falso (test/apoio/sistema_falso.dart).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract class DocumentosDoSistema {
  /// Abre a janela "Salvar como" com [nome] preenchido e copia [arquivo] para
  /// onde o tutor escolher. Devolve o endereco (URI) do arquivo salvo, ou null
  /// se o tutor cancelou. Erro de copia = excecao.
  Future<String?> salvarComo(File arquivo, {required String nome, required String tipo});

  /// Abre o arquivo salvo no app de planilhas. false = nenhum app abre esse tipo.
  Future<bool> abrir(String uri, {required String tipo});
}

class DocumentosAndroid implements DocumentosDoSistema {
  const DocumentosAndroid();

  static const _canal = MethodChannel('br.unimar.puzzleband/sistema');

  @override
  Future<String?> salvarComo(File arquivo, {required String nome, required String tipo}) async {
    try {
      return await _canal.invokeMethod<String>('salvarDocumento', {'caminho': arquivo.path, 'nome': nome, 'tipo': tipo});
    } on PlatformException catch (e) {
      // Ja ha um "Salvar como" aberto: este pedido e ignorado (o primeiro continua)
      if (e.code == 'ocupado') return null;
      rethrow;
    }
  }

  @override
  Future<bool> abrir(String uri, {required String tipo}) async {
    try {
      return await _canal.invokeMethod<bool>('abrirDocumento', {'uri': uri, 'tipo': tipo}) ?? false;
    } catch (e) {
      debugPrint('Abrir o relatorio: $e');
      return false;
    }
  }
}

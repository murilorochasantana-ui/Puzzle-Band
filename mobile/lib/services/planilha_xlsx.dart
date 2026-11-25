// Gravador .xlsx minimo (Office Open XML, ECMA-376), sem dependencia alem do
// `archive` (MIT) para o zip. Feito para o relatorio do cuidador
// (relatorio.dart): abas com cabecalho em negrito, primeira linha
// congelada, largura de cada coluna, numeros com casas fixas, datas e
// duracoes como valores de verdade (o Excel ordena e soma). Abre no Excel, no
// Google Planilhas e no LibreOffice (docs/app.md, "Relatorio em Excel").
//
// Textos vao na tabela de textos compartilhados (sharedStrings), nunca como
// formula: um texto que comeca com "=" (uma observacao, por exemplo) aparece
// como texto, sem risco de virar formula no Excel.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Formato de uma coluna (estilo das celulas).
enum Formato {
  texto(0),
  inteiro(2),
  decimal1(3),
  decimal2(4),
  dataHora(5),
  data(6),
  duracao(7),
  porcentagem(8);

  const Formato(this.estilo);

  /// Indice em cellXfs (styles.xml). 1 = cabecalho.
  final int estilo;

  static Formato decimal(int casas) => switch (casas) {
        <= 0 => Formato.inteiro,
        1 => Formato.decimal1,
        _ => Formato.decimal2,
      };
}

class Coluna {
  const Coluna(this.titulo, {this.largura = 14, this.formato = Formato.texto});

  final String titulo;

  /// Largura em caracteres (como no Excel).
  final double largura;
  final Formato formato;
}

/// Uma aba. Cada linha tem um valor por coluna: null (celula vazia), String,
/// num, DateTime (hora local do celular) ou Duration.
class Aba {
  const Aba({required this.nome, required this.colunas, required this.linhas});

  final String nome;
  final List<Coluna> colunas;
  final List<List<Object?>> linhas;
}

/// Letra(s) da coluna: 0 -> A, 25 -> Z, 26 -> AA.
String letraDaColuna(int i) {
  var n = i + 1;
  final letras = StringBuffer();
  final pilha = <String>[];
  while (n > 0) {
    final resto = (n - 1) % 26;
    pilha.add(String.fromCharCode(65 + resto));
    n = (n - 1) ~/ 26;
  }
  for (final l in pilha.reversed) {
    letras.write(l);
  }
  return letras.toString();
}

/// Numero de serie do Excel (sistema 1900) para a hora local [d]: dias desde
/// 30/12/1899, com a fracao do dia. A hora vai como esta no relogio do
/// celular (o Excel nao guarda fuso).
double serialDoExcel(DateTime d) {
  final semFuso = DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second, d.millisecond);
  return semFuso.difference(DateTime.utc(1899, 12, 30)).inMilliseconds / Duration.millisecondsPerDay;
}

final _invalidosNoXml = RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]');

String _escapar(String s) {
  var texto = s.replaceAll(_invalidosNoXml, '');
  if (texto.length > 32767) texto = texto.substring(0, 32767); // limite de uma celula
  return texto
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String _numero(num v) {
  if (v is int) return v.toString();
  final d = v.toDouble();
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
  return d.toString();
}

/// Nome de aba valido: ate 31 caracteres, sem []:*?/\.
String _nomeDaAba(String nome) {
  final limpo = nome.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  return limpo.length > 31 ? limpo.substring(0, 31) : limpo;
}

const _cabecalhoXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const _nsPlanilha = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _nsRelacoes = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _nsPacote = 'http://schemas.openxmlformats.org/package/2006/relationships';

const _estilos = '''$_cabecalhoXml<styleSheet xmlns="$_nsPlanilha">
<numFmts count="5"><numFmt numFmtId="164" formatCode="0.0"/><numFmt numFmtId="165" formatCode="dd/mm/yyyy hh:mm"/><numFmt numFmtId="166" formatCode="dd/mm/yyyy"/><numFmt numFmtId="167" formatCode="[h]:mm:ss"/><numFmt numFmtId="168" formatCode="0.0%"/></numFmts>
<fonts count="2"><font><sz val="11"/><name val="Calibri"/><family val="2"/></font><font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE8EEF2"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FF8A9BA8"/></bottom><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="9">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
<xf numFmtId="1" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="2" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="166" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="167" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="168" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>''';

/// Monta o .xlsx (bytes do zip). [autor] e [criadoEm] vao nas propriedades
/// do documento.
Uint8List gerarXlsx(List<Aba> abas, {String autor = 'Puzzle Band', DateTime? criadoEm}) {
  assert(abas.isNotEmpty);
  final textos = <String>[];
  final indiceDoTexto = <String, int>{};
  var usosDeTexto = 0;
  int texto(String s) {
    usosDeTexto++;
    return indiceDoTexto.putIfAbsent(s, () {
      textos.add(s);
      return textos.length - 1;
    });
  }

  String celula(String ref, Object? valor, Formato formato, {bool cabecalho = false}) {
    final estilo = cabecalho ? 1 : formato.estilo;
    final s = estilo == 0 ? '' : ' s="$estilo"';
    return switch (valor) {
      null => '',
      String v => '<c r="$ref" t="s"$s><v>${texto(v)}</v></c>',
      bool v => '<c r="$ref" t="b"$s><v>${v ? 1 : 0}</v></c>',
      num v when !v.isFinite => '',
      num v => '<c r="$ref"$s><v>${_numero(v)}</v></c>',
      DateTime v => '<c r="$ref" s="${formato == Formato.data ? Formato.data.estilo : (cabecalho ? 1 : Formato.dataHora.estilo)}"><v>${_numero(serialDoExcel(v))}</v></c>',
      Duration v => '<c r="$ref" s="${Formato.duracao.estilo}"><v>${_numero(v.inMilliseconds / Duration.millisecondsPerDay)}</v></c>',
      _ => '<c r="$ref" t="s"$s><v>${texto(valor.toString())}</v></c>',
    };
  }

  String planilha(Aba aba) {
    final b = StringBuffer(_cabecalhoXml)
      ..write('<worksheet xmlns="$_nsPlanilha" xmlns:r="$_nsRelacoes">');
    final ultimaColuna = letraDaColuna(aba.colunas.length - 1);
    b.write('<dimension ref="A1:$ultimaColuna${aba.linhas.length + 1}"/>');
    // Primeira linha congelada (cabecalho sempre visivel ao rolar)
    b.write('<sheetViews><sheetView workbookViewId="0">'
        '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
        '<selection pane="bottomLeft" activeCell="A2" sqref="A2"/>'
        '</sheetView></sheetViews>');
    b.write('<sheetFormatPr defaultRowHeight="15"/>');
    b.write('<cols>');
    for (final (i, c) in aba.colunas.indexed) {
      b.write('<col min="${i + 1}" max="${i + 1}" width="${c.largura}" customWidth="1"/>');
    }
    b.write('</cols><sheetData>');
    b.write('<row r="1" ht="32" customHeight="1">');
    for (final (i, c) in aba.colunas.indexed) {
      b.write(celula('${letraDaColuna(i)}1', c.titulo, Formato.texto, cabecalho: true));
    }
    b.write('</row>');
    for (final (l, linha) in aba.linhas.indexed) {
      final r = l + 2;
      b.write('<row r="$r">');
      for (var i = 0; i < aba.colunas.length && i < linha.length; i++) {
        b.write(celula('${letraDaColuna(i)}$r', linha[i], aba.colunas[i].formato));
      }
      b.write('</row>');
    }
    b.write('</sheetData>');
    b.write('<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>');
    b.write('</worksheet>');
    return b.toString();
  }

  final planilhas = [for (final a in abas) planilha(a)];
  final nomes = [for (final a in abas) _nomeDaAba(a.nome)];

  final sharedStrings = StringBuffer(_cabecalhoXml)
    ..write('<sst xmlns="$_nsPlanilha" count="$usosDeTexto" uniqueCount="${textos.length}">');
  for (final t in textos) {
    sharedStrings.write('<si><t xml:space="preserve">${_escapar(t)}</t></si>');
  }
  sharedStrings.write('</sst>');

  final workbook = StringBuffer(_cabecalhoXml)
    ..write('<workbook xmlns="$_nsPlanilha" xmlns:r="$_nsRelacoes">')
    ..write('<bookViews><workbookView xWindow="0" yWindow="0" windowWidth="16000" windowHeight="9000" activeTab="0"/></bookViews>')
    ..write('<sheets>');
  for (final (i, nome) in nomes.indexed) {
    workbook.write('<sheet name="${_escapar(nome)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
  }
  workbook.write('</sheets></workbook>');

  final relacoesDoWorkbook = StringBuffer(_cabecalhoXml)..write('<Relationships xmlns="$_nsPacote">');
  for (var i = 0; i < abas.length; i++) {
    relacoesDoWorkbook.write('<Relationship Id="rId${i + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
        'Target="worksheets/sheet${i + 1}.xml"/>');
  }
  relacoesDoWorkbook
    ..write('<Relationship Id="rId${abas.length + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>')
    ..write('<Relationship Id="rId${abas.length + 2}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>')
    ..write('</Relationships>');

  final tipos = StringBuffer(_cabecalhoXml)
    ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
    ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
    ..write('<Default Extension="xml" ContentType="application/xml"/>')
    ..write('<Override PartName="/xl/workbook.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>');
  for (var i = 0; i < abas.length; i++) {
    tipos.write('<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
  }
  tipos
    ..write('<Override PartName="/xl/styles.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>')
    ..write('<Override PartName="/xl/sharedStrings.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>')
    ..write('<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>')
    ..write('<Override PartName="/docProps/app.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>')
    ..write('</Types>');

  final relacoes = '$_cabecalhoXml<Relationships xmlns="$_nsPacote">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
      '</Relationships>';

  final quando = (criadoEm ?? DateTime.now()).toUtc();
  final iso = '${quando.toIso8601String().split('.').first}Z';
  final core = '$_cabecalhoXml<cp:coreProperties '
      'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:creator>${_escapar(autor)}</dc:creator>'
      '<dcterms:created xsi:type="dcterms:W3CDTF">$iso</dcterms:created>'
      '<dcterms:modified xsi:type="dcterms:W3CDTF">$iso</dcterms:modified>'
      '</cp:coreProperties>';
  final app = '$_cabecalhoXml<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
      '<Application>${_escapar(autor)}</Application></Properties>';

  final zip = Archive();
  void arquivo(String nome, String conteudo) {
    final bytes = utf8.encode(conteudo);
    zip.addFile(ArchiveFile(nome, bytes.length, bytes));
  }

  arquivo('[Content_Types].xml', tipos.toString());
  arquivo('_rels/.rels', relacoes);
  arquivo('docProps/core.xml', core);
  arquivo('docProps/app.xml', app);
  arquivo('xl/workbook.xml', workbook.toString());
  arquivo('xl/_rels/workbook.xml.rels', relacoesDoWorkbook.toString());
  arquivo('xl/styles.xml', _estilos);
  arquivo('xl/sharedStrings.xml', sharedStrings.toString());
  for (final (i, p) in planilhas.indexed) {
    arquivo('xl/worksheets/sheet${i + 1}.xml', p);
  }
  return Uint8List.fromList(ZipEncoder().encode(zip)!);
}

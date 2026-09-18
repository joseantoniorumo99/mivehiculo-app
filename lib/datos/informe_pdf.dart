/// EL INFORME COMPLETO DEL COCHE EN PDF: lo que se le da a quien lo compra.
///
/// Es el "historial" que en otros países vende una empresa por matrícula
/// (Carfax) y que aquí no existe: aquí lo hace el DUEÑO con lo que ha ido
/// anotando, y por eso vale lo que valga el diario. El documento lo dice al
/// final con todas las letras: no sustituye al informe de la DGT ni a una
/// revisión mecánica, y las facturas son la prueba de cada intervención.
///
/// Se genera EN EL MÓVIL y se comparte desde él (WhatsApp, correo, Drive). No
/// pasa por ningún servidor: es el documento más sensible de la app —sabe
/// dónde vive el coche y cuánto ha costado— y no tiene por qué salir de la
/// mano del dueño.
///
/// Qué lleva, en este orden, porque es el orden en que lo lee un comprador:
///   1. Datos del vehículo (matrícula, matriculación, bastidor, km).
///   2. Resumen en cifras y en qué se ha ido el dinero.
///   3. Estado: ITV, lo que toca, y LOS HUECOS (años sin documentar). El hueco
///      es la parte honesta del documento, y por eso convence.
///   4. Todas las intervenciones, con su desglose y si hay factura.
///   5. Las lecturas del diagnóstico OBD (km y códigos de avería con fecha).
///   6. Los informes que han mandado los talleres.
///   7. Qué es y qué no es este documento.
///
/// La letra es Roboto (Apache 2.0), dentro de la app: las tipografías de
/// serie del PDF no tienen ni el euro ni todas las tildes.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'mantenimiento.dart';
import 'modelo.dart';

final _azul = PdfColor.fromHex('2B6CB0');
final _tinta = PdfColor.fromHex('1F2937');
final _suave = PdfColor.fromHex('556275');
final _regla = PdfColor.fromHex('D9E0EA');
final _suelo = PdfColor.fromHex('EEF2F7');
final _naranja = PdfColor.fromHex('8A5200');
final _rojo = PdfColor.fromHex('B5272D');
final _teal = PdfColor.fromHex('146170');

class InformePdf {
  /// Carga la letra de los assets y construye el documento.
  static Future<Uint8List> construir({
    required Vehiculo coche,
    required List<Intervencion> diario,
    required List<LecturaGuardada> lecturas,
    List<Cita> citas = const [],
    DateTime? hoyPara,
  }) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fuentes/Roboto-Regular.ttf'));
    final negrita = pw.Font.ttf(await rootBundle.load('assets/fuentes/Roboto-Bold.ttf'));
    return construirConLetra(
      coche: coche,
      diario: diario,
      lecturas: lecturas,
      citas: citas,
      regular: regular,
      negrita: negrita,
      hoyPara: hoyPara,
    );
  }

  /// La construcción de verdad, con la letra ya cargada (así se prueba sin
  /// assets).
  static Future<Uint8List> construirConLetra({
    required Vehiculo coche,
    required List<Intervencion> diario,
    required List<LecturaGuardada> lecturas,
    required pw.Font regular,
    required pw.Font negrita,
    List<Cita> citas = const [],
    DateTime? hoyPara,
  }) async {
    final hoy = hoyPara ?? DateTime.now();
    final emitido = fechaCorta(hoyIso(hoy));
    final cronologico = [...diario]..sort((a, b) => a.fecha.compareTo(b.fecha));
    final total = diario.fold(0.0, (s, d) => s + (d.coste ?? 0));
    final huecos = aniosSinDocumentar(coche, diario);
    // La ITV tiene su línea propia arriba; en la lista van los demás avisos.
    final avisos = avisosDe(coche, diario, hoyPara: hoy).where((a) => a.clave != 'itv').toList();
    final itv = proximaItv(coche.anioEfectivo, coche.matriculacion,
        hoyPara: hoy, ultimaItv: ultimaDelTipo(diario, 'itv')?.fecha);
    final kms = diario.map((d) => d.km).whereType<int>().toList()..sort();
    final porTipo = <String, double>{};
    for (final d in diario) {
      porTipo[d.tipo] = (porTipo[d.tipo] ?? 0) + (d.coste ?? 0);
    }
    final tiposOrdenados = porTipo.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final lecturasOrdenadas = [...lecturas]..sort((a, b) => b.cuando.compareTo(a.cuando));
    final informes = citas.where((c) => c.hayInforme).toList()
      ..sort((a, b) => b.informeFecha.compareTo(a.informeFecha));

    final doc = pw.Document(
      title: 'Informe de ${coche.nombre}',
      author: 'Mi Vehículo',
      theme: pw.ThemeData.withFont(base: regular, bold: negrita).copyWith(
        defaultTextStyle: pw.TextStyle(font: regular, fontSize: 10, color: _tinta, lineSpacing: 2),
      ),
    );

    final titulo = '${coche.nombre}${coche.matricula.isNotEmpty ? ' · ${coche.matricula}' : ''}';

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 36),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 14),
              padding: const pw.EdgeInsets.only(bottom: 4),
              decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _regla))),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Mi Vehículo · Informe del vehículo', style: pw.TextStyle(fontSize: 8, color: _suave)),
                  pw.Text(titulo, style: pw.TextStyle(fontSize: 8, color: _suave)),
                ],
              ),
            ),
      footer: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Emitido el $emitido por el titular desde la app Mi Vehículo',
                style: pw.TextStyle(fontSize: 8, color: _suave)),
            pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: _suave)),
          ],
        ),
      ),
      build: (ctx) => [
        // ---- Portada ----
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('INFORME DEL VEHÍCULO',
                      style: pw.TextStyle(fontSize: 9, color: _azul, fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
                  pw.SizedBox(height: 4),
                  pw.Text(coche.nombre, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Historial de mantenimiento documentado por el titular',
                      style: pw.TextStyle(fontSize: 11, color: _suave)),
                ],
              ),
            ),
            if (coche.matricula.isNotEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _tinta, width: 1.2),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(coche.matricula,
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, letterSpacing: 2)),
              ),
          ],
        ),
        pw.SizedBox(height: 10),

        // ---- 1. Datos ----
        _seccion('1. Datos del vehículo'),
        _fila('Marca y modelo', '${coche.marca} ${coche.modelo}'.trim().isEmpty ? '—' : '${coche.marca} ${coche.modelo}'.trim()),
        if (coche.matricula.isNotEmpty) _fila('Matrícula', coche.matricula),
        _fila(
            'Primera matriculación',
            coche.matriculacion.isNotEmpty
                ? fechaCorta(coche.matriculacion)
                : (coche.anio != null ? '${coche.anio} (solo el año)' : 'no consta')),
        if (coche.combustible.isNotEmpty) _fila('Combustible', coche.combustible),
        _fila('Kilómetros actuales', coche.km != null ? '${conMiles(coche.km!)} km' : 'no consta'),
        _fila('Bastidor (VIN)', coche.bastidor.isNotEmpty ? coche.bastidor : 'no leído'),
        if (coche.adBlue != 'auto') _fila('AdBlue', coche.adBlue == 'si' ? 'sí' : (coche.adBlue == 'no' ? 'no' : 'sin confirmar')),

        // ---- 2. Resumen ----
        _seccion('2. Resumen'),
        pw.Row(children: [
          _cifra('Intervenciones', '${diario.length}'),
          _cifra('Gasto documentado', enEuros(total)),
          _cifra(
              'Km anotados',
              kms.isEmpty
                  ? '—'
                  : (kms.length == 1 ? conMiles(kms.first) : '${conMiles(kms.first)} a ${conMiles(kms.last)}')),
          _cifra(
              'Periodo',
              cronologico.isEmpty
                  ? '—'
                  : '${cronologico.first.fecha.substring(0, 4)} – ${cronologico.last.fecha.substring(0, 4)}',
              ultima: true),
        ]),
        if (tiposOrdenados.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text('En qué se ha ido', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            context: ctx,
            headers: ['Concepto', 'Importe', '% del total'],
            data: tiposOrdenados
                .map((e) => [
                      tiposMantenimiento[e.key] ?? e.key,
                      enEuros(e.value),
                      total > 0 ? '${(e.value / total * 100).round()} %' : '—',
                    ])
                .toList(),
            border: null,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: _suave),
            headerDecoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _regla))),
            cellStyle: const pw.TextStyle(fontSize: 9.5),
            cellPadding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
            columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(1)},
            rowDecoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _regla, width: 0.5))),
          ),
        ],

        // ---- 3. Estado ----
        _seccion('3. Estado a día de hoy'),
        if (itv != null)
          _punto(
            itv.vencida
                ? 'ITV caducada desde ${itv.cuando}.'
                : 'Próxima ITV: ${itv.cuando}${itv.desdeUltima ? ' (contada desde la última ITV anotada)' : itv.exacta ? '' : ' (aproximada: no consta el mes de matriculación)'}.',
            color: itv.vencida ? _rojo : (itv.faltan <= 0 ? _naranja : _teal),
          )
        else
          _punto('ITV: no se puede calcular sin el año de matriculación.', color: _suave),
        if (avisos.isEmpty)
          _punto('Nada pendiente que conste: los avisos de aceite, frenos, neumáticos y correa salen de lo anotado.', color: _teal)
        else
          ...avisos.map((a) => _punto('${a.tipo}: ${a.detalle}',
              color: switch (a.urgencia) { Urgencia.alta => _rojo, Urgencia.media => _naranja, Urgencia.baja => _teal })),
        if (huecos.isNotEmpty)
          _punto(
              huecos.length == 1
                  ? 'El año ${huecos.first} no tiene ninguna anotación.'
                  : 'Años sin anotaciones: ${huecos.join(', ')}. En esos años no consta qué se le hizo al coche.',
              color: _naranja),

        // ---- 4. Historial ----
        _seccion('4. Todas las intervenciones (${diario.length})'),
        if (cronologico.isEmpty)
          pw.Text('Todavía no hay ninguna anotada.', style: pw.TextStyle(color: _suave))
        else
          ...cronologico.map(_intervencion),

        // ---- 5. OBD ----
        _seccion('5. Lecturas del diagnóstico OBD (${lecturas.length})'),
        if (lecturasOrdenadas.isEmpty)
          pw.Text('Ninguna lectura guardada. Se hacen desde la app con un lector ELM327 conectado al coche.',
              style: pw.TextStyle(color: _suave))
        else ...[
          pw.Text(
            'Cada lectura es lo que la centralita del coche contestó ese día: el cuentakilómetros '
            'cuando el coche lo publica, y los códigos de avería memorizados (ninguno = sin averías).',
            style: pw.TextStyle(fontSize: 9, color: _suave),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            context: ctx,
            headers: ['Fecha', 'Km', 'Códigos de avería', 'Detalle'],
            data: lecturasOrdenadas.take(40).map((l) {
              final automatica = l.valores['Lectura'] == 'automática';
              final n = l.valores.length - (automatica ? 1 : 0);
              return [
                fechaCorta(l.cuando),
                l.km != null ? conMiles(l.km!) : '—',
                l.codigos.isEmpty ? 'ninguno' : l.codigos.join(', '),
                '$n datos${automatica ? ' · automática' : ''}',
              ];
            }).toList(),
            border: null,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: _suave),
            headerDecoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _regla))),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellPadding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            cellAlignments: {1: pw.Alignment.centerRight},
            columnWidths: {
              0: const pw.FlexColumnWidth(1.3),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(2.2),
              3: const pw.FlexColumnWidth(1.6),
            },
            rowDecoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _regla, width: 0.5))),
          ),
          if (lecturasOrdenadas.length > 40)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text('Se enseñan las 40 más recientes de ${lecturas.length}.',
                  style: pw.TextStyle(fontSize: 8.5, color: _suave)),
            ),
        ],

        // ---- 6. Informes de taller ----
        if (informes.isNotEmpty) ...[
          _seccion('6. Informes recibidos de talleres (${informes.length})'),
          pw.Text(
            'Redactados por el propio taller desde su panel al terminar el trabajo. '
            'Los que el titular añadió a su diario aparecen también en el apartado 4.',
            style: pw.TextStyle(fontSize: 9, color: _suave),
          ),
          pw.SizedBox(height: 6),
          ...informes.map(_informeTaller),
        ],

        // ---- 7. Nota ----
        _seccion('${informes.isNotEmpty ? 7 : 6}. Sobre este informe'),
        pw.Text(
          'Este documento lo genera el titular del vehículo desde la app Mi Vehículo con los datos que él '
          'mismo ha anotado (intervenciones, facturas, lecturas del diagnóstico OBD) y los informes que le '
          'han mandado los talleres. Vale lo que valga esa documentación: las facturas adjuntas en la app '
          'son la prueba de cada intervención, y los años sin anotaciones se indican expresamente. '
          'No sustituye al informe de la DGT (cargas, titularidad, ITV oficial) ni a una revisión '
          'mecánica antes de la compra.',
          style: pw.TextStyle(fontSize: 9, color: _suave, lineSpacing: 2.5),
        ),
      ],
    ));

    return doc.save();
  }

  // ---------------------------------------------------------------- piezas

  static pw.Widget _seccion(String texto) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 16, bottom: 8),
        padding: const pw.EdgeInsets.only(bottom: 4),
        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _azul, width: 1.2))),
        child: pw.Text(texto, style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold, color: _azul)),
      );

  static pw.Widget _fila(String etiqueta, String valor) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 150, child: pw.Text(etiqueta, style: pw.TextStyle(color: _suave))),
            pw.Expanded(child: pw.Text(valor, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
          ],
        ),
      );

  static pw.Widget _cifra(String etiqueta, String valor, {bool ultima = false}) => pw.Expanded(
        child: pw.Container(
          margin: pw.EdgeInsets.only(right: ultima ? 0 : 8),
          padding: const pw.EdgeInsets.all(9),
          decoration: pw.BoxDecoration(color: _suelo, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(etiqueta, style: pw.TextStyle(fontSize: 8, color: _suave)),
              pw.SizedBox(height: 3),
              pw.Text(valor, style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
      );

  static pw.Widget _punto(String texto, {required PdfColor color}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 7,
              height: 7,
              margin: const pw.EdgeInsets.only(top: 3.5, right: 7),
              decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
            ),
            pw.Expanded(child: pw.Text(texto)),
          ],
        ),
      );

  static pw.Widget _intervencion(Intervencion d) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 6),
        padding: const pw.EdgeInsets.fromLTRB(9, 7, 9, 7),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _regla),
          borderRadius: pw.BorderRadius.circular(5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(children: [
              pw.Expanded(
                  child: pw.Text(d.tituloEfectivo, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5))),
              pw.Text(enEuros(d.coste), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5)),
            ]),
            pw.Text(
              [
                fechaCorta(d.fecha),
                if (d.km != null) '${conMiles(d.km!)} km',
                if (d.taller.isNotEmpty) d.taller,
                if (d.factura.isNotEmpty) 'con factura adjunta en la app',
                if (d.fotos.isNotEmpty) '${d.fotos.length} ${d.fotos.length == 1 ? 'foto' : 'fotos'} de las piezas en la app',
              ].join(' · '),
              style: pw.TextStyle(fontSize: 8.5, color: _suave),
            ),
            if (d.lineas.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              ...d.lineas.map((l) => pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 8, top: 1),
                    child: pw.Row(children: [
                      pw.Expanded(
                          child: pw.Text('· ${l.concepto.isEmpty ? '(sin concepto)' : l.concepto}',
                              style: const pw.TextStyle(fontSize: 9))),
                      pw.Text(enEuros(l.importe), style: const pw.TextStyle(fontSize: 9)),
                    ]),
                  )),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 8, top: 1),
                child: pw.Text('Desglose: base imponible; el importe de arriba es el total.',
                    style: pw.TextStyle(fontSize: 7.5, color: _suave)),
              ),
            ],
            if (d.nota.isNotEmpty) ...[
              pw.SizedBox(height: 3),
              pw.Text(d.nota, style: const pw.TextStyle(fontSize: 9)),
            ],
          ],
        ),
      );

  static pw.Widget _informeTaller(Cita c) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 6),
        padding: const pw.EdgeInsets.fromLTRB(9, 7, 9, 7),
        decoration: pw.BoxDecoration(
          color: _suelo,
          borderRadius: pw.BorderRadius.circular(5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(children: [
              pw.Expanded(
                  child: pw.Text(
                      '${c.lugarNombre.isEmpty ? 'Taller' : c.lugarNombre} · ${c.informeTitulo.isEmpty ? c.servicio : c.informeTitulo}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5))),
              if (c.informeTotal != null)
                pw.Text(enEuros(c.informeTotal), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10.5)),
            ]),
            pw.Text(
              [
                if (c.informeFecha.isNotEmpty) fechaCorta(c.informeFecha),
                if (c.informeKm != null) '${conMiles(c.informeKm!)} km',
                c.informeAnadido ? 'añadido al diario' : 'no añadido al diario',
              ].join(' · '),
              style: pw.TextStyle(fontSize: 8.5, color: _suave),
            ),
            ...c.informeLineas.map((l) => pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 8, top: 1),
                  child: pw.Row(children: [
                    pw.Expanded(child: pw.Text('· ${l.concepto}', style: const pw.TextStyle(fontSize: 9))),
                    pw.Text(enEuros(l.importe), style: const pw.TextStyle(fontSize: 9)),
                  ]),
                )),
            if (c.informeNotas.isNotEmpty) ...[
              pw.SizedBox(height: 3),
              pw.Text(c.informeNotas, style: const pw.TextStyle(fontSize: 9)),
            ],
          ],
        ),
      );
}

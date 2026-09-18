/// EL EXPEDIENTE DEL COCHE: el historial completo, listo para enseñar.
///
/// Es lo que se le da a quien compra el coche, y lo que uno mismo mira cuando
/// quiere saber cuánto le ha costado de verdad. Se comparte como texto —a
/// WhatsApp, al correo, a donde sea— sin mandar nada a ningún servidor.
///
/// LA PIEZA QUE LO HACE FUNCIONAR ES EL HUECO: un coche de 2019 cuyo diario
/// empieza en 2026 tiene siete años sin documentar, y verlo escrito motiva a
/// subir las facturas viejas más que cualquier aviso, porque uno está mirando
/// un documento que quiere completo. Con el botón de anotar al lado: avisar de
/// que falta algo sin dar dónde ponerlo es solo dar la lata.
library;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../datos/informe_pdf.dart';
import '../datos/mantenimiento.dart';
import '../datos/modelo.dart';
import '../estado.dart';
import '../tema.dart';
import 'editar_intervencion.dart';
import 'ver_intervencion.dart';

class PantallaExpediente extends StatelessWidget {
  const PantallaExpediente({super.key});

  @override
  Widget build(BuildContext context) {
    final almacen = context.almacen;
    return ListenableBuilder(
      listenable: almacen,
      builder: (context, _) {
        final coche = almacen.coche;
        if (coche == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Expediente')),
            body: const Vacio(
                icono: Icons.folder_open,
                titulo: 'Sin coche',
                texto: 'Da de alta tu coche en el inicio.'),
          );
        }
        final diario = almacen.diarioDelCoche;
        final lecturas = almacen.lecturasDelCoche;
        final huecos = aniosSinDocumentar(coche, diario);
        final total = diario.fold(0.0, (s, d) => s + (d.coste ?? 0));
        final porTipo = <String, double>{};
        for (final d in diario) {
          porTipo[d.tipo] = (porTipo[d.tipo] ?? 0) + (d.coste ?? 0);
        }
        final tiposOrdenados = porTipo.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Expediente'),
            actions: [
              IconButton(
                tooltip: 'Compartir',
                onPressed: () => SharePlus.instance.share(ShareParams(
                  text: textoExpediente(coche, diario, lecturas),
                  subject: 'Expediente de ${coche.nombre}',
                )),
                icon: const Icon(Icons.ios_share),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Tarjeta(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(coche.nombre,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      if (coche.matricula.isNotEmpty) FilaDato('Matrícula', coche.matricula),
                      if (coche.anioEfectivo != null)
                        FilaDato('Matriculación',
                            coche.matriculacion.isNotEmpty ? fechaCorta(coche.matriculacion) : '${coche.anioEfectivo}'),
                      if (coche.combustible.isNotEmpty) FilaDato('Combustible', coche.combustible),
                      if (coche.km != null) FilaDato('Kilómetros', '${conMiles(coche.km!)} km'),
                      if (coche.bastidor.isNotEmpty) FilaDato('Bastidor', coche.bastidor, monoespaciada: true),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(child: _cifra('Gasto total', enEuros(total))),
                    const SizedBox(width: 10),
                    Expanded(child: _cifra('Intervenciones', '${diario.length}')),
                    const SizedBox(width: 10),
                    Expanded(child: _cifra('Lecturas OBD', '${lecturas.length}')),
                  ],
                ),
                if (huecos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Recuadro(
                    huecos.length == 1
                        ? 'El año ${huecos.first} no tiene ninguna anotación.'
                        : '${huecos.length} años sin documentar: ${_resumirAnios(huecos)}.',
                    consejo: 'Si tienes facturas viejas, anótalas con su fecha: el '
                        'expediente vale por lo que tiene, y a quien compre el coche '
                        'le importa más un hueco que un golpe bien documentado.',
                    tono: TonoEstado.atencion,
                    accion: TextButton(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const PantallaEditarIntervencion())),
                      child: const Text('Anotar una factura antigua'),
                    ),
                  ),
                ],
                if (tiposOrdenados.isNotEmpty) ...[
                  const TituloSeccion('En qué se ha ido'),
                  Tarjeta(
                    child: Column(
                      children: tiposOrdenados
                          .map((e) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(tiposMantenimiento[e.key] ?? e.key)),
                                    Text(enEuros(e.value),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: [FontFeature.tabularFigures()])),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ],
                const TituloSeccion('Todas las intervenciones'),
                if (diario.isEmpty)
                  const Tarjeta(
                    child: Text('Todavía no hay nada anotado.',
                        style: TextStyle(color: Tono.tintaSuave)),
                  )
                else
                  ...diario.map((d) => Tarjeta(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => PantallaVerIntervencion(id: d.id))),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(d.tituloEfectivo,
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(
                                    [
                                      fechaCorta(d.fecha),
                                      if (d.km != null) '${conMiles(d.km!)} km',
                                      if (d.taller.isNotEmpty) d.taller,
                                      if (d.factura.isNotEmpty) 'con factura',
                                    ].join(' · '),
                                    style: const TextStyle(fontSize: 12, color: Tono.tintaSuave),
                                  ),
                                ],
                              ),
                            ),
                            Text(enEuros(d.coste),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: [FontFeature.tabularFigures()])),
                          ],
                        ),
                      )),
                const SizedBox(height: 12),
                _BotonInformePdf(coche: coche, diario: diario, lecturas: lecturas,
                    citas: almacen.citasDelCoche),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => SharePlus.instance.share(ShareParams(
                    text: textoExpediente(coche, diario, lecturas),
                    subject: 'Expediente de ${coche.nombre}',
                  )),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Compartir como texto'),
                ),
                const SizedBox(height: 6),
                const Text(
                  'El informe se genera en tu móvil y se comparte a donde tú elijas '
                  '(WhatsApp, correo, Drive). No pasa por ningún servidor.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Tono.tintaSuave),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cifra(String etiqueta, String valor) => Tarjeta(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(etiqueta, style: const TextStyle(fontSize: 11, color: Tono.tintaSuave)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(valor,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ],
        ),
      );

  static String _resumirAnios(List<int> anios) {
    // 2019, 2020, 2021, 2024 → "2019–2021 y 2024"
    final tramos = <String>[];
    var i = 0;
    while (i < anios.length) {
      var j = i;
      while (j + 1 < anios.length && anios[j + 1] == anios[j] + 1) {
        j++;
      }
      tramos.add(j > i ? '${anios[i]}–${anios[j]}' : '${anios[i]}');
      i = j + 1;
    }
    if (tramos.length == 1) return tramos.first;
    return '${tramos.sublist(0, tramos.length - 1).join(', ')} y ${tramos.last}';
  }
}

/// El botón del informe en PDF. Genera el documento en el móvil (medio segundo
/// con un diario normal) y abre la hoja de compartir del sistema.
class _BotonInformePdf extends StatefulWidget {
  final Vehiculo coche;
  final List<Intervencion> diario;
  final List<LecturaGuardada> lecturas;
  final List<Cita> citas;
  const _BotonInformePdf(
      {required this.coche, required this.diario, required this.lecturas, required this.citas});

  @override
  State<_BotonInformePdf> createState() => _BotonInformePdfState();
}

class _BotonInformePdfState extends State<_BotonInformePdf> {
  bool _generando = false;

  Future<void> _generar() async {
    setState(() => _generando = true);
    try {
      final bytes = await InformePdf.construir(
        coche: widget.coche,
        diario: widget.diario,
        lecturas: widget.lecturas,
        citas: widget.citas,
      );
      final nombre = widget.coche.matricula.isNotEmpty
          ? widget.coche.matricula.replaceAll(' ', '')
          : widget.coche.nombre.replaceAll(' ', '-');
      await Printing.sharePdf(bytes: bytes, filename: 'informe-$nombre.pdf');
    } catch (e) {
      if (mounted) avisar(context, 'No se pudo generar el informe: $e');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: _generando ? null : _generar,
        icon: _generando
            ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.picture_as_pdf_outlined),
        label: Text(_generando ? 'Generando el informe…' : 'Informe completo en PDF'),
      );
}

/// El expediente como texto plano, para compartir. Sin adornos: lo que se
/// pega en un WhatsApp o un correo tiene que leerse en cualquier sitio.
String textoExpediente(
    Vehiculo coche, List<Intervencion> diario, List<LecturaGuardada> lecturas) {
  final b = StringBuffer();
  b.writeln('EXPEDIENTE DE ${coche.nombre.toUpperCase()}');
  if (coche.matricula.isNotEmpty) b.writeln('Matrícula: ${coche.matricula}');
  if (coche.matriculacion.isNotEmpty) {
    b.writeln('Primera matriculación: ${fechaCorta(coche.matriculacion)}');
  } else if (coche.anio != null) {
    b.writeln('Año: ${coche.anio}');
  }
  if (coche.combustible.isNotEmpty) b.writeln('Combustible: ${coche.combustible}');
  if (coche.km != null) b.writeln('Kilómetros: ${conMiles(coche.km!)} km');
  if (coche.bastidor.isNotEmpty) b.writeln('Bastidor: ${coche.bastidor}');
  b.writeln();

  final total = diario.fold(0.0, (s, d) => s + (d.coste ?? 0));
  b.writeln('${diario.length} intervenciones · ${enEuros(total)} en total');
  final huecos = aniosSinDocumentar(coche, diario);
  if (huecos.isNotEmpty) {
    b.writeln('Años sin anotaciones: ${huecos.join(', ')}');
  }
  b.writeln();

  final cronologico = [...diario]..sort((a, c) => a.fecha.compareTo(c.fecha));
  for (final d in cronologico) {
    b.writeln('${fechaCorta(d.fecha)}'
        '${d.km != null ? ' · ${conMiles(d.km!)} km' : ''}'
        ' · ${d.tituloEfectivo} · ${enEuros(d.coste)}'
        '${d.taller.isNotEmpty ? ' · ${d.taller}' : ''}');
    for (final l in d.lineas) {
      b.writeln('    - ${l.concepto.isEmpty ? '(sin concepto)' : l.concepto}: ${enEuros(l.importe)}');
    }
    if (d.nota.isNotEmpty) b.writeln('    ${d.nota}');
  }
  if (lecturas.isNotEmpty) {
    b.writeln();
    b.writeln('${lecturas.length} lecturas del OBD guardadas'
        ' (última: ${fechaCorta(lecturas.first.cuando)})');
  }
  b.writeln();
  b.writeln('Generado con Mi Vehículo.');
  return b.toString();
}

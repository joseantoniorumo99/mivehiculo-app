/// UNA INTERVENCIÓN EN MODO LECTURA. Sin un solo campo.
///
/// «Corregir estos datos» vive abajo del todo, porque consultar es lo que se
/// hace siempre y editar casi nunca: una factura de hace tres años se mira
/// para saber qué aceite lleva el coche, no para cambiarla.
library;

import 'package:flutter/material.dart';

import '../datos/mantenimiento.dart';
import '../datos/modelo.dart';
import '../estado.dart';
import '../tema.dart';
import 'editar_intervencion.dart';

class PantallaVerIntervencion extends StatelessWidget {
  final String id;
  const PantallaVerIntervencion({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    final almacen = context.almacen;
    return ListenableBuilder(
      listenable: almacen,
      builder: (context, _) {
        final d = almacen.intervencion(id);
        if (d == null) {
          // Se borró mientras estaba abierta (desde otro aparato, por ejemplo)
          return Scaffold(
            appBar: AppBar(),
            body: const Vacio(
              icono: Icons.search_off,
              titulo: 'Esta anotación ya no está',
              texto: 'Se ha borrado del diario.',
            ),
          );
        }
        final foto = almacen.ficheroFactura(d.factura);
        return Scaffold(
          appBar: AppBar(title: Text(tiposMantenimiento[d.tipo] ?? 'Intervención')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(d.tituloEfectivo,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                const SizedBox(height: 4),
                Text(
                  [fechaCorta(d.fecha), if (d.km != null) '${conMiles(d.km!)} km'].join(' · '),
                  style: const TextStyle(color: Tono.tintaSuave),
                ),
                const SizedBox(height: 16),
                Tarjeta(
                  child: Column(
                    children: [
                      FilaDato('Total', enEuros(d.coste)),
                      if (d.taller.isNotEmpty) FilaDato('Taller', d.taller),
                      FilaDato('Tipo', tiposMantenimiento[d.tipo] ?? d.tipo),
                    ],
                  ),
                ),
                if (d.lineas.isNotEmpty) ...[
                  const TituloSeccion('Desglose'),
                  Tarjeta(
                    child: Column(
                      children: [
                        ...d.lineas.map((l) => _lineaDesglose(l)),
                        const Divider(height: 18),
                        Row(
                          children: [
                            const Expanded(
                                child: Text('Base imponible',
                                    style: TextStyle(fontWeight: FontWeight.w700))),
                            Text(enEuros(d.sumaLineas),
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                          ],
                        ),
                        if (d.coste != null && (d.coste! - d.sumaLineas).abs() > 0.5)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              ((d.sumaLineas * 1.21) - d.coste!).abs() < 1
                                  ? 'El total incluye el 21 % de IVA.'
                                  : 'El total anotado no coincide con la suma del desglose.',
                              style: const TextStyle(fontSize: 12, color: Tono.tintaSuave),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (d.factura.isNotEmpty) ...[
                  const TituloSeccion('Factura'),
                  if (foto != null)
                    GestureDetector(
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          insetPadding: const EdgeInsets.all(12),
                          child: InteractiveViewer(child: Image.file(foto)),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(foto, width: double.infinity, height: 220, fit: BoxFit.cover),
                      ),
                    )
                  else
                    const Recuadro(
                      'La foto de la factura no está en este móvil.',
                      consejo: 'Si tienes cuenta, se bajará al sincronizar. Si no, la '
                          'anotación sigue valiendo: solo falta la imagen.',
                      tono: TonoEstado.neutro,
                    ),
                ],
                if (d.fotos.isNotEmpty) ...[
                  const TituloSeccion('Fotos'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: d.fotos.map((nombre) {
                      final f = almacen.ficheroFactura(nombre);
                      if (f == null) {
                        return Container(
                          width: 104,
                          height: 78,
                          decoration: BoxDecoration(color: Tono.suelo, borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.image_not_supported_outlined, color: Tono.tintaSuave),
                        );
                      }
                      return GestureDetector(
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            insetPadding: const EdgeInsets.all(12),
                            child: InteractiveViewer(child: Image.file(f)),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(f, width: 104, height: 78, fit: BoxFit.cover),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 4),
                  const Text('Las piezas, tal y como las fotografió el taller o tú.',
                      style: TextStyle(fontSize: 12, color: Tono.tintaSuave)),
                ],
                if (d.nota.isNotEmpty) ...[
                  const TituloSeccion('Notas'),
                  Tarjeta(child: Text(d.nota, style: const TextStyle(height: 1.45))),
                ],
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => PantallaEditarIntervencion(editar: d))),
                  child: const Text('Corregir estos datos'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _lineaDesglose(Linea l) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.concepto.isEmpty ? '(sin concepto)' : l.concepto),
                  if (l.tipo.isNotEmpty)
                    Text(tiposMantenimiento[l.tipo] ?? l.tipo,
                        style: const TextStyle(fontSize: 12, color: Tono.tintaSuave)),
                ],
              ),
            ),
            Text(enEuros(l.importe),
                style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
          ],
        ),
      );
}

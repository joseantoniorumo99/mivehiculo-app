/// LAS CITAS del coche en uso: las que vienen y las pasadas, con lo que el
/// taller ha contestado.
///
/// Cuando el taller acepta, aquí se ve su respuesta: cuánto tardará, cómo se
/// paga, un presupuesto aproximado y lo que haya querido decir. Cuando el
/// coche ya pasó por allí y el taller manda el INFORME, se ve entero y un
/// solo botón lo pasa al diario como una intervención con su desglose: el
/// informe del taller es la mejor factura que puede tener el expediente.
library;

import 'dart:convert' show base64Decode;

import 'package:flutter/material.dart';

import '../datos/mantenimiento.dart';
import '../datos/modelo.dart';
import '../datos/nube.dart';
import '../estado.dart';
import '../tema.dart';
import 'elegir_taller.dart';

class PantallaCitas extends StatelessWidget {
  const PantallaCitas({super.key});

  @override
  Widget build(BuildContext context) {
    final almacen = context.almacen;
    return Scaffold(
      appBar: AppBar(title: const Text('Citas')),
      floatingActionButton: almacen.coche == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const PantallaElegirTaller())),
              icon: const Icon(Icons.event_available),
              label: const Text('Pedir cita'),
            ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: almacen,
          builder: (context, _) {
            final lista = almacen.citasDelCoche;
            if (lista.isEmpty) {
              return const Vacio(
                icono: Icons.event_outlined,
                titulo: 'Ninguna cita',
                texto: 'Pulsa «Pedir cita»: los talleres que ya conoces salen primero, '
                    'y el mapa para encontrar otro. Con cuenta, el taller la recibe y '
                    'te avisamos cuando conteste.',
              );
            }
            final hoy = hoyIso();
            final proximas = lista
                .where((c) => c.fecha.compareTo(hoy) >= 0 && c.estado != EstadoCita.cancelada && !c.hayInforme)
                .toList()
                .reversed
                .toList();
            final pasadas = lista
                .where((c) => c.fecha.compareTo(hoy) < 0 || c.estado == EstadoCita.cancelada || c.hayInforme)
                .toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
              children: [
                if (proximas.isNotEmpty) const TituloSeccion('Próximas'),
                ...proximas.map((c) => _fila(context, c, activa: true)),
                if (pasadas.isNotEmpty) const TituloSeccion('Anteriores'),
                ...pasadas.map((c) => _fila(context, c, activa: false)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _fila(BuildContext context, Cita c, {required bool activa}) {
    final tono = switch (c.estado) {
      EstadoCita.confirmada => TonoEstado.calma,
      EstadoCita.rechazada || EstadoCita.cancelada => TonoEstado.neutro,
      EstadoCita.hecha => TonoEstado.calma,
      EstadoCita.solicitada => TonoEstado.atencion,
    };
    final chip = !c.enviada
        ? 'Sin confirmar'
        : (c.hayInforme ? 'Con informe' : nombreEstadoCita[c.estado]!);
    final sePuedeCancelar = activa &&
        c.estado != EstadoCita.rechazada &&
        c.estado != EstadoCita.hecha;

    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(c.lugarNombre.isEmpty ? 'Taller' : c.lugarNombre,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              ChipEstado(chip, tono: c.hayInforme ? TonoEstado.accion : tono),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              '${fechaCorta(c.fecha)}${c.hora.isNotEmpty ? ' · ${c.hora}' : ''}'
              '${c.servicio.isNotEmpty ? ' · ${c.servicio}' : ''}',
              style: const TextStyle(color: Tono.tintaSuave)),
          if (c.nota.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(c.nota, style: const TextStyle(height: 1.4)),
            ),

          // Lo que contestó el taller al aceptar.
          if (c.estado == EstadoCita.confirmada && (c.textoRespuesta.isNotEmpty || c.mensaje.isNotEmpty))
            _bloque(
              tono: TonoEstado.calma,
              children: [
                if (c.textoRespuesta.isNotEmpty)
                  Text(c.textoRespuesta,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Tono.tealTinta)),
                if (c.mensaje.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: c.textoRespuesta.isNotEmpty ? 4 : 0),
                    child: Text('«${c.mensaje}»', style: const TextStyle(height: 1.4)),
                  ),
              ],
            ),

          // Por qué no puede.
          if (c.estado == EstadoCita.rechazada)
            _bloque(
              tono: TonoEstado.atencion,
              children: [
                Text(c.motivo.isNotEmpty ? c.motivo : 'El taller no puede atenderte ese día.',
                    style: const TextStyle(height: 1.4)),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PantallaElegirTaller())),
                    child: const Text('Pedir otra fecha'),
                  ),
                ),
              ],
            ),

          // El informe del taller.
          if (c.hayInforme) _informe(context, c),

          if (!c.enviada && activa)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Anotada en tu móvil. Confírmala llamando al taller.',
                  style: TextStyle(fontSize: 12, color: Tono.naranjaTinta)),
            ),
          if (c.enviada && activa && c.estado == EstadoCita.solicitada)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Enviada al taller. Te avisaremos cuando conteste.',
                  style: TextStyle(fontSize: 12, color: Tono.tintaSuave)),
            ),
          if (sePuedeCancelar)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(foregroundColor: Tono.rojoTinta),
                onPressed: () async {
                  final ok = await confirmar(context,
                      titulo: 'Cancelar la cita',
                      texto: 'Se marca como cancelada. Si ya la confirmaste por teléfono, avisa al taller.',
                      accion: 'Cancelar la cita');
                  if (ok && context.mounted) await context.almacen.cancelarCita(c.id);
                },
                child: const Text('Cancelar'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bloque({required TonoEstado tono, required List<Widget> children}) {
    final (fondo, borde) = switch (tono) {
      TonoEstado.calma => (Tono.tealFilm, Tono.tealTinta),
      TonoEstado.accion => (Tono.azulFilm, Tono.azul),
      _ => (Tono.naranjaFilm, Tono.naranjaRegla),
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fondo,
        border: Border.all(color: borde.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _informe(BuildContext context, Cita c) {
    final lineas = c.informeLineas;
    final total = c.informeTotal;
    return _bloque(
      tono: TonoEstado.accion,
      children: [
        const Row(
          children: [
            Icon(Icons.description_outlined, size: 18, color: Tono.azulTinta),
            SizedBox(width: 6),
            Expanded(
              child: Text('Informe del taller',
                  style: TextStyle(fontWeight: FontWeight.w700, color: Tono.azulTinta)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(c.informeTitulo.isNotEmpty ? c.informeTitulo : c.servicio,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        Text(
          [
            if (c.informeFecha.isNotEmpty) fechaCorta(c.informeFecha),
            if (c.informeKm != null) '${conMiles(c.informeKm!)} km',
          ].join(' · '),
          style: const TextStyle(fontSize: 12, color: Tono.tintaSuave),
        ),
        if (lineas.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...lineas.map((l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(l.concepto.isEmpty ? '(sin concepto)' : l.concepto)),
                    Text(enEuros(l.importe),
                        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                  ],
                ),
              )),
          const Text('Base imponible por concepto; el total lleva el IVA.',
              style: TextStyle(fontSize: 11, color: Tono.tintaSuave)),
        ],
        if (total != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Expanded(child: Text('Total cobrado', style: TextStyle(fontWeight: FontWeight.w700))),
              Text(enEuros(total),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
        ],
        if (c.informeNotas.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(c.informeNotas, style: const TextStyle(height: 1.4)),
        ],
        if (c.informeFotos.isNotEmpty) ...[
          const SizedBox(height: 10),
          _fotosInforme(context, c),
        ],
        const SizedBox(height: 8),
        if (c.informeAnadido)
          const Row(
            children: [
              Icon(Icons.check_circle, size: 18, color: Tono.tealTinta),
              SizedBox(width: 6),
              Text('Ya está en tu diario', style: TextStyle(color: Tono.tealTinta, fontWeight: FontWeight.w600)),
            ],
          )
        else
          FilledButton.icon(
            onPressed: () async {
              final almacen = context.almacen;
              final nube = context.nube;
              // Las fotos del taller se bajan a la carpeta de la app: así el
              // diario las conserva aunque el servidor las pierda algún día.
              final fotos = c.informeFotos.isEmpty
                  ? const <String>[]
                  : await nube.bajarFotosDelInforme(almacen, c);
              await almacen.guardarIntervencion(c.informeComoIntervencion(fotos: fotos));
              c.informeAnadido = true;
              await almacen.guardarCita(c);
              if (context.mounted) {
                avisar(context,
                    'Añadido al diario con su desglose${fotos.isNotEmpty ? ' y ${fotos.length == 1 ? 'su foto' : '${fotos.length} fotos'}' : ''}.');
              }
            },
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Añadir al diario'),
          ),
      ],
    );
  }

  /// Las fotos de las piezas, en miniatura; tocar una la abre entera.
  Widget _fotosInforme(BuildContext context, Cita c) {
    final bajadas = c.fotosBajadas;
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: c.informeFotos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = c.informeFotos[i];
          final local = bajadas[f.id.isNotEmpty ? f.id : f.datos.hashCode.toString()];
          final fichero = local == null ? null : context.almacen.ficheroFactura(local);
          Widget imagen;
          if (fichero != null) {
            imagen = Image.file(fichero, fit: BoxFit.cover);
          } else if (f.id.isNotEmpty) {
            imagen = Image.network(
              Nube.urlFotoInforme(f.id),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(
                  color: Tono.suelo, child: Icon(Icons.broken_image_outlined, color: Tono.tintaSuave)),
            );
          } else {
            final coma = f.datos.indexOf(',');
            imagen = coma < 0
                ? const SizedBox()
                : Image.memory(base64Decode(f.datos.substring(coma + 1)), fit: BoxFit.cover);
          }
          return GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => Dialog(
                insetPadding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: InteractiveViewer(child: imagen)),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(f.titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(width: 96, height: 72, child: imagen),
                ),
                const SizedBox(height: 3),
                Text(f.titulo, style: const TextStyle(fontSize: 11, color: Tono.tintaSuave)),
              ],
            ),
          );
        },
      ),
    );
  }
}

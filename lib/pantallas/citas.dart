/// LAS CITAS del coche en uso: las que vienen y las pasadas.
library;

import 'package:flutter/material.dart';

import '../datos/mantenimiento.dart';
import '../datos/modelo.dart';
import '../estado.dart';
import '../tema.dart';

class PantallaCitas extends StatelessWidget {
  const PantallaCitas({super.key});

  @override
  Widget build(BuildContext context) {
    final almacen = context.almacen;
    return Scaffold(
      appBar: AppBar(title: const Text('Citas')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: almacen,
          builder: (context, _) {
            final lista = almacen.citasDelCoche;
            if (lista.isEmpty) {
              return const Vacio(
                icono: Icons.event_outlined,
                titulo: 'Ninguna cita',
                texto: 'Desde la ficha de un taller en el mapa puedes anotar una. '
                    'Por ahora la cita se guarda aquí y se confirma llamando.',
              );
            }
            final hoy = hoyIso();
            final proximas = lista.where((c) => c.fecha.compareTo(hoy) >= 0 && c.estado != EstadoCita.cancelada).toList().reversed.toList();
            final pasadas = lista.where((c) => c.fecha.compareTo(hoy) < 0 || c.estado == EstadoCita.cancelada).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
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
              ChipEstado(
                  c.enviada ? nombreEstadoCita[c.estado]! : 'Sin confirmar',
                  tono: tono),
            ],
          ),
          const SizedBox(height: 4),
          Text('${fechaCorta(c.fecha)} · ${c.hora}${c.servicio.isNotEmpty ? ' · ${c.servicio}' : ''}',
              style: const TextStyle(color: Tono.tintaSuave)),
          if (c.nota.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(c.nota, style: const TextStyle(height: 1.4)),
            ),
          if (!c.enviada && activa)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Anotada en tu móvil. Confírmala llamando al taller.',
                  style: TextStyle(fontSize: 12, color: Tono.naranjaTinta)),
            ),
          if (activa)
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
}

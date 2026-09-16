/// LAS LECTURAS DEL OBD, aparte del diario.
///
/// El diario es para lo que se le HACE al coche: mecánica, siniestros, ITV.
/// Esto es lo que el coche DICE de sí mismo cada vez que la app lo lee, y
/// vale como prueba de por dónde iba el cuentakilómetros y qué códigos había
/// ese día. Mezclarlas enterraría las facturas entre docenas de "35 °C".
///
/// Se leen SOLAS al abrir la app si el lector está a mano —o sea, si estás
/// en el coche con el contacto dado, porque el lector se alimenta del propio
/// conector—, y se guardan aquí sin preguntar. Eso es "saber cuándo
/// conduces" sin dejar nada escuchando en segundo plano.
library;

import 'package:flutter/material.dart';

import '../datos/mantenimiento.dart';
import '../datos/modelo.dart';
import '../estado.dart';
import '../tema.dart';

class PantallaLecturas extends StatelessWidget {
  const PantallaLecturas({super.key});

  @override
  Widget build(BuildContext context) {
    final almacen = context.almacen;
    return Scaffold(
      appBar: AppBar(title: const Text('Lecturas del OBD')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: almacen,
          builder: (context, _) {
            final lista = almacen.lecturasDelCoche;
            if (lista.isEmpty) {
              return const Vacio(
                icono: Icons.monitor_heart_outlined,
                titulo: 'Ninguna lectura guardada',
                texto: 'Cada vez que abres la app con el coche en contacto y el '
                    'lector puesto, se lee sola y se guarda aquí. También puedes '
                    'guardar una a mano desde la pestaña OBD.',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              itemCount: lista.length,
              itemBuilder: (context, i) => _fila(context, lista[i]),
            );
          },
        ),
      ),
    );
  }

  Widget _fila(BuildContext context, LecturaGuardada l) {
    final cuando = DateTime.tryParse(l.cuando)?.toLocal();
    final hora = cuando == null
        ? ''
        : '${cuando.hour}:${cuando.minute.toString().padLeft(2, '0')}';
    final principales = l.valores.entries.take(4).toList();
    return Tarjeta(
      onTap: () => _verTodo(context, l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${fechaCorta(l.cuando)}${hora.isNotEmpty ? ' · $hora' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (l.codigos.isEmpty)
                const ChipEstado('Sin códigos', tono: TonoEstado.calma)
              else
                ChipEstado('${l.codigos.length} código${l.codigos.length > 1 ? 's' : ''}',
                    tono: TonoEstado.urgente),
            ],
          ),
          if (l.km != null)
            Text('${conMiles(l.km!)} km',
                style: const TextStyle(fontSize: 12, color: Tono.tintaSuave)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: principales
                .map((e) => Text.rich(TextSpan(children: [
                      TextSpan(
                          text: '${e.key}: ',
                          style: const TextStyle(fontSize: 12, color: Tono.tintaSuave)),
                      TextSpan(
                          text: e.value,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ])))
                .toList(),
          ),
          if (l.valores.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('y ${l.valores.length - 4} más',
                  style: const TextStyle(fontSize: 12, color: Tono.azulTinta)),
            ),
        ],
      ),
    );
  }

  void _verTodo(BuildContext context, LecturaGuardada l) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (c, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Text('Lectura del ${fechaCorta(l.cuando)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (l.codigos.isNotEmpty) ...[
              const Text('Códigos de avería', style: TextStyle(fontWeight: FontWeight.w700)),
              ...l.codigos.map((c) => Text(c, style: const TextStyle(fontFamily: 'monospace'))),
              const SizedBox(height: 10),
            ],
            ...l.valores.entries.map((e) => FilaDato(e.key, e.value)),
            const SizedBox(height: 16),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Tono.rojoTinta),
              onPressed: () async {
                final ok = await confirmar(context,
                    titulo: 'Borrar esta lectura',
                    texto: 'Se quita de la lista. No afecta al diario.');
                if (!ok || !context.mounted) return;
                await context.almacen.borrarLectura(l.id);
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('Borrar esta lectura'),
            ),
          ],
        ),
      ),
    );
  }
}

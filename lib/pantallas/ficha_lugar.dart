/// LA FICHA DE UN SITIO: qué es, dónde, cuándo abre, qué hace, y las tres
/// acciones que importan: llamar, cómo llegar, pedir cita.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../lugares/lugares.dart';
import '../tema.dart';
import 'pedir_cita.dart';

class PantallaFichaLugar extends StatelessWidget {
  final Lugar lugar;
  final double distancia;

  /// Si la distancia es desde la persona o desde el centro del mapa. Se dice,
  /// porque "a 3 km" desde un punto que no es uno no vale para decidir.
  final bool distanciaDesdeTi;
  final String? servicio;

  const PantallaFichaLugar({
    super.key,
    required this.lugar,
    required this.distancia,
    required this.distanciaDesdeTi,
    this.servicio,
  });

  Future<void> _abrir(BuildContext context, Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) avisar(context, 'No hay ninguna app que abra esto.');
    } catch (e) {
      if (context.mounted) avisar(context, 'No se ha podido abrir: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = lugar.estadoAhora();
    final esTaller = lugar.tipo == TipoLugar.taller;
    return Scaffold(
      appBar: AppBar(title: Text(nombreTipoLugar[lugar.tipo]!.replaceAll(RegExp(r's$'), ''))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(lugar.nombre,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            const SizedBox(height: 4),
            Text(
              '${textoDistancia(distancia)}${distanciaDesdeTi ? '' : ' del centro del mapa'}'
              '${lugar.direccion.isNotEmpty ? ' · ${lugar.direccion}' : ''}',
              style: const TextStyle(color: Tono.tintaSuave),
            ),
            if (estado != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ChipEstado(estado,
                    tono: estado.startsWith('Abierto') ? TonoEstado.calma : TonoEstado.atencion),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (lugar.telefono.isNotEmpty) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _abrir(context,
                          Uri(scheme: 'tel', path: lugar.telefono.replaceAll(RegExp(r'[^\d+]'), ''))),
                      icon: const Icon(Icons.call),
                      label: const Text('Llamar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _abrir(
                        context,
                        Uri.parse(
                            'https://www.google.com/maps/dir/?api=1&destination=${lugar.lat},${lugar.lon}')),
                    icon: const Icon(Icons.directions),
                    label: const Text('Cómo llegar'),
                  ),
                ),
              ],
            ),
            if (esTaller) ...[
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PantallaPedirCita(lugar: lugar, servicio: servicio))),
                icon: const Icon(Icons.event_available),
                label: const Text('Pedir cita'),
              ),
            ],
            const TituloSeccion('Datos'),
            Tarjeta(
              child: Column(
                children: [
                  if (lugar.telefono.isNotEmpty) FilaDato('Teléfono', lugar.telefono),
                  if (lugar.web.isNotEmpty)
                    InkWell(
                      onTap: () => _abrir(context, Uri.parse(lugar.web)),
                      child: FilaDato('Web', lugar.web),
                    ),
                  if (lugar.direccion.isNotEmpty) FilaDato('Dirección', lugar.direccion),
                  if (lugar.horario != null)
                    ..._diasHorario(lugar.horario!)
                  else if (lugar.horarioTexto.isNotEmpty)
                    FilaDato('Horario', lugar.horarioTexto)
                  else
                    const FilaDato('Horario', 'No consta'),
                ],
              ),
            ),
            if (lugar.servicios.isNotEmpty) ...[
              const TituloSeccion('Servicios que declara'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: lugar.servicios
                    .map((s) => ChipEstado(s,
                        tono: servicio != null && s.toLowerCase() == servicio!.toLowerCase()
                            ? TonoEstado.accion
                            : TonoEstado.neutro))
                    .toList(),
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'Datos de OpenStreetMap, aportados por voluntarios. Si algo no cuadra, '
              'puede que el sitio haya cambiado y el mapa no.',
              style: TextStyle(fontSize: 12, color: Tono.tintaSuave),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _diasHorario(List<List<List<int>>> h) {
    const dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
    String hora(int m) => m % 60 == 0 ? '${m ~/ 60}:00' : '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
    final hoy = DateTime.now().weekday - 1;
    return List.generate(7, (i) {
      final tramos = h[i];
      final texto = tramos.isEmpty ? 'Cerrado' : tramos.map((t) => '${hora(t[0])}–${hora(t[1])}').join(', ');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 128,
              child: Text(dias[i],
                  style: TextStyle(
                      color: Tono.tintaSuave,
                      fontWeight: i == hoy ? FontWeight.w700 : FontWeight.w400)),
            ),
            Expanded(
              child: Text(texto,
                  style: TextStyle(fontWeight: i == hoy ? FontWeight.w700 : FontWeight.w500)),
            ),
          ],
        ),
      );
    });
  }
}

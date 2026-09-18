/// LA FICHA DE UN SITIO: qué es, dónde, cuándo abre, qué hace, y las tres
/// acciones que importan: llamar, cómo llegar, pedir cita.
///
/// Si el taller publicó su ficha desde el panel, lo que él escribió manda:
/// sus servicios con tiempo aproximado y precio de partida, y lo que ofrece
/// además (recogida a domicilio, coche de sustitución…). Lo de OpenStreetMap
/// queda para los que no lo han hecho, y se dice de dónde sale cada cosa.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../datos/mantenimiento.dart' show enEuros, fechaCorta;
import '../estado.dart';
import '../lugares/lugares.dart';
import '../tema.dart';
import 'pedir_cita.dart';

class PantallaFichaLugar extends StatefulWidget {
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

  @override
  State<PantallaFichaLugar> createState() => _PantallaFichaLugarState();
}

class _PantallaFichaLugarState extends State<PantallaFichaLugar> {
  FichaTaller? _publicada;

  Lugar get lugar => widget.lugar;
  double get distancia => widget.distancia;
  bool get distanciaDesdeTi => widget.distanciaDesdeTi;
  String? get servicio => widget.servicio;

  @override
  void initState() {
    super.initState();
    if (lugar.esTaller) {
      context.nube.fichaDeTaller(lugar.id).then((f) {
        if (mounted && f != null) setState(() => _publicada = f);
      });
    }
  }

  /// Al pedir cita, los servicios que publicó el taller mandan.
  Lugar get _lugarParaCita {
    final p = _publicada;
    if (p == null || p.servicios.isEmpty) return lugar;
    return lugar.conServicios(p.servicios.map((s) => s.nombre).toList());
  }

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
                        builder: (_) => PantallaPedirCita(lugar: _lugarParaCita, servicio: servicio))),
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
            if (_publicada != null) ..._loQuePublica(_publicada!),
            if (_publicada == null && lugar.servicios.isNotEmpty) ...[
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

  /// Lo que el taller publicó él mismo: servicios con tiempo y precio, y
  /// extras. Se distingue a la vista de lo de OpenStreetMap.
  List<Widget> _loQuePublica(FichaTaller f) {
    final buscado = servicio?.toLowerCase();
    return [
      TituloSeccion('Lo que publica el taller',
          accion: f.actualizado.length >= 10
              ? Text(fechaCorta(f.actualizado.substring(0, 10)),
                  style: const TextStyle(fontSize: 12, color: Tono.tintaSuave))
              : null),
      if (f.servicios.isNotEmpty)
        Tarjeta(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: f.servicios.map((s) {
              final destacado = buscado != null && s.nombre.toLowerCase() == buscado;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.nombre,
                              style: TextStyle(
                                  fontWeight: destacado ? FontWeight.w800 : FontWeight.w600,
                                  color: destacado ? Tono.azulTinta : Tono.tinta)),
                          if (s.tiempo.isNotEmpty)
                            Text('Tiempo aproximado: ${s.tiempo}',
                                style: const TextStyle(fontSize: 12, color: Tono.tintaSuave)),
                        ],
                      ),
                    ),
                    Text(
                      s.precio != null ? 'desde ${enEuros(s.precio)}' : 'sin precio',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: s.precio != null ? Tono.tinta : Tono.tintaSuave,
                          fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      if (f.extras.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Además', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: f.extras.map((e) => ChipEstado(e, tono: TonoEstado.accion)).toList(),
        ),
        const SizedBox(height: 8),
      ],
      const Text(
        'Publicado por el propio taller desde su panel. Los precios son de partida.',
        style: TextStyle(fontSize: 12, color: Tono.tintaSuave),
      ),
    ];
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

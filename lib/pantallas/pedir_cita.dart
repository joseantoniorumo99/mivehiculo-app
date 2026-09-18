/// PEDIR CITA EN UN TALLER.
///
/// EN ESTA VERSIÓN LA CITA NO LE LLEGA AL TALLER, y la pantalla lo dice con
/// todas las letras antes del botón: queda anotada en tu diario de citas y
/// hay que llamar para confirmarla —con el teléfono a un toque—. Un botón
/// que promete avisar a un taller y no avisa a nadie es peor que no tenerlo,
/// porque el dueño se presenta allí el martes a las diez.
///
/// Cuando exista el lado del taller (la función de citas del servidor), esta
/// misma pantalla la mandará y el aviso cambiará. El modelo ya lo contempla:
/// `Cita.enviada`.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../datos/mantenimiento.dart';
import '../datos/modelo.dart';
import '../estado.dart';
import '../lugares/lugares.dart';
import '../tema.dart';

class PantallaPedirCita extends StatefulWidget {
  final Lugar lugar;
  final String? servicio;
  const PantallaPedirCita({super.key, required this.lugar, this.servicio});

  @override
  State<PantallaPedirCita> createState() => _PantallaPedirCitaState();
}

class _PantallaPedirCitaState extends State<PantallaPedirCita> {
  late String _servicio;
  late DateTime _fecha;
  String _hora = '10:00';
  final _nota = TextEditingController();
  bool _guardando = false;

  static const _horas = [
    '08:00', '08:30', '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
    '12:00', '12:30', '13:00', '16:00', '16:30', '17:00', '17:30', '18:00',
    '18:30', '19:00',
  ];

  List<String> get _servicios {
    final lista = [...widget.lugar.servicios];
    if (widget.servicio != null && !lista.contains(widget.servicio)) {
      lista.insert(0, widget.servicio!);
    }
    if (lista.isEmpty) lista.add('Mecánica general');
    if (!lista.contains('Otra cosa')) lista.add('Otra cosa');
    return lista;
  }

  @override
  void initState() {
    super.initState();
    _servicio = widget.servicio ?? _servicios.first;
    // Mañana, o el lunes si mañana es fin de semana
    var f = DateTime.now().add(const Duration(days: 1));
    while (f.weekday > 5) {
      f = f.add(const Duration(days: 1));
    }
    _fecha = f;
  }

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final f = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 120)),
      locale: const Locale('es'),
    );
    if (f != null) setState(() => _fecha = f);
  }

  /// Se guarda en el móvil SIEMPRE, y luego se intenta mandar al taller si
  /// hay cuenta. Si la función del servidor no está o no hay red, la cita se
  /// queda anotada como antes y la pantalla lo dice: mejor media cita que un
  /// botón que se traga lo que escribiste.
  Future<void> _guardar() async {
    final almacen = context.almacen;
    final nube = context.nube;
    final coche = almacen.coche;
    if (coche == null) return;
    setState(() => _guardando = true);
    final cita = Cita(
      vehiculoId: coche.id,
      lugarId: widget.lugar.id,
      lugarNombre: widget.lugar.nombre,
      servicio: _servicio,
      fecha: hoyIso(_fecha),
      hora: _hora,
      nota: _nota.text.trim(),
      enviada: false,
    );
    await almacen.guardarCita(cita);

    var mensaje = 'Cita anotada. Llama al taller para confirmarla.';
    if (nube.conSesion) {
      final vehiculo = '${coche.nombre}${coche.matricula.isNotEmpty ? ' (${coche.matricula})' : ''}';
      final r = await nube.enviarCita(cita, vehiculo);
      if (r.remotoId != null) {
        cita
          ..enviada = true
          ..remotoId = r.remotoId!;
        await almacen.guardarCita(cita);
        mensaje = 'Cita enviada al taller. Te avisaremos cuando conteste.';
      } else if (r.error != null) {
        mensaje = 'Anotada en tu móvil, pero no enviada: ${r.error}';
      }
    }
    if (!mounted) return;
    avisar(context, mensaje);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tel = widget.lugar.telefono;
    final servicios = _servicios;
    if (!servicios.contains(_servicio)) _servicio = servicios.first;
    return Scaffold(
      appBar: AppBar(title: const Text('Pedir cita')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(widget.lugar.nombre,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            if (widget.lugar.direccion.isNotEmpty)
              Text(widget.lugar.direccion, style: const TextStyle(color: Tono.tintaSuave)),
            const SizedBox(height: 16),
            Recuadro(
              context.nube.conSesion
                  ? 'La cita se envía al taller a través de tu cuenta.'
                  : 'Esta cita se anota en tu móvil; al taller no le llega.',
              consejo: context.nube.conSesion
                  ? 'Si el taller todavía no usa la app, se queda anotada aquí y '
                      'conviene llamar para confirmarla.'
                  : tel.isNotEmpty
                      ? 'Llama para confirmarla. Con cuenta, se enviaría desde aquí.'
                      : 'Este taller no tiene teléfono en el mapa: confírmala en persona. '
                          'Con cuenta, se enviaría desde aquí.',
              tono: context.nube.conSesion ? TonoEstado.accion : TonoEstado.atencion,
              accion: tel.isEmpty
                  ? null
                  : TextButton.icon(
                      onPressed: () => launchUrl(
                          Uri(scheme: 'tel', path: tel.replaceAll(RegExp(r'[^\d+]'), '')),
                          mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.call, size: 18),
                      label: Text('Llamar al $tel'),
                    ),
            ),
            DropdownButtonFormField<String>(
              initialValue: _servicio,
              decoration: const InputDecoration(labelText: 'Para qué'),
              items: servicios.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _servicio = v ?? _servicio),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _elegirFecha,
                    borderRadius: BorderRadius.circular(14),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Día', suffixIcon: Icon(Icons.calendar_today, size: 18)),
                      child: Text(fechaCorta(hoyIso(_fecha))),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _hora,
                    decoration: const InputDecoration(labelText: 'Hora'),
                    items: _horas.map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
                    onChanged: (v) => setState(() => _hora = v ?? _hora),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nota,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Qué le pasa al coche (opcional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: const Text('Anotar la cita'),
            ),
          ],
        ),
      ),
    );
  }
}

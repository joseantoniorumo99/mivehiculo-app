/// AJUSTES DE LA LECTURA AUTOMÁTICA: cuándo lee la app sola.
///
/// Dos disparadores, los dos apagados de fábrica. Se explica lo que cuesta
/// cada uno en batería, porque es la única forma honesta de dejar elegir:
///
/// · Al conectarse al Bluetooth del coche: no cuesta nada mientras no se
///   conduce. Es el bueno.
/// · Cada X minutos: unos segundos de radio por intento, esté el coche donde
///   esté. Es el de "por si acaso".
library;

import 'package:flutter/material.dart';

import '../obd/enlace_classic.dart';
import '../obd/lector_recordado.dart';
import '../obd/lectura_fondo.dart';
import '../obd/transporte_bluetooth.dart';
import '../tema.dart';

class PantallaLecturaAutomatica extends StatefulWidget {
  const PantallaLecturaAutomatica({super.key});
  @override
  State<PantallaLecturaAutomatica> createState() => _PantallaLecturaAutomaticaState();
}

class _PantallaLecturaAutomaticaState extends State<PantallaLecturaAutomatica> {
  ({String direccion, String nombre})? _coche;
  ({String direccion, String nombre})? _lector;
  int _cadaMinutos = 0;
  DateTime? _ultima;
  List<AparatoBluetooth> _emparejados = [];
  String? _error;
  bool _cargando = true;

  static const _opciones = [0, 30, 60, 120];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    _coche = await AjustesLecturaAutomatica.aparatoCoche();
    _lector = await LectorRecordado.leer();
    _cadaMinutos = await AjustesLecturaAutomatica.cadaMinutos();
    _ultima = await AjustesLecturaAutomatica.ultimaLecturaDeFondo();
    try {
      _emparejados = await Bluetooth().emparejados();
    } on ErrorBluetooth catch (e) {
      _error = e.mensaje;
    } catch (e) {
      _error = 'No se han podido listar los aparatos: $e';
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _elegirCoche(AparatoBluetooth? a) async {
    await AjustesLecturaAutomatica.ponerAparatoCoche(a?.direccion, a?.nombre);
    setState(() => _coche = a == null ? null : (direccion: a.direccion, nombre: a.nombre));
  }

  Future<void> _elegirCada(int minutos) async {
    await AjustesLecturaAutomatica.ponerCadaMinutos(minutos);
    setState(() => _cadaMinutos = minutos);
  }

  @override
  Widget build(BuildContext context) {
    // El lector no es el coche: de la lista se quita el propio lector OBD,
    // que no se "conecta" solo a nada.
    final candidatos = _emparejados.where((a) => a.direccion != _lector?.direccion).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Lectura automática')),
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  if (_lector == null)
                    const Recuadro(
                      'Primero hay que leer el coche una vez a mano.',
                      consejo: 'En la pestaña OBD, «Conectar con mi lector». Así la app '
                          'sabe con qué lector hablar cuando lo haga sola.',
                      tono: TonoEstado.atencion,
                    )
                  else
                    Recuadro('Lector: ${_lector!.nombre}', tono: TonoEstado.calma),
                  if (_error != null) Recuadro(_error!, tono: TonoEstado.atencion),
                  const TituloSeccion('Cuando el móvil se conecte al coche'),
                  const Text(
                    'Elige el Bluetooth del coche (el manos libres o la radio). Cuando el '
                    'móvil se conecte a él, la app espera un minuto y lee el OBD. No gasta '
                    'batería mientras no conduces: no hay nada vigilando.',
                    style: TextStyle(color: Tono.tintaSuave, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  if (candidatos.isEmpty)
                    const Text('No hay más aparatos emparejados en este móvil.',
                        style: TextStyle(color: Tono.tintaSuave))
                  else
                    ...candidatos.map((a) => RadioListTile<String>(
                          value: a.direccion,
                          // ignore: deprecated_member_use
                          groupValue: _coche?.direccion,
                          title: Text(a.nombre),
                          subtitle: Text(a.direccion),
                          contentPadding: EdgeInsets.zero,
                          // ignore: deprecated_member_use
                          onChanged: (_) => _elegirCoche(a),
                        )),
                  if (_coche != null)
                    TextButton(
                      onPressed: () => _elegirCoche(null),
                      child: const Text('Desactivar'),
                    ),
                  const TituloSeccion('Cada cierto tiempo'),
                  const Text(
                    'Por si el coche no tiene Bluetooth. Cada intento enciende la radio '
                    'unos segundos aunque el coche esté apagado, así que gasta algo de '
                    'batería. Android no baja de 15 minutos.',
                    style: TextStyle(color: Tono.tintaSuave, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    segments: _opciones
                        .map((m) => ButtonSegment(
                              value: m,
                              label: Text(m == 0 ? 'No' : m < 60 ? '$m min' : '${m ~/ 60} h'),
                            ))
                        .toList(),
                    selected: {_cadaMinutos},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => _elegirCada(s.first),
                  ),
                  const SizedBox(height: 18),
                  Tarjeta(
                    color: Tono.sueloAlto,
                    child: Text(
                      _ultima == null
                          ? 'Todavía no se ha hecho ninguna lectura automática.'
                          : 'Última lectura automática: ${_ultima!.toLocal().day}/${_ultima!.toLocal().month} '
                              'a las ${_ultima!.toLocal().hour}:${_ultima!.toLocal().minute.toString().padLeft(2, '0')}. '
                              'Están en Diario → Lecturas del OBD.',
                      style: const TextStyle(color: Tono.tintaSuave, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Las lecturas automáticas no emparejan ni preguntan nada: si el '
                    'lector no contesta en unos segundos, lo dejan. Y nunca se repiten '
                    'con menos de diez minutos entre una y otra.',
                    style: TextStyle(fontSize: 12, color: Tono.tintaSuave),
                  ),
                ],
              ),
      ),
    );
  }
}

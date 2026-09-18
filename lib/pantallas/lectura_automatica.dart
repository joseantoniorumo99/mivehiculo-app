/// AJUSTES DE LA LECTURA AUTOMÁTICA: cuándo lee la app sola.
///
/// Dos disparadores, los dos apagados de fábrica. Se explica lo que cuesta
/// cada uno en batería, porque es la única forma honesta de dejar elegir:
///
/// · Al conectarse al Bluetooth del coche: no cuesta nada mientras no se
///   conduce. Es el bueno.
/// · Cada X minutos: unos segundos de radio por intento, esté el coche donde
///   esté. Es el de "por si acaso".
///
/// Y abajo, EL REGISTRO: lo que el segundo plano ha hecho, línea a línea, y
/// un botón para probarlo sin coche. Sin esto, "no me funcionó" no se puede
/// convertir en un fallo concreto.
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

class _PantallaLecturaAutomaticaState extends State<PantallaLecturaAutomatica>
    with WidgetsBindingObserver {
  ({String direccion, String nombre})? _coche;
  ({String direccion, String nombre})? _lector;
  int _cadaMinutos = 0;
  DateTime? _ultima;
  List<AparatoBluetooth> _emparejados = [];
  List<String> _registro = [];
  String? _error;
  bool _cargando = true;

  static const _opciones = [0, 30, 60, 120];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver a la pantalla (después de la prueba, por ejemplo) se relee el
  /// registro: lo ha escrito otro proceso.
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _releerRegistro();
  }

  Future<void> _releerRegistro() async {
    final r = await RegistroFondo.leer();
    final u = await AjustesLecturaAutomatica.ultimaLecturaDeFondo();
    if (mounted) {
      setState(() {
        _registro = r;
        _ultima = u;
      });
    }
  }

  Future<void> _cargar() async {
    _coche = await AjustesLecturaAutomatica.aparatoCoche();
    _lector = await LectorRecordado.leer();
    _cadaMinutos = await AjustesLecturaAutomatica.cadaMinutos();
    _ultima = await AjustesLecturaAutomatica.ultimaLecturaDeFondo();
    _registro = await RegistroFondo.leer();
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
    await _releerRegistro();
  }

  Future<void> _elegirCada(int minutos) async {
    await AjustesLecturaAutomatica.ponerCadaMinutos(minutos);
    setState(() => _cadaMinutos = minutos);
    await _releerRegistro();
  }

  Future<void> _probar() async {
    await AjustesLecturaAutomatica.probarAhora();
    await _releerRegistro();
    if (!mounted) return;
    avisar(context,
        'Lectura encolada. Sal de la app (botón de inicio) y vuelve en medio minuto: el registro dirá qué pasó.');
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
                    'móvil se conecte a él, la app espera medio minuto y lee el OBD. No '
                    'gasta batería mientras no conduces: no hay nada vigilando.',
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
                  TituloSeccion(
                    'Registro',
                    accion: TextButton(
                      onPressed: _releerRegistro,
                      child: const Text('Actualizar'),
                    ),
                  ),
                  Text(
                    _ultima == null
                        ? 'Todavía no se ha hecho ninguna lectura automática.'
                        : 'Última lectura automática: ${_ultima!.toLocal().day}/${_ultima!.toLocal().month} '
                            'a las ${_ultima!.toLocal().hour}:${_ultima!.toLocal().minute.toString().padLeft(2, '0')}. '
                            'Están en Diario → Lecturas del OBD.',
                    style: const TextStyle(color: Tono.tintaSuave, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _lector == null ? null : _probar,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Probar el segundo plano ahora'),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Encola una lectura por el mismo camino que usan el Bluetooth del '
                    'coche y la periódica. Pulsa, sal de la app con el botón de inicio, '
                    'espera medio minuto y vuelve: aquí abajo saldrá qué ha pasado, '
                    'paso a paso. Con el coche en contacto guardará una lectura; sin '
                    'él dirá que el lector no contesta, que también es información.',
                    style: TextStyle(fontSize: 12, color: Tono.tintaSuave),
                  ),
                  const SizedBox(height: 12),
                  Tarjeta(
                    color: Tono.sueloAlto,
                    child: _registro.isEmpty
                        ? const Text('Nada apuntado todavía.',
                            style: TextStyle(color: Tono.tintaSuave))
                        : SelectableText(
                            _registro.join('\n'),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.5),
                          ),
                  ),
                  if (_registro.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        await RegistroFondo.borrar();
                        await _releerRegistro();
                      },
                      child: const Text('Vaciar el registro'),
                    ),
                ],
              ),
      ),
    );
  }
}

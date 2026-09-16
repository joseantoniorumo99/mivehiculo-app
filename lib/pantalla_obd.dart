/// La pantalla del OBD.
///
/// LA REGLA QUE GOBIERNA ESTA PANTALLA, y viene de un error que costó días en
/// la versión web: el botón principal habla con el LECTOR DE VERDAD. El
/// adaptador simulado existe —sirve para ver la pantalla sin coche— pero es
/// una salida lateral, sus resultados llevan un aviso a la vista, y NO se
/// pueden guardar en el historial del coche. Un botón que promete leer tu
/// coche y enseña un coche inventado no es una demo: es un dato falso, y unos
/// códigos inventados en el historial no se descubren hasta que vas a
/// venderlo, que es justo cuando el historial tiene que valer algo.
library;

import 'package:flutter/material.dart';

import 'obd/enlace_classic.dart';
import 'obd/protocolo.dart';
import 'obd/transporte_bluetooth.dart';

class PantallaObd extends StatefulWidget {
  const PantallaObd({super.key});
  @override
  State<PantallaObd> createState() => _PantallaObdState();
}

enum _Fase { inicio, eligiendo, leyendo, resultado }

class _PantallaObdState extends State<PantallaObd> {
  final _bt = Bluetooth();
  _Fase _fase = _Fase.inicio;
  String _paso = '';
  String? _error;
  List<AparatoBluetooth> _aparatos = [];
  List<Lectura> _lecturas = [];
  List<Averia> _averias = [];
  String? _vin;
  bool _esEjemplo = false;
  final List<String> _registro = [];

  void _apuntar(String linea) {
    _registro.add(linea);
    if (mounted) setState(() => _paso = linea);
  }

  Future<void> _elegirLector() async {
    setState(() {
      _fase = _Fase.eligiendo;
      _error = null;
      _aparatos = [];
    });
    try {
      final lista = await _bt.emparejados();
      if (!mounted) return;
      setState(() => _aparatos = lista);
      if (lista.isEmpty) {
        setState(() {
          _fase = _Fase.inicio;
          _error = 'No hay ningún aparato emparejado. Empareja el lector desde '
              'los ajustes de Bluetooth del móvil (el PIN suele ser 1234 o 0000) '
              'con el coche y el contacto dado: el lector se alimenta del propio '
              'conector, así que sin contacto ni se enciende.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.inicio;
        _error = 'No hemos podido ver los aparatos emparejados: $e';
      });
    }
  }

  Future<void> _leer(Transporte transporte, {required bool ejemplo}) async {
    setState(() {
      _fase = _Fase.leyendo;
      _esEjemplo = ejemplo;
      _registro.clear();
      _lecturas = [];
      _averias = [];
      _vin = null;
      _error = null;
    });

    try {
      /// El registro lo escribe la SESIÓN, no esta pantalla: así nada queda
      /// fuera aunque el protocolo mande comandos por su cuenta, y el volcado
      /// que se copia para mandármelo no puede mentir por omisión justo en la
      /// parte que explicaría por qué falta un dato.
      final sesion = Sesion(transporte, mirar: (que, texto) {
        if (que == 'envia') {
          _registro.add('> $texto');
        } else {
          _registro.add(
              '  ${texto.replaceAll(RegExp(r'[\r\n>]+'), ' ').trim()}');
        }
      });

      _apuntar('Preparando el adaptador…');
      if (!await sesion.iniciar()) {
        throw 'El adaptador no responde a los comandos.';
      }

      _apuntar('Leyendo datos del motor…');
      final lecturas = await sesion.leerTodo();

      _apuntar('Buscando códigos de avería…');
      final guardados = await sesion.leerCodigos(3);

      _apuntar('Pidiendo el bastidor…');
      final vin = await sesion.leerVin();

      /// Si el coche no contesta a NADA, decirlo. Una pantalla vacía parece un
      /// fallo de la app y casi siempre es que falta dar el contacto.
      if (!ejemplo && lecturas.isEmpty && guardados.isEmpty && vin == null) {
        throw 'El lector conecta pero el coche no contesta. ¿Está el contacto dado?';
      }

      if (!mounted) return;
      setState(() {
        _lecturas = lecturas;
        _averias = guardados;
        _vin = vin;
        _fase = _Fase.resultado;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.inicio;
        _error = e.toString();
      });
    } finally {
      await transporte.cerrar();
    }
  }

  Future<void> _conectarA(AparatoBluetooth a) async {
    setState(() {
      _fase = _Fase.leyendo;
      _paso = 'Conectando con ${a.nombre}…';
    });
    try {
      final enlace = await _bt.conectar(a.direccion);
      final transporte = TransporteBluetooth(enlace, avisar: _apuntar);
      final vivo = await transporte.despertar();
      if (!vivo) {
        await transporte.cerrar();
        if (!mounted) return;
        setState(() {
          _fase = _Fase.inicio;
          _error = 'Hay enlace con ${a.nombre}, pero no contesta como un '
              'ELM327. Comprueba que el coche tiene el contacto dado.';
        });
        return;
      }
      await _leer(transporte, ejemplo: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.inicio;
        _error = 'No hemos podido conectar con ${a.nombre}: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnosis OBD')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (_fase) {
            _Fase.inicio => _vistaInicio(),
            _Fase.eligiendo => _vistaEligiendo(),
            _Fase.leyendo => _vistaLeyendo(),
            _Fase.resultado => _vistaResultado(),
          },
        ),
      ),
    );
  }

  Widget _vistaInicio() => ListView(
        children: [
          const Text('Conecta tu lector OBD-II',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Enchufa el lector bajo el volante y da el contacto: se alimenta '
            'del propio conector, así que sin eso no se enciende. No hace '
            'falta arrancar para ver qué soporta y leer los códigos; sí para '
            'ver valores vivos.',
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _elegirLector,
            child: const Text('Conectar con mi lector'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () =>
                _leer(TransporteSimulado(retardo: const Duration(milliseconds: 40)),
                    ejemplo: true),
            child: const Text('Ver un ejemplo de lectura'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0x14FCA311),
                border: Border.all(color: const Color(0x57FCA311)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(_error!),
            ),
          ],
        ],
      );

  Widget _vistaEligiendo() => ListView(
        children: [
          const Text('Elige tu lector',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Solo salen los aparatos ya emparejados en el móvil. '
              'Los que parecen un lector van los primeros.'),
          const SizedBox(height: 14),
          ..._aparatos.map((a) => Card(
                child: ListTile(
                  leading: Icon(a.pareceElm ? Icons.usb : Icons.bluetooth),
                  title: Text(a.nombre),
                  subtitle: Text(a.direccion),
                  onTap: () => _conectarA(a),
                ),
              )),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => setState(() => _fase = _Fase.inicio),
            child: const Text('Volver'),
          ),
        ],
      );

  Widget _vistaLeyendo() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(_paso, textAlign: TextAlign.center),
          ],
        ),
      );

  Widget _vistaResultado() => ListView(
        children: [
          if (_esEjemplo)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0x29FCA311),
                border: Border.all(color: const Color(0x57FCA311)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Esto es un ejemplo, no tu coche. Son datos de muestra para ver '
                'cómo queda la pantalla. No se pueden guardar en el diario.',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          if (_vin != null) ...[
            const Text('Bastidor',
                style: TextStyle(fontWeight: FontWeight.w600)),
            SelectableText(_vin!),
            const SizedBox(height: 16),
          ],
          const Text('Lecturas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (_lecturas.isEmpty)
            const Text('El coche no ha dado ninguna lectura.')
          else
            ..._lecturas.map((l) => ListTile(
                  dense: true,
                  title: Text(l.nombre),
                  trailing: Text(
                    '${l.valor.toStringAsFixed(_decimales(l.unidad))} ${l.unidad}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                )),
          const SizedBox(height: 16),
          const Text('Códigos de avería',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (_averias.isEmpty)
            const Text('Ninguno guardado.')
          else
            ..._averias.map((a) => ListTile(
                  dense: true,
                  title: Text(a.codigo,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                  subtitle: Text(a.descripcion),
                )),
          const SizedBox(height: 20),
          FilledButton(
            /// Un ejemplo NO se guarda. Va desactivado, no escondido: que se
            /// vea que existe y por qué no se puede.
            onPressed: _esEjemplo ? null : () {},
            child: Text(_esEjemplo
                ? 'No se puede guardar un ejemplo'
                : 'Guardar en el diario'),
          ),
          TextButton(
            onPressed: () => setState(() => _fase = _Fase.inicio),
            child: const Text('Volver'),
          ),
          const SizedBox(height: 16),
          ExpansionTile(
            title: const Text('Lo que ha contestado'),
            subtitle: const Text('Para adjuntarlo si algo no cuadra'),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  _registro.join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      );

  /// Las revoluciones y los kilómetros no llevan decimales; los voltios, uno.
  int _decimales(String unidad) =>
      (unidad == 'V' || unidad == 'L/h' || unidad == 'g/s') ? 1 : 0;
}

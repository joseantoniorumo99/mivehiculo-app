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
///
/// LA SEGUNDA REGLA, del 16/09/2026: la lista de lectores enseña TAMBIÉN los
/// que no están emparejados todavía, y empareja desde aquí. Antes solo salían
/// los emparejados, y en un móvil donde el emparejamiento del sistema falla
/// —pasó con un Redmi: el lector aparecía en "disponibles" de los ajustes pero
/// no llegaba a vincularse— la app se quedaba sin ninguna salida y sin ninguna
/// explicación.
///
/// LA TERCERA, de la 1.1.0: la lectura se ve EN VIVO. Tras la primera pasada
/// completa, el enlace se queda abierto y los datos que cambian (revoluciones,
/// velocidad, temperaturas, tensión…) se refrescan cada segundo; «Guardar»
/// coge el momento que se está viendo. Y se para SOLO en cuanto se sale de
/// esta pestaña, la app pasa a segundo plano o pasan diez minutos: en vivo
/// mientras se mira, nunca mientras no se mira.
library;

import 'package:flutter/material.dart';

import 'estado.dart';
import 'obd/enlace_classic.dart';
import 'obd/lectura_fondo.dart';
import 'obd/lector_recordado.dart';
import 'obd/protocolo.dart';
import 'obd/transporte_bluetooth.dart';
import 'tema.dart';

class PantallaObd extends StatefulWidget {
  /// Si esta pestaña es la que se está mirando. Cuando deja de serlo, la
  /// lectura en vivo se para: no se lee lo que nadie mira.
  final bool activa;
  const PantallaObd({super.key, this.activa = true});
  @override
  State<PantallaObd> createState() => _PantallaObdState();
}

enum _Fase { inicio, eligiendo, leyendo, resultado }

/// Los PID que cambian mientras el motor funciona y merecen refrescarse. Los
/// que son fijos (norma OBD, sondas montadas, tipo de combustible…) se leen
/// una vez y ya.
const Set<int> _pidsVivos = {
  0x0C, 0x0D, 0x05, 0x04, 0x11, 0x0B, 0x0F, 0x10, 0x42, 0x2F, 0x5C, 0x46,
  0x0E, 0x06, 0x07, 0x14, 0x15, 0x03, 0x01, 0x21, 0x1F, 0x43, 0x45, 0x49,
  0x5A, 0x5E, 0x33, 0x62, 0x61, 0x2C, 0x23, 0x22, 0x44, 0x3C, 0x3D,
};

class _PantallaObdState extends State<PantallaObd> with WidgetsBindingObserver {
  final _bt = Bluetooth();
  _Fase _fase = _Fase.inicio;
  String _paso = '';
  String? _error;
  String? _consejo;
  List<AparatoBluetooth> _aparatos = [];
  List<Lectura> _lecturas = [];
  List<Averia> _averias = [];
  String? _vin;
  bool _esEjemplo = false;
  bool _buscando = false;

  /// La lectura de al abrir la app es automática: se guarda sola. La que
  /// pide el usuario con el botón, la guarda él si quiere.
  bool _automatica = false;

  /// Para que el botón diga "Guardada" y no deje guardar dos veces la misma.
  bool _guardada = false;

  /// EN VIVO: el enlace sigue abierto y los datos se refrescan.
  bool _enVivo = false;
  DateTime? _vivoDesde;
  int _pasadas = 0;
  Transporte? _transporteVivo;

  /// El registro solo apunta la primera pasada: en vivo son cientos de
  /// líneas por minuto y taparían lo que interesa cuando algo no cuadra.
  bool _registrando = true;

  /// Cuando el permiso queda denegado PARA SIEMPRE, el sistema ya no vuelve a
  /// preguntar y la única salida son los ajustes de la app. Sin este botón el
  /// usuario se queda con un mensaje y ninguna forma de arreglarlo.
  bool _ofrecerAjustes = false;

  /// Lo mismo con la ubicación: buscar aparatos la exige, y decirlo sin dar el
  /// botón para encenderla es mandar a alguien a rebuscar por los ajustes.
  bool _ofrecerUbicacion = false;

  /// El último lector que funcionó, para poder repetir sin volver a elegir.
  AparatoBluetooth? _lector;
  final List<String> _registro = [];

  void _apuntar(String linea) {
    if (_registrando) _registro.add(linea);
    if (mounted) setState(() => _paso = linea);
  }

  void _fallo(ErrorBluetooth e) {
    if (!mounted) return;
    setState(() {
      _fase = _Fase.inicio;
      _error = e.mensaje;
      _consejo = e.consejo;
      _ofrecerAjustes = e.causa == FalloBluetooth.permisoDenegadoParaSiempre;
      _ofrecerUbicacion = e.causa == FalloBluetooth.ubicacionApagada;
    });
  }

  void _limpiarError() {
    _error = null;
    _consejo = null;
    _ofrecerAjustes = false;
    _ofrecerUbicacion = false;
  }

  // ---------------------------------------------------------------
  // Ciclo de vida: en vivo solo mientras se mira
  // ---------------------------------------------------------------

  /// Al abrir la pantalla: si ya se sabe con qué lector se habló, se lee SOLA.
  ///
  /// Y se lee UNA VEZ, cerrando el enlace al terminar. Dejar el Bluetooth
  /// escuchando en segundo plano gasta batería, deja el puerto cogido para
  /// cualquier otra app y el sistema acaba matando el proceso igualmente. Lo
  /// que se quiere es que el dato esté fresco cuando MIRAS, no que se lea
  /// cuando no miras.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _intentarSolo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pararVivo();
    super.dispose();
  }

  @override
  void didUpdateWidget(PantallaObd viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.activa && !widget.activa) _pararVivo();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado != AppLifecycleState.resumed) _pararVivo();
  }

  Future<void> _intentarSolo() async {
    final guardado = await LectorRecordado.leer();
    if (guardado == null || !mounted) return;
    final a = AparatoBluetooth(guardado.nombre, guardado.direccion,
        emparejado: true);
    setState(() => _lector = a);
    await _conectarA(a, silencioSiFalla: true);
  }

  // ---------------------------------------------------------------
  // Elegir lector
  // ---------------------------------------------------------------

  /// Abre la lista con los EMPAREJADOS, que es instantáneo, y desde ahí se
  /// puede buscar. Al revés —buscar antes de enseñar nada— son doce segundos
  /// mirando una ruleta para quien ya tenía su lector vinculado.
  Future<void> _elegirLector() async {
    _pararVivo();
    setState(() {
      _fase = _Fase.eligiendo;
      _limpiarError();
      _aparatos = [];
    });
    try {
      final lista = await _bt.emparejados();
      if (!mounted) return;
      setState(() => _aparatos = lista);
      // Sin nada emparejado, se busca solo: es lo único que puede hacer.
      if (lista.isEmpty) await _buscarCerca();
    } on ErrorBluetooth catch (e) {
      _fallo(e);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.inicio;
        _error = 'No hemos podido ver los aparatos: $e';
      });
    }
  }

  Future<void> _buscarCerca() async {
    setState(() {
      _buscando = true;
      _limpiarError();
    });
    try {
      final lista = await _bt.buscar();
      if (!mounted) return;
      setState(() {
        _aparatos = lista;
        _buscando = false;
      });
    } on ErrorBluetooth catch (e) {
      if (!mounted) return;
      setState(() {
        _buscando = false;
        _error = e.mensaje;
        _consejo = e.consejo;
        _ofrecerAjustes = e.causa == FalloBluetooth.permisoDenegadoParaSiempre;
        _ofrecerUbicacion = e.causa == FalloBluetooth.ubicacionApagada;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _buscando = false;
        _error = 'La búsqueda ha fallado: $e';
      });
    }
  }

  // ---------------------------------------------------------------
  // Leer
  // ---------------------------------------------------------------

  Future<void> _conectarA(AparatoBluetooth a,
      {bool silencioSiFalla = false}) async {
    _pararVivo();
    setState(() {
      _fase = _Fase.leyendo;
      _paso = 'Conectando con ${a.nombre}…';
      _automatica = silencioSiFalla;
      _limpiarError();
    });
    try {
      final enlace = await _bt.conectar(a.direccion, avisar: _apuntar);
      final transporte = TransporteBluetooth(enlace, avisar: _apuntar);
      final vivo = await transporte.despertar();
      if (!vivo) {
        await transporte.cerrar();
        if (!mounted) return;
        setState(() {
          _fase = _Fase.inicio;
          _error =
              'Hay enlace con ${a.nombre}, pero no contesta como un ELM327.';
          _consejo = 'Comprueba que el coche tiene el contacto dado: el lector '
              'se alimenta del propio conector.';
        });
        return;
      }
      // Funcionó: se recuerda para poder leer solo la próxima vez
      await LectorRecordado.guardar(a.direccion, a.nombre);
      _lector = a;
      await _leer(transporte, ejemplo: false);
    } on ErrorBluetooth catch (e) {
      /// El intento automático de al abrir NO puede gritar un error: casi
      /// siempre es que el coche está apagado o el lector fuera, y eso no es
      /// un fallo, es lo normal cuando abres la app en el sofá.
      if (silencioSiFalla) {
        if (mounted) setState(() => _fase = _Fase.inicio);
        return;
      }
      _fallo(e);
    } catch (e) {
      if (!mounted) return;
      if (silencioSiFalla) {
        setState(() => _fase = _Fase.inicio);
        return;
      }
      setState(() {
        _fase = _Fase.inicio;
        _error = 'No hemos podido conectar con ${a.nombre}.';
        _consejo = e.toString();
      });
    }
  }

  Future<void> _leer(Transporte transporte, {required bool ejemplo}) async {
    setState(() {
      _fase = _Fase.leyendo;
      _esEjemplo = ejemplo;
      _registro.clear();
      _registrando = true;
      _lecturas = [];
      _averias = [];
      _vin = null;
      _limpiarError();
    });

    /// Si al final se queda en vivo, el enlace NO se cierra aquí: lo cierra
    /// `_pararVivo` cuando toque.
    var cedidoAlVivo = false;

    try {
      /// El registro lo escribe la SESIÓN, no esta pantalla: así nada queda
      /// fuera aunque el protocolo mande comandos por su cuenta, y el volcado
      /// que se copia para mandármelo no puede mentir por omisión justo en la
      /// parte que explicaría por qué falta un dato.
      final sesion = Sesion(transporte, mirar: (que, texto) {
        if (!_registrando) return;
        if (que == 'envia') {
          _registro.add('> $texto');
        } else {
          _registro
              .add('  ${texto.replaceAll(RegExp(r'[\r\n>]+'), ' ').trim()}');
        }
      });

      _apuntar('Preparando el adaptador…');
      if (!await sesion.iniciar()) {
        throw 'El adaptador no responde a los comandos.';
      }

      /// Se le PREGUNTA al coche qué sabe dar antes de pedir nada. Con una
      /// lista fija, un Opel real contestaba "no soportado" a cinco de diez
      /// mientras tenía otros datos que nadie le preguntaba.
      _apuntar('Preguntando al coche qué datos da…');
      final lecturas = await sesion.leerLoQueHaya(
        avisar: (hechos, total) => _apuntar('Leyendo $hechos de $total…'),
      );

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
        _guardada = false;
        _fase = _Fase.resultado;
      });

      /// La lectura automática de al abrir se guarda SOLA: es la que vale como
      /// "estaba en el coche tal día con tantos km". Y el bastidor se apunta
      /// en el coche siempre que llega: es lo que ata el historial a ESE coche.
      if (!ejemplo) {
        if (vin != null) await context.almacen.ponerBastidor(vin);
        if (_automatica) await _guardarLectura(avisando: false);
      }

      /// EN VIVO, pero solo si alguien está mirando: la pestaña activa y la
      /// lectura pedida a mano. La automática de al abrir la app se cierra:
      /// nadie está en esta pestaña cuando pasa.
      if (!ejemplo && !_automatica && widget.activa && lecturas.isNotEmpty) {
        cedidoAlVivo = true;
        _vivir(sesion, transporte);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fase = _Fase.inicio;
        _error = e.toString();
      });
    } finally {
      if (!cedidoAlVivo) await transporte.cerrar();
    }
  }

  /// El bucle en vivo: pasa por los PID que cambian, uno tras otro, y repinta
  /// al final de cada pasada (una por segundo, más o menos). Se para solo
  /// cuando se deja de mirar o a los diez minutos.
  Future<void> _vivir(Sesion sesion, Transporte transporte) async {
    _transporteVivo = transporte;
    _registrando = false;
    setState(() {
      _enVivo = true;
      _vivoDesde = DateTime.now();
      _pasadas = 0;
    });

    final vivos = _lecturas.map((l) => l.pid).where(_pidsVivos.contains).toList();
    try {
      while (_enVivo && mounted) {
        if (DateTime.now().difference(_vivoDesde!).inMinutes >= 10) {
          _pararVivo(motivo: 'Diez minutos en vivo: se para solo para no gastar batería.');
          break;
        }
        for (final pid in vivos) {
          if (!_enVivo || !mounted) break;
          final r = await sesion.leerPid(pid);
          if (r == null) continue;
          final i = _lecturas.indexWhere((l) => l.pid == pid);
          if (i >= 0) _lecturas[i] = r;
        }
        if (!_enVivo || !mounted) break;
        setState(() => _pasadas++);
        // Un respiro: el ELM327 no gana nada con más de una pasada por segundo
        // y la pantalla tampoco.
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } catch (_) {
      // Se cayó el enlace (el coche se apagó, el lector se desenchufó): se
      // deja lo último que se vio, que sigue siendo verdad de ese momento.
      _pararVivo(motivo: 'Se ha perdido el enlace con el lector.');
    }
  }

  void _pararVivo({String? motivo}) {
    if (!_enVivo) return;
    _enVivo = false;
    final t = _transporteVivo;
    _transporteVivo = null;
    // ignore: discarded_futures
    t?.cerrar();
    if (mounted) {
      setState(() {
        if (motivo != null) _consejo = motivo;
      });
    }
  }

  /// Guarda lo leído en las LECTURAS del coche, no en el diario. El diario es
  /// para lo que se le hace al coche; esto es lo que el coche dice de sí
  /// mismo. Van aparte a propósito. En vivo, coge el momento que se ve.
  Future<void> _guardarLectura({bool avisando = true}) async {
    if (_esEjemplo) return;
    if (_guardada && !_enVivo) return;
    final almacen = context.almacen;
    final coche = almacen.coche;
    if (coche == null) {
      if (avisando) avisar(context, 'Da de alta tu coche en el inicio para guardar lecturas.');
      return;
    }
    await almacen.guardarLectura(
        construirLecturaGuardada(coche.id, _lecturas, _averias, automatica: _automatica));
    if (!mounted) return;
    setState(() => _guardada = true);
    if (avisando) avisar(context, 'Guardada en las lecturas del coche.');
  }

  // ---------------------------------------------------------------
  // Pintura
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnosis OBD'),
        actions: [
          if (_enVivo)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: _chipVivo()),
            ),
        ],
      ),
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

  Widget _chipVivo() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Tono.tealFilm,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: Tono.tealTinta, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text('EN VIVO · $_pasadas',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Tono.tealTinta,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ],
        ),
      );

  Widget _aviso() {
    if (_error == null && _consejo == null) return const SizedBox.shrink();
    return Recuadro(
      _error ?? _consejo!,
      consejo: _error == null ? null : _consejo,
      tono: _error == null ? TonoEstado.neutro : TonoEstado.atencion,
      accion: _ofrecerAjustes
          ? TextButton(
              onPressed: _bt.abrirAjustes,
              child: const Text('Abrir los ajustes de la app'))
          : _ofrecerUbicacion
              ? TextButton(
                  onPressed: _bt.abrirAjustesUbicacion,
                  child: const Text('Abrir los ajustes de ubicación'))
              : null,
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
            /// Si ya se sabe cuál es, no se vuelve a preguntar: se conecta. La
            /// lista solo sale la primera vez o si se pide cambiar de lector.
            onPressed: () =>
                _lector != null ? _conectarA(_lector!) : _elegirLector(),
            child: Text(_lector != null
                ? 'Leer con ${_lector!.nombre}'
                : 'Conectar con mi lector'),
          ),
          TextButton(
            onPressed: () async {
              if (_lector != null) await LectorRecordado.olvidar();
              if (mounted) setState(() => _lector = null);
              await _elegirLector();
            },
            child: Text(_lector != null
                ? 'Usar otro lector'
                : 'Ver los lectores que hay'),
          ),
          TextButton(
            onPressed: () => _leer(
                TransporteSimulado(retardo: const Duration(milliseconds: 40)),
                ejemplo: true),
            child: const Text('Ver un ejemplo de lectura'),
          ),
          const SizedBox(height: 16),
          _aviso(),
        ],
      );

  Widget _vistaEligiendo() {
    final emparejados = _aparatos.where((a) => a.emparejado).toList();
    final nuevos = _aparatos.where((a) => !a.emparejado).toList();
    return ListView(
      children: [
        const Text('Elige tu lector',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text(
          'Los que parecen un lector van los primeros. Si el tuyo no está, '
          'búscalo: no hace falta emparejarlo antes desde los ajustes del '
          'móvil, la app lo empareja al conectar.',
        ),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          onPressed: _buscando ? null : _buscarCerca,
          icon: _buscando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.search),
          label: Text(_buscando
              ? 'Buscando… (tarda unos segundos)'
              : 'Buscar los que hay cerca'),
        ),
        const SizedBox(height: 14),
        _aviso(),
        if (emparejados.isNotEmpty) ...[
          const Text('Ya emparejados',
              style: TextStyle(fontWeight: FontWeight.w600)),
          ...emparejados.map(_fila),
          const SizedBox(height: 12),
        ],
        if (nuevos.isNotEmpty) ...[
          const Text('Encontrados cerca',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const Text('Al tocarlos, el móvil pedirá el PIN: 1234 o 0000.',
              style: TextStyle(fontSize: 12)),
          ...nuevos.map(_fila),
        ],
        if (_aparatos.isEmpty && !_buscando)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No aparece ningún aparato. El lector se alimenta del conector '
              'OBD: si el coche no tiene el contacto dado no se enciende, y si '
              'no se enciende no se anuncia. Da el contacto y vuelve a buscar.',
            ),
          ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() => _fase = _Fase.inicio),
          child: const Text('Volver'),
        ),
      ],
    );
  }

  Widget _fila(AparatoBluetooth a) => Card(
        child: ListTile(
          leading: Icon(a.pareceElm ? Icons.usb : Icons.bluetooth),
          title: Text(a.nombre),
          subtitle: Text([
            a.direccion,
            // La señal ayuda a distinguir el lector que está en TU coche del
            // que está en el de al lado, que pasa más de lo que parece.
            if (a.senal != null) 'señal ${a.senal} dBm',
          ].join(' · ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _conectarA(a),
        ),
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

  Widget _vistaResultado() {
    final reconocidas = _lecturas.where((l) => l.reconocido).toList();
    final crudas = _lecturas.where((l) => !l.reconocido).toList();
    return ListView(
      children: [
        if (_esEjemplo)
          const Recuadro(
            'Esto es un ejemplo, no tu coche.',
            consejo: 'Son datos de muestra para ver cómo queda la pantalla. No se '
                'pueden guardar en el diario.',
            tono: TonoEstado.atencion,
          ),
        if (_automatica && _guardada)
          const Recuadro(
            'Lectura guardada sola al abrir la app.',
            consejo: 'Está en Diario → Lecturas del OBD, aparte de las facturas.',
            tono: TonoEstado.calma,
          ),
        if (_consejo != null && _error == null)
          Recuadro(_consejo!, tono: TonoEstado.neutro),
        if (_vin != null) ...[
          const Text('Bastidor', style: TextStyle(fontWeight: FontWeight.w600)),
          SelectableText(_vin!),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: Text('Lecturas · ${_lecturas.length}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            if (_enVivo)
              TextButton(onPressed: () => _pararVivo(), child: const Text('Detener'))
            else if (!_esEjemplo && _lector != null && widget.activa)
              TextButton(
                  onPressed: () => _conectarA(_lector!),
                  child: const Text('Ver en vivo')),
          ],
        ),
        if (_enVivo)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Los valores se refrescan cada segundo. «Guardar» coge el momento '
              'que estás viendo. Se para solo al salir de aquí o a los diez minutos.',
              style: TextStyle(fontSize: 12, color: Tono.tintaSuave),
            ),
          ),
        const SizedBox(height: 6),
        if (_lecturas.isEmpty)
          const Text('El coche no ha dado ninguna lectura.')
        else
          ...reconocidas.map(_filaLectura),

        /// LOS QUE NO SABEMOS INTERPRETAR TAMBIÉN SE ENSEÑAN. El coche los ha
        /// contestado; esconderlos haría que la cuenta no cuadrase con lo que
        /// él dice que soporta, y esa diferencia es justo lo que hace dudar de
        /// si la app está leyendo bien.
        if (crudas.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('El coche da estos otros, sin traducir todavía',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const Text(
            'Son datos reales del coche; la app aún no sabe qué significan, '
            'así que los enseña tal cual en vez de callárselos.',
            style: TextStyle(fontSize: 12),
          ),
          ...crudas.map(_filaLectura),
        ],
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
          /// Un ejemplo NO se guarda. Va desactivado, no escondido: que se vea
          /// que existe y por qué no se puede.
          onPressed: (_esEjemplo || (_guardada && !_enVivo)) ? null : () => _guardarLectura(),
          child: Text(_esEjemplo
              ? 'No se puede guardar un ejemplo'
              : _enVivo
                  ? 'Guardar este momento'
                  : _guardada
                      ? 'Guardada en las lecturas'
                      : 'Guardar en las lecturas'),
        ),
        if (!_esEjemplo && _lector != null && !_enVivo)
          TextButton(
            onPressed: () => _conectarA(_lector!),
            child: const Text('Volver a leer'),
          ),
        TextButton(
          onPressed: () {
            _pararVivo();
            setState(() => _fase = _Fase.inicio);
          },
          child: const Text('Volver'),
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('Lo que ha contestado'),
          subtitle: const Text('La primera pasada, para adjuntarla si algo no cuadra'),
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
  }

  Widget _filaLectura(Lectura l) => ListTile(
        dense: true,
        title: Text(l.nombre),

        /// La mariposa NUNCA marca cero: tiene un tope mecánico y en ralentí
        /// se queda entre el 10 y el 20 %. Sin decirlo aquí, cualquiera piensa
        /// que el pedal está pisado — pasó con un coche de verdad.
        subtitle: l.pid == 0x11
            ? const Text('En ralentí marca 10-20 % por diseño, no es el pedal',
                style: TextStyle(fontSize: 11))
            : null,
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(
            l.esNumero
                ? '${l.valor!.toStringAsFixed(decimalesDe(l.unidad))} ${l.unidad}'
                : (l.texto ?? '—'),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontFamily: l.reconocido ? null : 'monospace',
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      );
}

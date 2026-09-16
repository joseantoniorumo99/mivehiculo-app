/// EL ALMACÉN: dónde vive todo y quién avisa cuando cambia.
///
/// Primero local, nube después. Aquí "local" significa de verdad local: un
/// JSON en las preferencias del móvil y las fotos de las facturas como
/// ficheros en la carpeta privada de la app. Sin cuenta, sin servidor, sin
/// red. El coche funciona en un aparcamiento subterráneo sin cobertura, y la
/// app que lleva su historial también tiene que funcionar ahí.
///
/// POR QUÉ UN SOLO JSON Y NO UNA BASE DE DATOS: el historial de un coche son
/// decenas de entradas, no millones. Una SQLite aquí sería un motor de camión
/// en una bicicleta, y traería migraciones de esquema cada vez que se añade un
/// campo. El JSON se lee entero, se escribe entero, se respalda copiando un
/// texto y se abre con el bloc de notas si algún día hace falta rescatarlo.
///
/// LA REGLA DEL GUARDADO: se guarda en cuanto algo cambia, no al salir. Un
/// móvil mata la app cuando quiere —una llamada, poca batería, el sistema
/// haciendo sitio— y nadie pulsa "guardar" antes de que le llamen por
/// teléfono.
///
/// LAS MARCAS DE SINCRONIZACIÓN: cada objeto lleva la hora de su último
/// cambio (`_marcas`), la hora del último envío a la nube (`_enviados`) y, si
/// se borró, la hora del borrado (`_borrados`). Con esas tres la nube sabe
/// qué subir, qué bajar y qué borrar en el otro lado sin preguntar. Viven
/// aquí y no en cada modelo para que los modelos no sepan que existe una nube.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'modelo.dart';

class Almacen extends ChangeNotifier {
  static const _clave = 'mivehiculo_v1';

  /// Sube cuando el formato guardado cambia de forma incompatible. Hoy 1: si
  /// algún día hay que migrar, aquí se sabrá desde qué versión.
  static const _version = 1;

  final List<Vehiculo> vehiculos = [];
  final List<Intervencion> diario = [];
  final List<Cita> citas = [];
  final List<LecturaGuardada> lecturas = [];

  String? _vehiculoActivoId;
  bool _cargado = false;
  Directory? _carpeta;

  final Map<String, String> _marcas = {};
  final Map<String, String> _enviados = {};
  final Map<String, String> _borrados = {};
  final Set<String> _fotosSubidas = {};

  /// Se avisa aquí cada vez que algo cambia por la mano del usuario (no por
  /// la sincronización). La nube lo escucha para subir en cuanto pueda.
  final _cambios = StreamController<void>.broadcast();
  Stream<void> get cambios => _cambios.stream;

  bool get cargado => _cargado;
  bool get hayCoche => vehiculos.isNotEmpty;
  bool get variosVehiculos => vehiculos.length > 1;

  Vehiculo? get coche {
    if (vehiculos.isEmpty) return null;
    for (final v in vehiculos) {
      if (v.id == _vehiculoActivoId) return v;
    }
    return vehiculos.first;
  }

  // ---------------------------------------------------------------
  // Cargar y guardar
  // ---------------------------------------------------------------

  Future<void> cargar() async {
    if (_cargado) return;
    try {
      _carpeta = await getApplicationDocumentsDirectory();
    } catch (_) {
      // En pruebas no hay carpeta de documentos; el resto tiene que seguir.
      _carpeta = null;
    }
    final p = await SharedPreferences.getInstance();
    final texto = p.getString(_clave);
    if (texto != null && texto.isNotEmpty) _leerJson(texto);
    _cargado = true;
    notifyListeners();
  }

  void _leerJson(String texto) {
    try {
      final j = jsonDecode(texto) as Map<String, dynamic>;
      List<Map<String, dynamic>> lista(String clave) =>
          ((j[clave] ?? []) as List)
              .map((x) => Map<String, dynamic>.from(x as Map))
              .toList();
      Map<String, String> mapa(String clave) =>
          Map<String, String>.from((j[clave] ?? <String, dynamic>{}) as Map);

      vehiculos
        ..clear()
        ..addAll(lista('vehiculos').map(Vehiculo.deJson));
      diario
        ..clear()
        ..addAll(lista('diario').map(Intervencion.deJson));
      citas
        ..clear()
        ..addAll(lista('citas').map(Cita.deJson));
      lecturas
        ..clear()
        ..addAll(lista('lecturas').map(LecturaGuardada.deJson));
      _vehiculoActivoId = j['vehiculoActivo'] as String?;
      _marcas
        ..clear()
        ..addAll(mapa('marcas'));
      _enviados
        ..clear()
        ..addAll(mapa('enviados'));
      _borrados
        ..clear()
        ..addAll(mapa('borrados'));
      _fotosSubidas
        ..clear()
        ..addAll(((j['fotosSubidas'] ?? []) as List).map((x) => x.toString()));
    } catch (e) {
      /// UN GUARDADO ILEGIBLE NO SE BORRA. Si el JSON está roto se arranca
      /// vacío, pero el texto original sigue en las preferencias: mientras
      /// esté ahí se puede rescatar a mano. Borrarlo para "empezar limpio"
      /// destruiría años de facturas por un byte torcido.
      debugPrint('No se ha podido leer el guardado: $e');
    }
  }

  String aJsonTexto() => jsonEncode({
        'version': _version,
        'vehiculoActivo': coche?.id,
        'vehiculos': vehiculos.map((v) => v.aJson()).toList(),
        'diario': diario.map((d) => d.aJson()).toList(),
        'citas': citas.map((c) => c.aJson()).toList(),
        'lecturas': lecturas.map((l) => l.aJson()).toList(),
        'marcas': _marcas,
        'enviados': _enviados,
        'borrados': _borrados,
        'fotosSubidas': _fotosSubidas.toList(),
      });

  Future<void> _guardar({bool esCambioPropio = true}) async {
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_clave, aJsonTexto());
    if (esCambioPropio && !_cambios.isClosed) _cambios.add(null);
  }

  static String _ahora() => DateTime.now().toUtc().toIso8601String();

  void _marcar(String id) {
    _marcas[id] = _ahora();
    _borrados.remove(id);
  }

  void _marcarBorrado(String id) {
    _marcas.remove(id);
    _enviados.remove(id);
    _borrados[id] = _ahora();
  }

  // ---------------------------------------------------------------
  // Vehículos
  // ---------------------------------------------------------------

  /// Si la matrícula ya existe NO da error: lleva al coche que ya tenías. Una
  /// matrícula identifica un coche, y dos fichas del mismo coche parten su
  /// historial en dos, que es el peor resultado posible.
  Vehiculo? vehiculoConMatricula(String matricula, {String? excepto}) {
    final m = _normalizarMatricula(matricula);
    if (m.isEmpty) return null;
    for (final v in vehiculos) {
      if (v.id != excepto && _normalizarMatricula(v.matricula) == m) return v;
    }
    return null;
  }

  static String _normalizarMatricula(String m) =>
      m.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');

  Future<Vehiculo> anadirVehiculo(Vehiculo v) async {
    final ya = vehiculoConMatricula(v.matricula);
    if (ya != null) {
      await activar(ya.id);
      return ya;
    }
    vehiculos.add(v);
    _vehiculoActivoId = v.id;
    _marcar(v.id);
    await _guardar();
    return v;
  }

  Future<void> guardarVehiculo(Vehiculo v) async {
    final i = vehiculos.indexWhere((x) => x.id == v.id);
    if (i >= 0) {
      vehiculos[i] = v;
    } else {
      vehiculos.add(v);
    }
    _marcar(v.id);
    await _guardar();
  }

  Future<void> activar(String id) async {
    if (!vehiculos.any((v) => v.id == id)) return;
    _vehiculoActivoId = id;
    await _guardar(esCambioPropio: false);
  }

  /// Quitar un coche se lleva SU historial, sus citas y sus lecturas. Dejar
  /// entradas huérfanas apuntando a un vehículo que ya no existe es lo que
  /// hace que un día aparezca un gasto de 700 € sin coche al que achacarlo.
  Future<void> quitarVehiculo(String id) async {
    for (final d in diario.where((d) => d.vehiculoId == id).toList()) {
      await _borrarFactura(d.factura);
      _marcarBorrado(d.id);
    }
    for (final c in citas.where((c) => c.vehiculoId == id)) {
      _marcarBorrado(c.id);
    }
    for (final l in lecturas.where((l) => l.vehiculoId == id)) {
      _marcarBorrado(l.id);
    }
    vehiculos.removeWhere((v) => v.id == id);
    diario.removeWhere((d) => d.vehiculoId == id);
    citas.removeWhere((c) => c.vehiculoId == id);
    lecturas.removeWhere((l) => l.vehiculoId == id);
    _marcarBorrado(id);
    if (_vehiculoActivoId == id) {
      _vehiculoActivoId = vehiculos.isEmpty ? null : vehiculos.first.id;
    }
    await _guardar();
  }

  /// Los kilómetros solo SUBEN. Corregir a la baja una anotación vieja no hace
  /// que el coche dé marcha atrás, y un cuentakilómetros que baja es lo que
  /// más desconfianza da a quien esté mirando el historial para comprar.
  Future<void> ponerKm(int km) async {
    final c = coche;
    if (c == null) return;
    if (c.km == null || km > c.km!) {
      c.km = km;
      _marcar(c.id);
      await _guardar();
    }
  }

  /// Para cuando el dueño corrige el cuentakilómetros a mano. Aquí sí puede
  /// bajar: es él quien mira el cuadro y la app la que estaba equivocada.
  Future<void> corregirKm(int km) async {
    final c = coche;
    if (c == null) return;
    c.km = km;
    _marcar(c.id);
    await _guardar();
  }

  Future<void> ponerBastidor(String vin) async {
    final c = coche;
    if (c == null || vin.isEmpty || c.bastidor == vin) return;
    c.bastidor = vin;
    _marcar(c.id);
    await _guardar();
  }

  // ---------------------------------------------------------------
  // Diario
  // ---------------------------------------------------------------

  /// El diario es DEL COCHE, no de la persona: cada entrada lleva su vehículo
  /// y aquí se filtra. Sin esto, cambiar de coche enseñaría las facturas del
  /// otro.
  List<Intervencion> get diarioDelCoche {
    final c = coche;
    if (c == null) return const [];
    final lista = diario.where((d) => d.vehiculoId == c.id).toList();
    lista.sort((a, b) => b.fecha.compareTo(a.fecha));
    return lista;
  }

  Intervencion? intervencion(String id) {
    for (final d in diario) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> guardarIntervencion(Intervencion i) async {
    final pos = diario.indexWhere((d) => d.id == i.id);
    if (pos >= 0) {
      // Si cambia la foto, la vieja se borra: sin dueño no vale para nada.
      if (diario[pos].factura.isNotEmpty && diario[pos].factura != i.factura) {
        await _borrarFactura(diario[pos].factura);
      }
      diario[pos] = i;
    } else {
      diario.add(i);
    }
    _marcar(i.id);
    if (i.km != null && i.vehiculoId == coche?.id) await ponerKm(i.km!);
    await _guardar();
  }

  Future<void> borrarIntervencion(String id) async {
    final pos = diario.indexWhere((d) => d.id == id);
    if (pos < 0) return;
    await _borrarFactura(diario[pos].factura);
    diario.removeAt(pos);
    _marcarBorrado(id);
    await _guardar();
  }

  // ---------------------------------------------------------------
  // Citas
  // ---------------------------------------------------------------

  List<Cita> get citasDelCoche {
    final c = coche;
    if (c == null) return const [];
    final lista = citas.where((x) => x.vehiculoId == c.id).toList();
    lista.sort((a, b) => '${b.fecha}${b.hora}'.compareTo('${a.fecha}${a.hora}'));
    return lista;
  }

  Future<void> guardarCita(Cita c) async {
    final pos = citas.indexWhere((x) => x.id == c.id);
    if (pos >= 0) {
      citas[pos] = c;
    } else {
      citas.add(c);
    }
    _marcar(c.id);
    await _guardar();
  }

  Future<void> cancelarCita(String id) async {
    final pos = citas.indexWhere((x) => x.id == id);
    if (pos < 0) return;
    citas[pos].estado = EstadoCita.cancelada;
    _marcar(id);
    await _guardar();
  }

  // ---------------------------------------------------------------
  // Lecturas del OBD
  // ---------------------------------------------------------------

  List<LecturaGuardada> get lecturasDelCoche {
    final c = coche;
    if (c == null) return const [];
    final lista = lecturas.where((l) => l.vehiculoId == c.id).toList();
    lista.sort((a, b) => b.cuando.compareTo(a.cuando));
    return lista;
  }

  Future<void> guardarLectura(LecturaGuardada l) async {
    lecturas.add(l);
    _marcar(l.id);
    if (l.km != null && l.vehiculoId == coche?.id) await ponerKm(l.km!);
    await _guardar();
  }

  Future<void> borrarLectura(String id) async {
    lecturas.removeWhere((l) => l.id == id);
    _marcarBorrado(id);
    await _guardar();
  }

  // ---------------------------------------------------------------
  // Facturas (ficheros)
  // ---------------------------------------------------------------

  /// Dónde está de verdad la foto. Devuelve null si no hay carpeta (pruebas) o
  /// si el fichero ya no existe: una ruta rota tiene que dar "no hay foto" y
  /// no una pantalla en negro.
  File? ficheroFactura(String nombreFichero) {
    if (_carpeta == null || nombreFichero.isEmpty) return null;
    if (nombreFichero.contains('/') || nombreFichero.contains('\\')) return null;
    final f = File('${_carpeta!.path}${Platform.pathSeparator}$nombreFichero');
    return f.existsSync() ? f : null;
  }

  /// Copia la foto elegida a la carpeta de la app y devuelve su nombre. Se
  /// COPIA y no se guarda la ruta de la galería a propósito: el usuario puede
  /// borrar la foto de la galería mañana, y la factura del coche tiene que
  /// seguir ahí dentro de siete años cuando lo venda.
  Future<String> adjuntarFactura(File origen) async {
    if (_carpeta == null) return '';
    var ext = origen.path.contains('.')
        ? origen.path.substring(origen.path.lastIndexOf('.')).toLowerCase()
        : '.jpg';
    if (!RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(ext)) ext = '.jpg';
    final nombreFichero = '${nuevoId('f')}$ext';
    await origen.copy('${_carpeta!.path}${Platform.pathSeparator}$nombreFichero');
    return nombreFichero;
  }

  Future<void> guardarFacturaBajada(String nombreFichero, List<int> bytes) async {
    if (_carpeta == null) return;
    await File('${_carpeta!.path}${Platform.pathSeparator}$nombreFichero')
        .writeAsBytes(bytes, flush: true);
  }

  Future<void> _borrarFactura(String nombreFichero) async {
    final f = ficheroFactura(nombreFichero);
    _fotosSubidas.remove(nombreFichero);
    if (f != null) {
      try {
        await f.delete();
      } catch (_) {/* si no se puede, tampoco es para tirar la app */}
    }
  }

  bool fotoSubida(String nombreFichero) => _fotosSubidas.contains(nombreFichero);

  void marcarFotoSubida(String nombreFichero) {
    _fotosSubidas.add(nombreFichero);
    unawaited(_guardar(esCambioPropio: false));
  }

  // ---------------------------------------------------------------
  // Lo que la nube necesita
  // ---------------------------------------------------------------

  String? marcaDe(String id) => _marcas[id];
  String? enviadoEn(String id) => _enviados[id];
  String? borradoEn(String id) => _borrados[id];
  Iterable<String> get idsBorrados => _borrados.keys;

  Iterable<String> get todosLosIds => [
        ...vehiculos.map((v) => v.id),
        ...diario.map((d) => d.id),
        ...citas.map((c) => c.id),
        ...lecturas.map((l) => l.id),
      ];

  /// Hay algo que no ha llegado a la nube todavía.
  bool get hayPendiente =>
      _borrados.isNotEmpty ||
      _marcas.entries.any((e) => _enviados[e.key] != e.value);

  void marcarEnviado(String id, String marca) {
    _enviados[id] = marca;
    unawaited(_guardar(esCambioPropio: false));
  }

  void olvidarBorrado(String id) {
    _borrados.remove(id);
    unawaited(_guardar(esCambioPropio: false));
  }

  String? tipoDe(String id) {
    if (vehiculos.any((v) => v.id == id)) return 'vehiculo';
    if (diario.any((d) => d.id == id)) return 'intervencion';
    if (citas.any((c) => c.id == id)) return 'cita';
    if (lecturas.any((l) => l.id == id)) return 'lectura';
    return null;
  }

  Map<String, dynamic>? objetoJson(String id) {
    for (final v in vehiculos) {
      if (v.id == id) return v.aJson();
    }
    for (final d in diario) {
      if (d.id == id) return d.aJson();
    }
    for (final c in citas) {
      if (c.id == id) return c.aJson();
    }
    for (final l in lecturas) {
      if (l.id == id) return l.aJson();
    }
    return null;
  }

  /// Aplica algo que viene del servidor. NO pasa por `_marcar`: la marca es
  /// la del servidor, y `enviado` también, para que no se vuelva a subir lo
  /// que acaba de bajar.
  Future<void> aplicarRemoto(
      String tipo, Map<String, dynamic> datos, String actualizado) async {
    final id = (datos['id'] ?? '') as String;
    if (id.isEmpty) return;
    switch (tipo) {
      case 'vehiculo':
        final v = Vehiculo.deJson(datos);
        final i = vehiculos.indexWhere((x) => x.id == id);
        if (i >= 0) {
          vehiculos[i] = v;
        } else {
          vehiculos.add(v);
        }
        _vehiculoActivoId ??= v.id;
      case 'intervencion':
        final d = Intervencion.deJson(datos);
        final i = diario.indexWhere((x) => x.id == id);
        if (i >= 0) {
          diario[i] = d;
        } else {
          diario.add(d);
        }
      case 'cita':
        final c = Cita.deJson(datos);
        final i = citas.indexWhere((x) => x.id == id);
        if (i >= 0) {
          citas[i] = c;
        } else {
          citas.add(c);
        }
      case 'lectura':
        final l = LecturaGuardada.deJson(datos);
        final i = lecturas.indexWhere((x) => x.id == id);
        if (i >= 0) {
          lecturas[i] = l;
        } else {
          lecturas.add(l);
        }
      default:
        return;
    }
    _marcas[id] = actualizado;
    _enviados[id] = actualizado;
    _borrados.remove(id);
    await _guardar(esCambioPropio: false);
  }

  /// Se borró desde otro aparato: se quita aquí sin dejar lápida, que ya no
  /// hay nada que borrar allí.
  Future<void> quitarPorSincronizacion(String id) async {
    final d = diario.where((x) => x.id == id).toList();
    for (final x in d) {
      await _borrarFactura(x.factura);
    }
    vehiculos.removeWhere((x) => x.id == id);
    diario.removeWhere((x) => x.id == id);
    citas.removeWhere((x) => x.id == id);
    lecturas.removeWhere((x) => x.id == id);
    _marcas.remove(id);
    _enviados.remove(id);
    if (_vehiculoActivoId == id) {
      _vehiculoActivoId = vehiculos.isEmpty ? null : vehiculos.first.id;
    }
    await _guardar(esCambioPropio: false);
  }

  /// Al cerrar sesión los datos NO se borran del móvil: son suyos y siguen
  /// aquí. Lo que se olvida es qué se había subido, para que si entra otra
  /// cuenta no se dé por sincronizado lo que esa cuenta no tiene.
  Future<void> olvidarNube() async {
    _enviados.clear();
    _fotosSubidas.clear();
    await _guardar(esCambioPropio: false);
  }

  /// Para las pruebas: carga un estado sin tocar disco ni preferencias.
  @visibleForTesting
  void cargarDePruebas({
    List<Vehiculo> conVehiculos = const [],
    List<Intervencion> conDiario = const [],
    List<Cita> conCitas = const [],
    List<LecturaGuardada> conLecturas = const [],
  }) {
    vehiculos
      ..clear()
      ..addAll(conVehiculos);
    diario
      ..clear()
      ..addAll(conDiario);
    citas
      ..clear()
      ..addAll(conCitas);
    lecturas
      ..clear()
      ..addAll(conLecturas);
    _vehiculoActivoId = conVehiculos.isEmpty ? null : conVehiculos.first.id;
    _cargado = true;
  }

  @override
  void dispose() {
    _cambios.close();
    super.dispose();
  }
}

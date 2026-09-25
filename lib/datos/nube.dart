/// LA NUBE: la cuenta y la copia de los datos en Appwrite.
///
/// Es el MISMO proyecto de Appwrite que usa la versión web: el coche que das
/// de alta en el móvil sale en el ordenador y al revés. Endpoint y project id
/// son públicos —van también en el JavaScript de la web—; lo que no va aquí
/// ni en ningún fichero es una API key, que es de servidor y no pinta nada en
/// un móvil.
///
/// EL MÓVIL MANDA. El almacén local es la verdad y la nube es la copia: la
/// app funciona igual sin cuenta, sin cobertura y con el servidor caído. Con
/// cuenta, cada cambio se sube en cuanto hay red y al entrar se baja lo que
/// haya de otros aparatos. Si el mismo dato se tocó en dos sitios, gana el
/// más reciente (última escritura), que para un diario de mantenimiento es lo
/// razonable: nadie edita la misma factura desde dos móviles a la vez.
///
/// CÓMO SE GUARDA EN EL SERVIDOR: una sola tabla, `documentos`, con una fila
/// por objeto —vehículo, intervención, cita, lectura— y el objeto entero como
/// JSON en una columna. No es lo canónico, y es a propósito: una tabla por
/// tipo con una columna por campo obligaría a tocar el servidor cada vez que
/// el móvil añade un campo, y a que el móvil viejo y el nuevo no se entiendan.
/// Así la fila es opaca para el servidor y la app decide. Las fotos de las
/// facturas van a un cubo de Storage con el mismo permiso por usuario.
///
/// Cada fila y cada foto llevan permiso de lectura y escritura SOLO para su
/// dueño (`Role.user`). El servidor lo impone; no depende de que la app se
/// porte bien.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:appwrite/models.dart' as modelos;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../lugares/lugares.dart' show FichaTaller, etiquetaDeTaller;
import 'almacen.dart';
import 'modelo.dart';

class Nube extends ChangeNotifier {
  static const endpoint = 'https://fra.cloud.appwrite.io/v1';
  static const proyecto = '6a9a7983002332de60a5';
  static const bd = 'principal';
  static const tabla = 'documentos';
  static const cubo = 'facturas';

  /// La web atiende `?userId=…&secret=…` para poner clave nueva y para
  /// confirmar el correo, así que los enlaces de esos correos apuntan allí.
  /// A `/app`, que es quien los entiende: hasta la 1.5.1 iban a la portada, y
  /// la portada los reenvía a `/app` por si queda alguna versión vieja.
  static const urlRecuperacion = 'https://motora-42w.pages.dev/app';

  late final Client _cliente;
  late final Account _cuenta;
  late final TablesDB _tablas;
  late final Storage _archivos;
  late final Functions _funciones;

  /// La función del servidor que crea las citas con el permiso del taller, y
  /// la tabla donde viven. Son las mismas que usa la web.
  static const funcionCitas = 'citas';
  static const tablaCitas = 'citas';

  /// La ficha que cada taller publica desde su panel (servicios con precio y
  /// tiempo, extras). Pública: se lee sin sesión.
  static const tablaTalleres = 'talleres';
  final Map<String, FichaTaller?> _fichas = {};
  List<FichaTaller>? _publicados;
  DateTime? _publicadosCuando;

  modelos.User? usuario;

  /// Ya se ha intentado recuperar la sesión al arrancar. Hasta entonces la
  /// app no sabe si hay cuenta o no, y no debe pintar "sin cuenta" un segundo
  /// para luego cambiar.
  bool arrancada = false;

  bool sincronizando = false;
  DateTime? ultimaSincronizacion;

  /// Lo que el taller ha hecho con una cita desde la última vez (confirmar,
  /// rechazar, mandar el informe). Lo escucha la app para avisar.
  final _novedades = StreamController<NovedadCita>.broadcast();
  Stream<NovedadCita> get novedades => _novedades.stream;

  /// Lo último que pasó al sincronizar, para la pantalla del perfil. Null
  /// cuando fue bien.
  String? ultimoAviso;

  /// Se pone a false si el servidor contesta que la tabla o el cubo no
  /// existen: entonces la app lo dice en el perfil en vez de reintentar en
  /// silencio cada minuto.
  bool servidorListo = true;

  /// Verdadero cuando lo que hay en este móvil es de OTRA cuenta (ver
  /// `Almacen.propietarioLocal`). Mientras esté así, `sincronizar()` no toca
  /// el servidor: subir a ciegas escribiría encima de filas de otra persona,
  /// o mezclaría su diario en esta cuenta. El perfil lo enseña y ofrece
  /// `resolverConflictoVaciando`.
  bool conflictoDeCuenta = false;

  Nube() {
    _cliente = Client().setEndpoint(endpoint).setProject(proyecto);
    _cuenta = Account(_cliente);
    _tablas = TablesDB(_cliente);
    _archivos = Storage(_cliente);
    _funciones = Functions(_cliente);
  }

  bool get conSesion => usuario != null;
  String get nombre => usuario?.name ?? '';
  String get correo => usuario?.email ?? '';
  bool get correoVerificado => usuario?.emailVerification ?? false;

  // ---------------------------------------------------------------
  // Cuenta
  // ---------------------------------------------------------------

  Future<void> recuperarSesion() async {
    try {
      usuario = await _cuenta.get();
    } catch (_) {
      usuario = null;
    }
    arrancada = true;
    notifyListeners();
  }

  Future<void> entrar(String correo, String clave) async {
    // En minúsculas: el teclado del móvil pone mayúscula la primera letra
    // sin que nadie se lo pida, y "Jose@" no es "jose@" para todo el mundo.
    await _cuenta.createEmailPasswordSession(
        email: correo.trim().toLowerCase(), password: clave);
    usuario = await _cuenta.get();
    notifyListeners();
  }

  /// Entrar con Google. El SDK abre el navegador del sistema con la página de
  /// Google, Appwrite crea la sesión y vuelve a la app por el esquema
  /// `appwrite-callback-<proyecto>://` (declarado en el manifiesto). Es el
  /// mismo proveedor que usa la web, así que la cuenta es la misma.
  Future<void> entrarConGoogle() async {
    await _cuenta.createOAuth2Session(provider: enums.OAuthProvider.google);
    usuario = await _cuenta.get();
    notifyListeners();
  }

  Future<void> registrar(String nombre, String correo, String clave) async {
    await _cuenta.create(
      userId: ID.unique(),
      email: correo.trim().toLowerCase(),
      password: clave,
      name: nombre.trim(),
    );
    await entrar(correo, clave);
    // Que llegue el correo de verificación no bloquea nada: si falla, se
    // puede pedir otra vez desde el perfil.
    try {
      await _cuenta.createEmailVerification(url: '$urlRecuperacion?accion=verificar');
    } catch (_) {/* sin drama */}
  }

  Future<void> salir() async {
    try {
      await _cuenta.deleteSession(sessionId: 'current');
    } catch (_) {/* ya estaba muerta */}
    usuario = null;
    ultimaSincronizacion = null;
    notifyListeners();
  }

  Future<void> pedirClaveNueva(String correo) =>
      _cuenta.createRecovery(email: correo.trim(), url: urlRecuperacion);

  /// Borra la cuenta y TODO lo que hay en ella: lo hace la función del
  /// servidor (acción `borrarCuenta`), porque el SDK de cliente no deja que
  /// un usuario se borre a sí mismo y porque hay que llevarse también sus
  /// filas, sus citas y sus ficheros con una clave que los vea todos.
  /// Devuelve null si ha ido bien, o el motivo si no.
  /// Resuelve `conflictoDeCuenta` vaciando este móvil (coche, diario, citas,
  /// lecturas y sus fotos) y descargando lo que de verdad tenga esta cuenta
  /// en el servidor. Es la opción segura: si lo que había era importante,
  /// seguía a salvo en su cuenta original, entrando con ella en cualquier
  /// otro móvil.
  Future<void> resolverConflictoVaciando(Almacen almacen) async {
    await almacen.borrarTodo();
    conflictoDeCuenta = false;
    await sincronizar(almacen);
  }

  Future<String?> borrarCuenta() async {
    if (!conSesion) return 'No hay ninguna sesión abierta.';
    try {
      final e = await _funciones.createExecution(
        functionId: funcionCitas,
        body: jsonEncode({'accion': 'borrarCuenta'}),
        xasync: false,
      );
      final cuerpo = e.responseBody.trim().isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(e.responseBody) as Map);
      if (cuerpo['ok'] != true) {
        return (cuerpo['error'] as String?) ??
            'El servidor no ha contestado. Inténtalo más tarde o escríbenos.';
      }
    } on AppwriteException catch (e) {
      if (e.code == 404) {
        return 'El servidor todavía no admite borrar cuentas desde la app. '
            'Escríbenos y lo hacemos a mano.';
      }
      return explicar(e);
    } catch (_) {
      return 'Sin conexión. Inténtalo con red.';
    }
    // La sesión murió con la cuenta; aquí solo queda olvidarla
    usuario = null;
    ultimaSincronizacion = null;
    notifyListeners();
    return null;
  }

  Future<void> reenviarVerificacion() =>
      _cuenta.createEmailVerification(url: '$urlRecuperacion?accion=verificar');

  /// Lo que Appwrite devuelve traducido a lo que la persona puede hacer. Un
  /// "AppwriteException: user_invalid_credentials (401)" en pantalla es un
  /// fallo de la app tanto como el error que describe.
  static String explicar(Object e) {
    if (e is AppwriteException) {
      switch (e.type) {
        case 'user_invalid_credentials':
          return 'El correo o la contraseña no son correctos.';
        case 'user_already_exists':
        case 'user_email_already_exists':
          return 'Ya hay una cuenta con ese correo. Entra con ella o pide una '
              'contraseña nueva.';
        case 'user_password_mismatch':
          return 'Las contraseñas no coinciden.';
        case 'password_recently_used':
        case 'password_personal_data':
          return 'Esa contraseña no vale: no puede llevar tu nombre ni tu '
              'correo, ni ser una que ya usaste.';
        case 'user_blocked':
          return 'Esa cuenta está bloqueada.';
        case 'general_rate_limit_exceeded':
          return 'Demasiados intentos seguidos. Espera un minuto.';
        case 'user_session_already_exists':
          return 'Ya había una sesión abierta.';
      }
      if (e.code == 400 && (e.message ?? '').contains('password')) {
        return 'La contraseña tiene que tener al menos 8 caracteres.';
      }
      if (e.code == 400 && (e.message ?? '').contains('email')) {
        return 'Ese correo no tiene buena pinta. Revísalo.';
      }
      if (e.code == 404) return 'El servidor no tiene eso todavía.';
      if (e.code == 401) return 'Hace falta entrar con la cuenta.';
      return e.message ?? 'Fallo del servidor (${e.code}).';
    }
    if (e is SocketException) {
      return 'Sin conexión. Los datos están a salvo en el móvil y se subirán '
          'cuando vuelva la red.';
    }
    return e.toString();
  }

  // ---------------------------------------------------------------
  // Sincronizar
  // ---------------------------------------------------------------

  List<String> _permisos() {
    final uid = usuario!.$id;
    return [
      Permission.read(Role.user(uid)),
      Permission.update(Role.user(uid)),
      Permission.delete(Role.user(uid)),
    ];
  }

  /// Baja lo del servidor, mezcla, y sube lo que falte. Nunca lanza: lo que
  /// pase queda en `ultimoAviso` para que el perfil lo cuente.
  ///
  /// ANTES de tocar el servidor, comprueba de quién es lo que hay en este
  /// móvil. Si es de otra cuenta, no se sube nada: se marca
  /// `conflictoDeCuenta` y se para ahí. Subir a ciegas el coche o el diario
  /// de otra persona a esta cuenta, o intentar escribir encima de una fila
  /// que no es suya, es peor que preguntar primero.
  Future<void> sincronizar(Almacen almacen) async {
    if (!conSesion || sincronizando) return;
    final uid = usuario!.$id;
    final propietario = almacen.propietarioLocal;
    if (propietario != null && propietario != uid && almacen.hayDatosLocales) {
      conflictoDeCuenta = true;
      notifyListeners();
      return;
    }
    conflictoDeCuenta = false;
    sincronizando = true;
    ultimoAviso = null;
    notifyListeners();
    try {
      await _sincronizarDeVerdad(almacen);
      await almacen.marcarPropietario(uid);
      ultimaSincronizacion = DateTime.now();
      servidorListo = true;
    } on AppwriteException catch (e) {
      if (e.code == 404) {
        /// La tabla no existe: el servidor no está preparado. No es un fallo
        /// del usuario y no se le enseña como tal.
        servidorListo = false;
        ultimoAviso = 'El servidor todavía no tiene la tabla de datos. Los '
            'datos siguen guardados en este móvil.';
      } else {
        ultimoAviso = explicar(e);
      }
    } catch (e) {
      ultimoAviso = explicar(e);
    } finally {
      sincronizando = false;
      notifyListeners();
    }
  }

  Future<void> _sincronizarDeVerdad(Almacen almacen) async {
    final uid = usuario!.$id;

    // 1. Bajar TODO lo del usuario, por páginas.
    final remotos = <String, modelos.Row>{};
    String? cursor;
    while (true) {
      final pagina = await _tablas.listRows(
        databaseId: bd,
        tableId: tabla,
        queries: [
          Query.equal('usuarioId', uid),
          Query.limit(100),
          if (cursor != null) Query.cursorAfter(cursor),
        ],
      );
      for (final fila in pagina.rows) {
        remotos[fila.$id] = fila;
      }
      if (pagina.rows.length < 100) break;
      cursor = pagina.rows.last.$id;
    }

    // 2. Mezclar fila a fila.
    for (final fila in remotos.values) {
      final id = fila.$id;
      final tipo = (fila.data['tipo'] ?? '') as String;
      final actualizado = (fila.data['actualizado'] ?? fila.$updatedAt) as String;
      final borradoLocal = almacen.borradoEn(id);
      final marcaLocal = almacen.marcaDe(id);

      if (borradoLocal != null && borradoLocal.compareTo(actualizado) >= 0) {
        // Se borró aquí después de la última copia: se borra allí.
        await _tablas.deleteRow(databaseId: bd, tableId: tabla, rowId: id);
        almacen.olvidarBorrado(id);
        continue;
      }
      if (marcaLocal == null || actualizado.compareTo(marcaLocal) > 0) {
        // Lo del servidor es más nuevo (o aquí no está): se aplica.
        final datos = jsonDecode((fila.data['datos'] ?? '{}') as String);
        await almacen.aplicarRemoto(
            tipo, Map<String, dynamic>.from(datos as Map), actualizado);
        await _bajarFotoSiFalta(almacen, tipo, datos);
      } else if (marcaLocal.compareTo(actualizado) > 0) {
        // Lo de aquí es más nuevo: se sube.
        await _subir(almacen, id, uid);
      } else {
        almacen.marcarEnviado(id, marcaLocal);
      }
    }

    // 3. Lo que hay aquí y allí no: o es nuevo (se sube) o lo borraron desde
    //    otro aparato (se borra aquí). Se distingue por si alguna vez llegó a
    //    subirse.
    for (final id in almacen.todosLosIds.toList()) {
      if (remotos.containsKey(id)) continue;
      if (almacen.enviadoEn(id) != null) {
        await almacen.quitarPorSincronizacion(id);
      } else {
        await _subir(almacen, id, uid);
      }
    }

    // 4. Borrados pendientes de objetos que ya no están ni aquí ni allí.
    for (final id in almacen.idsBorrados.toList()) {
      if (!remotos.containsKey(id)) almacen.olvidarBorrado(id);
    }

    // 5. Las citas van por otra tabla: lo que haya decidido el taller. Cada
    //    novedad sale por el canal para que la app avise en la bandeja.
    for (final n in await sincronizarCitas(almacen)) {
      _novedades.add(n);
    }
  }

  // ---------------------------------------------------------------
  // Citas: por la función del servidor, que es quien puede dar el permiso
  // del taller
  // ---------------------------------------------------------------

  /// Manda la cita al servidor. La crea la función `citas` con el permiso
  /// `label:<taller>` que un usuario no puede conceder; ahí se comprueban de
  /// verdad la identidad y el correo verificado.
  ///
  /// Devuelve `remotoId` si llegó; `error` con un motivo para la persona si
  /// la función dijo que no (correo sin verificar, fecha pasada); y
  /// `sinServidor` si la función no está desplegada o no hay red, que no es
  /// culpa de nadie y la cita se queda en el móvil como hasta ahora.
  Future<({String? remotoId, String? error, bool sinServidor})> enviarCita(
      Cita c, String vehiculo) async {
    if (!conSesion) return (remotoId: null, error: null, sinServidor: true);
    try {
      final e = await _funciones.createExecution(
        functionId: funcionCitas,
        body: jsonEncode({
          'tallerId': c.lugarId,
          'tallerNombre': c.lugarNombre,
          'servicio': c.servicio,
          'fecha': c.fecha,
          'hora': c.hora,
          'vehiculo': vehiculo,
        }),
        xasync: false,
      );
      final cuerpo = e.responseBody.trim().isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(e.responseBody) as Map);
      if (cuerpo['ok'] == true && cuerpo['cita'] is Map) {
        final fila = Map<String, dynamic>.from(cuerpo['cita'] as Map);
        return (remotoId: fila[r'$id'] as String?, error: null, sinServidor: false);
      }
      final motivo = cuerpo['error'] as String?;
      if (motivo != null && motivo.isNotEmpty) {
        return (remotoId: null, error: motivo, sinServidor: false);
      }
      return (remotoId: null, error: null, sinServidor: true);
    } on AppwriteException catch (e) {
      // 404: la función no existe todavía. No es un error del usuario.
      if (e.code == 404) return (remotoId: null, error: null, sinServidor: true);
      return (remotoId: null, error: explicar(e), sinServidor: false);
    } catch (_) {
      return (remotoId: null, error: null, sinServidor: true);
    }
  }

  /// Baja las citas del usuario de la tabla `citas` y pone al día las
  /// locales: es por donde vuelve lo que decida el taller (estado, respuesta
  /// e informe). Las que existan allí y aquí no (pedidas desde la web) se
  /// traen al coche en uso.
  ///
  /// Devuelve las NOVEDADES: cada cita cuyo último suceso (confirmada,
  /// rechazada, informe) todavía no se había avisado. Se marca como avisado
  /// aquí mismo, así que quien llame —la app abierta o la comprobación en
  /// segundo plano— avisa una vez y el otro ya no.
  Future<List<NovedadCita>> sincronizarCitas(Almacen almacen) async {
    final uid = usuario!.$id;
    final coche = almacen.coche;
    final novedades = <NovedadCita>[];
    modelos.RowList pagina;
    try {
      pagina = await _tablas.listRows(
        databaseId: bd,
        tableId: tablaCitas,
        queries: [Query.equal('clienteId', uid), Query.limit(100)],
      );
    } on AppwriteException catch (e) {
      if (e.code == 404) return novedades; // sin tabla de citas todavía
      rethrow;
    }
    final hoy = DateTime.now();
    final hace30 = hoy.subtract(const Duration(days: 30));
    final limite = '${hace30.year}-${hace30.month.toString().padLeft(2, '0')}-${hace30.day.toString().padLeft(2, '0')}';

    for (final fila in pagina.rows) {
      final d = fila.data;
      final estado = Cita.estadoDeTexto(d['estado'] as String?);
      final respuesta = mapaTolerante(d['respuesta']);
      final informe = mapaTolerante(d['informe']);
      Cita? local;
      for (final c in almacen.citas) {
        if (c.remotoId == fila.$id) {
          local = c;
          break;
        }
      }
      if (local == null) {
        if (coche == null) continue;
        local = Cita(
          vehiculoId: coche.id,
          lugarId: (d['tallerId'] ?? '') as String,
          lugarNombre: (d['tallerNombre'] ?? '') as String,
          servicio: (d['servicio'] ?? '') as String,
          fecha: (d['fecha'] ?? '') as String,
          hora: (d['hora'] ?? '') as String,
          estado: estado,
          enviada: true,
          remotoId: fila.$id,
          respuesta: respuesta,
          informe: informe,
        );
        // Una cita de hace más de un mes que llega de la web no es una
        // novedad: se da por vista para no llenar la bandeja al estrenar.
        if (local.fecha.compareTo(limite) < 0) local.avisado = local.suceso;
        await almacen.guardarCita(local);
      } else {
        // El taller puede mover la cita desde su agenda: fecha y hora nuevas
        final fechaRemota = (d['fecha'] ?? local.fecha).toString();
        final horaRemota = (d['hora'] ?? local.hora).toString();
        final movida = local.enviada &&
            (fechaRemota != local.fecha || horaRemota != local.hora) &&
            fechaRemota.isNotEmpty;
        final cambia = movida ||
            local.estado != estado ||
            !local.enviada ||
            jsonEncode(local.respuesta) != jsonEncode(respuesta) ||
            jsonEncode(local.informe) != jsonEncode(informe);
        if (cambia) {
          local
            ..estado = estado
            ..enviada = true
            ..fecha = fechaRemota
            ..hora = horaRemota
            ..respuesta = respuesta
            ..informe = informe;
          await almacen.guardarCita(local);
        }
        // Un cambio de fecha se avisa siempre: es lo que más importa saber
        if (movida && estado != EstadoCita.cancelada && estado != EstadoCita.rechazada) {
          novedades.add(NovedadCita(local, 'cambiada'));
        }
      }
      final suceso = local.suceso;
      if (suceso.isNotEmpty && suceso != local.avisado) {
        local.avisado = suceso;
        await almacen.guardarCita(local);
        novedades.add(NovedadCita(local, suceso));
      }
    }
    return novedades;
  }

  /// La ficha publicada por un taller, o null si no publicó nada (o no hay
  /// red, o la tabla no existe todavía). Se recuerda por sesión: abrir la
  /// misma ficha tres veces no son tres viajes.
  Future<FichaTaller?> fichaDeTaller(String lugarId) async {
    final id = etiquetaDeTaller(lugarId);
    if (id.isEmpty) return null;
    if (_fichas.containsKey(id)) return _fichas[id];
    try {
      final fila = await _tablas.getRow(databaseId: bd, tableId: tablaTalleres, rowId: id);
      var f = FichaTaller.deFila({...fila.data, r'$id': id});
      try {
        final v = await _tablas.getRow(databaseId: bd, tableId: 'verificaciones', rowId: id);
        f = f.conSello(v.data['verificado'] == true);
      } catch (_) {}
      _fichas[id] = f;
      return f;
    } catch (_) {
      _fichas[id] = null;
      return null;
    }
  }

  /// Todos los talleres con ficha publicada, para pintar en el mapa los que
  /// no están en OpenStreetMap. Hoy son pocos: se bajan de una vez (100) y se
  /// recuerdan diez minutos. Sin tabla o sin red, ninguno.
  Future<List<FichaTaller>> talleresPublicados() async {
    final ahora = DateTime.now();
    if (_publicados != null &&
        _publicadosCuando != null &&
        ahora.difference(_publicadosCuando!).inMinutes < 10) {
      return _publicados!;
    }
    try {
      final pagina = await _tablas.listRows(
        databaseId: bd,
        tableId: tablaTalleres,
        queries: [Query.limit(100)],
      );
      // Los sellos, de la tabla que solo escribe el servidor
      final sellos = <String>{};
      try {
        final v = await _tablas.listRows(databaseId: bd, tableId: 'verificaciones', queries: [Query.limit(100)]);
        for (final r in v.rows) {
          if (r.data['verificado'] == true) sellos.add(r.$id);
        }
      } catch (_) {}
      final lista = pagina.rows
          .map((f) => FichaTaller.deFila({...f.data, r'$id': f.$id}).conSello(sellos.contains(f.$id)))
          .toList();
      for (final f in lista) {
        _fichas[f.id] = f;
      }
      _publicados = lista;
      _publicadosCuando = ahora;
      return lista;
    } catch (_) {
      return _publicados ?? const [];
    }
  }

  Future<void> _subir(Almacen almacen, String id, String uid) async {
    final tipo = almacen.tipoDe(id);
    final objeto = almacen.objetoJson(id);
    final marca = almacen.marcaDe(id);
    if (tipo == null || objeto == null || marca == null) return;

    await _tablas.upsertRow(
      databaseId: bd,
      tableId: tabla,
      rowId: id,
      data: {
        'usuarioId': uid,
        'tipo': tipo,
        'datos': jsonEncode(objeto),
        'actualizado': marca,
      },
      permissions: _permisos(),
    );
    almacen.marcarEnviado(id, marca);

    if (tipo == 'intervencion') {
      final f = (objeto['factura'] ?? '') as String;
      if (f.isNotEmpty) await _subirFoto(almacen, f);
      for (final foto in ((objeto['fotos'] ?? []) as List)) {
        if (foto.toString().isNotEmpty) await _subirFoto(almacen, foto.toString());
      }
    }
  }

  static String _idArchivo(String nombreFichero) {
    final sinExt = nombreFichero.contains('.')
        ? nombreFichero.substring(0, nombreFichero.lastIndexOf('.'))
        : nombreFichero;
    return sinExt.length > 36 ? sinExt.substring(0, 36) : sinExt;
  }

  Future<void> _subirFoto(Almacen almacen, String nombreFichero) async {
    if (almacen.fotoSubida(nombreFichero)) return;
    final f = almacen.ficheroFactura(nombreFichero);
    if (f == null) return;
    try {
      await _archivos.createFile(
        bucketId: cubo,
        fileId: _idArchivo(nombreFichero),
        file: InputFile.fromPath(path: f.path, filename: nombreFichero),
        permissions: _permisos(),
      );
      almacen.marcarFotoSubida(nombreFichero);
    } on AppwriteException catch (e) {
      if (e.code == 409) {
        almacen.marcarFotoSubida(nombreFichero); // ya estaba
      } else if (e.code == 404) {
        // El cubo no existe todavía: la fila sí se subió, la foto esperará.
        ultimoAviso = 'El servidor todavía no tiene el cubo de facturas: las '
            'fotos se quedan en este móvil hasta que exista.';
      } else {
        rethrow;
      }
    }
  }

  Future<void> _bajarFotoSiFalta(
      Almacen almacen, String tipo, Object datos) async {
    if (tipo != 'intervencion' || datos is! Map) return;
    final ficheros = <String>[
      (datos['factura'] ?? '') as String,
      ...((datos['fotos'] ?? []) as List).map((x) => x.toString()),
    ];
    for (final f in ficheros) {
      if (f.isEmpty || almacen.ficheroFactura(f) != null) continue;
      try {
        final bytes = await _archivos.getFileDownload(
            bucketId: cubo, fileId: _idArchivo(f));
        await almacen.guardarFacturaBajada(f, bytes);
        almacen.marcarFotoSubida(f);
      } on AppwriteException catch (e) {
        if (e.code != 404) rethrow;
        // No está en el servidor: la ficha lo dirá ("foto no disponible").
      }
    }
  }

  /// La dirección pública de una foto del informe del taller. El taller la
  /// sube con lectura pública y un id imposible de adivinar, así que se pinta
  /// sin más sesión que la que haya.
  static String urlFotoInforme(String id) =>
      '$endpoint/storage/buckets/$cubo/files/$id/view?project=$proyecto';

  /// Baja las fotos del informe de una cita a la carpeta de la app y devuelve
  /// sus nombres de fichero, para que pasen al diario con la intervención.
  /// Las que ya estaban bajadas no se vuelven a pedir; las que fallan se
  /// saltan (la anotación vale igual, solo falta esa imagen).
  Future<List<String>> bajarFotosDelInforme(Almacen almacen, Cita c) async {
    final bajadas = Map<String, String>.from(c.fotosBajadas);
    final nombres = <String>[];
    for (final f in c.informeFotos) {
      final clave = f.id.isNotEmpty ? f.id : f.datos.hashCode.toString();
      final previo = bajadas[clave];
      if (previo != null && almacen.ficheroFactura(previo) != null) {
        nombres.add(previo);
        continue;
      }
      try {
        List<int> bytes;
        if (f.id.isNotEmpty) {
          final r = await http.get(Uri.parse(urlFotoInforme(f.id))).timeout(const Duration(seconds: 20));
          if (r.statusCode != 200) continue;
          bytes = r.bodyBytes;
        } else {
          final coma = f.datos.indexOf(',');
          if (coma < 0) continue;
          bytes = base64Decode(f.datos.substring(coma + 1));
        }
        final nombre = '${nuevoId('f')}.jpg';
        await almacen.guardarFacturaBajada(nombre, bytes);
        bajadas[clave] = nombre;
        nombres.add(nombre);
      } catch (_) {
        // sin red o foto borrada: se sigue con las demás
      }
    }
    if (bajadas.isNotEmpty) {
      c.informe['_bajadas'] = bajadas;
      await almacen.guardarCita(c);
    }
    return nombres;
  }
}

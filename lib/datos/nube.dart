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

import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as modelos;
import 'package:flutter/foundation.dart';

import 'almacen.dart';

class Nube extends ChangeNotifier {
  static const endpoint = 'https://fra.cloud.appwrite.io/v1';
  static const proyecto = '6a9a7983002332de60a5';
  static const bd = 'principal';
  static const tabla = 'documentos';
  static const cubo = 'facturas';

  /// La web atiende `?userId=…&secret=…` para poner clave nueva, así que el
  /// enlace del correo de recuperación apunta allí.
  static const urlRecuperacion = 'https://motora-42w.pages.dev/';

  late final Client _cliente;
  late final Account _cuenta;
  late final TablesDB _tablas;
  late final Storage _archivos;

  modelos.User? usuario;

  /// Ya se ha intentado recuperar la sesión al arrancar. Hasta entonces la
  /// app no sabe si hay cuenta o no, y no debe pintar "sin cuenta" un segundo
  /// para luego cambiar.
  bool arrancada = false;

  bool sincronizando = false;
  DateTime? ultimaSincronizacion;

  /// Lo último que pasó al sincronizar, para la pantalla del perfil. Null
  /// cuando fue bien.
  String? ultimoAviso;

  /// Se pone a false si el servidor contesta que la tabla o el cubo no
  /// existen: entonces la app lo dice en el perfil en vez de reintentar en
  /// silencio cada minuto.
  bool servidorListo = true;

  Nube() {
    _cliente = Client().setEndpoint(endpoint).setProject(proyecto);
    _cuenta = Account(_cliente);
    _tablas = TablesDB(_cliente);
    _archivos = Storage(_cliente);
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
    await _cuenta.createEmailPasswordSession(
        email: correo.trim(), password: clave);
    usuario = await _cuenta.get();
    notifyListeners();
  }

  Future<void> registrar(String nombre, String correo, String clave) async {
    await _cuenta.create(
      userId: ID.unique(),
      email: correo.trim(),
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
  Future<void> sincronizar(Almacen almacen) async {
    if (!conSesion || sincronizando) return;
    sincronizando = true;
    ultimoAviso = null;
    notifyListeners();
    try {
      await _sincronizarDeVerdad(almacen);
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
    final f = (datos['factura'] ?? '') as String;
    if (f.isEmpty || almacen.ficheroFactura(f) != null) return;
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

/// LA APP SE ACTUALIZA SOLA.
///
/// No hay tienda de por medio: las versiones viven como releases en GitHub,
/// con el APK adjunto. La app pregunta a la API pública de GitHub cuál es la
/// última, compara con la suya, y si hay una más nueva la descarga y abre el
/// instalador del sistema. Android pide confirmación la primera vez
/// ("permitir instalar apps de esta fuente") y la instala encima, conservando
/// los datos, porque todas las versiones van firmadas con la misma clave.
///
/// SE COMPRUEBA CON CALMA: una vez cada seis horas como mucho, y solo si hay
/// red. GitHub deja 60 consultas por hora sin autenticar y no hay motivo para
/// gastarlas en cada arranque.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Actualizacion extends ChangeNotifier {
  static const repo = 'joseantoniorumo99/mivehiculo-app';
  static const _claveUltimaComprobacion = 'act_ultima_comprobacion';
  static const _cadaHoras = 6;

  String versionActual = '';
  String? versionNueva;
  String? urlApk;
  int tamanoApk = 0;
  String notas = '';
  bool comprobando = false;
  bool descargando = false;
  double progreso = 0;
  String? error;
  DateTime? ultimaComprobacion;

  bool get hayNueva => versionNueva != null && urlApk != null;

  Future<void> leerVersionActual() async {
    if (versionActual.isNotEmpty) return;
    try {
      versionActual = (await PackageInfo.fromPlatform()).version;
      notifyListeners();
    } catch (_) {/* en pruebas no hay plataforma */}
  }

  /// Pregunta a GitHub. Con `forzar` se salta la espera de seis horas (el
  /// botón del perfil); sin él, respeta la calma.
  Future<void> comprobar({bool forzar = false}) async {
    if (comprobando) return;
    try {
      final p = await SharedPreferences.getInstance();
      final ultima = DateTime.tryParse(p.getString(_claveUltimaComprobacion) ?? '');
      ultimaComprobacion = ultima;
      if (!forzar && ultima != null && DateTime.now().difference(ultima).inHours < _cadaHoras) {
        return;
      }
      comprobando = true;
      error = null;
      notifyListeners();

      await leerVersionActual();

      final r = await http.get(
        Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'MiVehiculo/$versionActual',
        },
      ).timeout(const Duration(seconds: 12));
      await p.setString(_claveUltimaComprobacion, DateTime.now().toIso8601String());
      ultimaComprobacion = DateTime.now();
      if (r.statusCode != 200) {
        error = 'GitHub ha contestado ${r.statusCode}.';
        return;
      }
      final j = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
      final etiqueta = (j['tag_name'] ?? '') as String;
      final remota = etiqueta.startsWith('v') ? etiqueta.substring(1) : etiqueta;
      Map<String, dynamic>? apk;
      for (final a in (j['assets'] ?? []) as List) {
        final m = Map<String, dynamic>.from(a as Map);
        if ((m['name'] as String? ?? '').toLowerCase().endsWith('.apk')) {
          apk = m;
          break;
        }
      }
      if (apk == null || compararVersiones(remota, versionActual) <= 0) {
        versionNueva = null;
        urlApk = null;
        return;
      }
      versionNueva = remota;
      urlApk = apk['browser_download_url'] as String;
      tamanoApk = (apk['size'] as num?)?.toInt() ?? 0;
      notas = (j['body'] ?? '') as String;
    } catch (e) {
      // Sin red no es un error que enseñar: se vuelve a mirar otro día.
      if (e is! SocketException) error = e.toString();
    } finally {
      comprobando = false;
      notifyListeners();
    }
  }

  /// Baja el APK a la carpeta temporal y abre el instalador. Devuelve el
  /// motivo si no se pudo, o null si el instalador se abrió.
  Future<String?> descargarEInstalar() async {
    final url = urlApk;
    if (url == null || descargando) return 'No hay nada que descargar.';
    descargando = true;
    progreso = 0;
    error = null;
    notifyListeners();
    try {
      final carpeta = await getTemporaryDirectory();
      final destino =
          File('${carpeta.path}${Platform.pathSeparator}MiVehiculo-$versionNueva.apk');

      final cliente = http.Client();
      try {
        final respuesta = await cliente
            .send(http.Request('GET', Uri.parse(url)))
            .timeout(const Duration(seconds: 30));
        if (respuesta.statusCode != 200) {
          return 'La descarga ha contestado ${respuesta.statusCode}.';
        }
        final total = respuesta.contentLength ?? tamanoApk;
        var bajado = 0;
        final salida = destino.openWrite();
        await for (final trozo in respuesta.stream) {
          salida.add(trozo);
          bajado += trozo.length;
          if (total > 0) {
            final p = bajado / total;
            // Repintar cada 1 %: por trozo serían cientos de repintados/segundo.
            if (p - progreso >= 0.01) {
              progreso = p;
              notifyListeners();
            }
          }
        }
        await salida.close();
      } finally {
        cliente.close();
      }
      progreso = 1;
      notifyListeners();

      final r = await OpenFilex.open(destino.path,
          type: 'application/vnd.android.package-archive');
      if (r.type != ResultType.done) {
        return 'No se ha podido abrir el instalador: ${r.message}';
      }
      return null;
    } catch (e) {
      return e is SocketException ? 'Sin conexión.' : e.toString();
    } finally {
      descargando = false;
      notifyListeners();
    }
  }

  /// "1.10.0" > "1.9.3": se compara número a número, no como texto.
  static int compararVersiones(String a, String b) {
    List<int> partes(String v) =>
        v.split(RegExp(r'[.+-]')).map((x) => int.tryParse(x) ?? 0).toList();
    final pa = partes(a), pb = partes(b);
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}

/// Las páginas de la web a las que la app enlaza. En un solo sitio: si el
/// dominio cambia, se cambia aquí y en `Nube.urlRecuperacion`.
///
/// Van a la WEB a propósito y no como texto dentro de la app: el correo de
/// soporte o un párrafo de las condiciones se corrigen desplegando la web,
/// sin sacar una versión nueva de la app.
library;

import 'package:url_launcher/url_launcher.dart';

class Enlaces {
  static const web = 'https://motora-42w.pages.dev';
  static const privacidad = '$web/privacidad';
  static const condiciones = '$web/condiciones';
  static const soporte = '$web/soporte';
  static const borrarCuenta = '$web/soporte#borrar-cuenta';

  /// Abre la página en el navegador del sistema. Devuelve false si no hay
  /// ninguno que la abra (no pasa en un móvil normal).
  static Future<bool> abrir(String url) async {
    try {
      return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

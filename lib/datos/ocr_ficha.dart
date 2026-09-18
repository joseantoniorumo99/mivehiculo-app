/// LEER LA FICHA TÉCNICA DE UNA FOTO, en el propio móvil.
///
/// ML Kit reconoce el texto sin conexión y sin mandar la foto a ningún
/// sitio: la ficha técnica lleva el bastidor y la matrícula, y eso no tiene
/// por qué salir del teléfono. El modelo latino viene dentro de la app.
///
/// Devuelve el texto tal cual, línea a línea en el orden en que está en la
/// tarjeta (los bloques de ML Kit se ordenan de arriba abajo), y
/// `leerFichaTecnica()` se encarga de interpretarlo.
library;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

Future<String> textoDeLaFoto(String rutaFichero) async {
  final lector = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final r = await lector.processImage(InputImage.fromFilePath(rutaFichero));
    // Los bloques, de arriba abajo y de izquierda a derecha: así "D.1" y su
    // valor quedan en la misma línea o en líneas seguidas.
    final bloques = [...r.blocks]..sort((a, b) {
        final dy = a.boundingBox.top.compareTo(b.boundingBox.top);
        return dy != 0 ? dy : a.boundingBox.left.compareTo(b.boundingBox.left);
      });
    return bloques.map((b) => b.lines.map((l) => l.text).join('\n')).join('\n');
  } finally {
    await lector.close();
  }
}

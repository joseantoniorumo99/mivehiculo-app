/// PROTOCOLO OBD-II — puerto a Dart de `assets/obd.js`.
///
/// ESCRITO DESDE EL ESTÁNDAR, NO COPIADO DE NADIE:
///   · Comandos del adaptador → hoja de datos pública del ELM327.
///   · PIDs del modo 01 y sus fórmulas → SAE J1979.
///   · Estructura de los códigos de avería → SAE J2012.
/// AndrOBD se miró para entender cómo se comporta un adaptador real, que es
/// legítimo, pero NO se ha copiado nada suyo: es GPL-3.0 y obligaría a abrir
/// toda la app.
///
/// POR QUÉ ESTE FICHERO NO SABE NADA DE BLUETOOTH: el protocolo habla con un
/// `Transporte`, que solo tiene que saber mandar una línea y devolver lo que
/// conteste el adaptador. En la web había tres transportes (simulado, puerto
/// serie y BLE) sin tocar una coma de esto. En Android el transporte será
/// Bluetooth CLÁSICO, que es lo que ningún navegador puede hacer y por lo que
/// existe esta app.
library;

/// Un PID del modo 01: cuántos bytes devuelve y cómo se convierten en un
/// número. A, B, C, D es como los nombra el estándar.
///
/// NO TODO DATO ES UN NÚMERO. Unos cuantos PID del estándar son mapas de bits
/// o enumerados: a qué norma OBD responde el coche, en qué modo está el
/// sistema de combustible, qué sondas lambda monta. Ésos llevan `describir` en
/// lugar de `calcular` y valen tanto como los demás — el que dice si el
/// testigo del motor está encendido y cuántos códigos hay guardados es, de
/// hecho, el más útil de todos, y hasta hoy la app no lo pedía.
class Pid {
  final String nombre;
  final String unidad;
  final int bytes;
  final double Function(List<int> b)? calcular;
  final String Function(List<int> b)? describir;

  const Pid(this.nombre, this.unidad, this.bytes, this.calcular)
      : describir = null;

  const Pid.texto(this.nombre, this.bytes, this.describir)
      : unidad = '',
        calcular = null;
}

const Map<int, Pid> pids = {
  /// EL TESTIGO DEL MOTOR Y CUÁNTOS CÓDIGOS HAY. Lo soporta absolutamente
  /// todo coche con OBD-II —es el primer PID del estándar— y la app no lo
  /// pedía: se leían los códigos por el modo 03 pero no se decía si la luz
  /// estaba encendida, que es lo primero que quiere saber cualquiera.
  0x01: Pid.texto('Testigo del motor', 4, _testigo),

  0x03: Pid.texto('Sistema de combustible', 2, _sistemaCombustible),
  0x04: Pid('Carga del motor', '%', 1, _carga),
  0x05: Pid('Temperatura del refrigerante', '°C', 1, _menos40),
  0x06: Pid('Ajuste de mezcla corto (banco 1)', '%', 1, _ajuste),
  0x07: Pid('Ajuste de mezcla largo (banco 1)', '%', 1, _ajuste),
  0x0A: Pid('Presión de combustible', 'kPa', 1, _por3),
  0x0B: Pid('Presión del colector', 'kPa', 1, _crudoA),
  0x0C: Pid('Revoluciones', 'rpm', 2, _rpm),
  0x0D: Pid('Velocidad', 'km/h', 1, _crudoA),
  0x0E: Pid('Avance del encendido', '°', 1, _avance),
  0x0F: Pid('Temperatura del aire de admisión', '°C', 1, _menos40),
  0x10: Pid('Caudal de aire', 'g/s', 2, _maf),

  /// OJO CON EL NOMBRE. Este PID es la posición ABSOLUTA de la mariposa, y
  /// por diseño NO baja a cero: el sensor tiene un tope mecánico y en ralentí
  /// se queda entre el 10 y el 20 %. Llamarlo "posición del acelerador" hacía
  /// pensar que el pedal estaba pisado sin estarlo — pasó con un Opel real,
  /// que marcaba 14 % con el pie fuera. El dato era correcto; la etiqueta, no.
  /// El que sí baja a cero es el 0x45 (relativa) o el 0x5A (pedal).
  0x11: Pid('Mariposa (posición absoluta)', '%', 1, _carga),

  0x12: Pid.texto('Aire secundario', 1, _aireSecundario),
  0x13: Pid.texto('Sondas lambda montadas', 1, _sondas),

  /// LAS SONDAS LAMBDA, UNA A UNA. Son ocho PID seguidos y casi todos los
  /// coches dan al menos dos. Cada uno trae la tensión de la sonda (A/200 V)
  /// y el ajuste de mezcla que esa sonda provoca. Faltaban enteros: en un
  /// Opel real el coche anunciaba 0x14 y 0x15 y la app no los pedía.
  0x14: Pid('Sonda 1 · tensión', 'V', 2, _tensionSonda),
  0x15: Pid('Sonda 2 · tensión', 'V', 2, _tensionSonda),
  0x16: Pid('Sonda 3 · tensión', 'V', 2, _tensionSonda),
  0x17: Pid('Sonda 4 · tensión', 'V', 2, _tensionSonda),
  0x18: Pid('Sonda 5 · tensión', 'V', 2, _tensionSonda),
  0x19: Pid('Sonda 6 · tensión', 'V', 2, _tensionSonda),
  0x1A: Pid('Sonda 7 · tensión', 'V', 2, _tensionSonda),
  0x1B: Pid('Sonda 8 · tensión', 'V', 2, _tensionSonda),

  0x1C: Pid.texto('Norma OBD del coche', 1, _normaObd),
  0x1F: Pid('Tiempo desde el arranque', 's', 2, _dosBytes),
  0x21: Pid('Distancia con el testigo encendido', 'km', 2, _dosBytes),
  0x22: Pid('Presión del combustible (relativa)', 'kPa', 2, _presionRelativa),
  0x23: Pid('Presión del raíl', 'kPa', 2, _presionRail),
  0x2C: Pid('EGR mandada', '%', 1, _carga),
  0x2D: Pid('Error de EGR', '%', 1, _ajuste),
  0x2E: Pid('Purga del canister', '%', 1, _carga),
  0x2F: Pid('Nivel de combustible', '%', 1, _carga),
  0x30: Pid('Calentamientos desde el último borrado', '', 1, _crudoA),
  0x31: Pid('Distancia desde el último borrado', 'km', 2, _dosBytes),
  0x32: Pid('Presión de vapores del depósito', 'Pa', 2, _vapores),
  0x33: Pid('Presión barométrica', 'kPa', 1, _crudoA),
  0x3C: Pid('Temperatura del catalizador 1', '°C', 2, _tempCatalizador),
  0x3D: Pid('Temperatura del catalizador 2', '°C', 2, _tempCatalizador),
  0x3E: Pid('Temperatura del catalizador 3', '°C', 2, _tempCatalizador),
  0x3F: Pid('Temperatura del catalizador 4', '°C', 2, _tempCatalizador),
  0x42: Pid('Tensión de la centralita', 'V', 2, _milivoltios),
  0x43: Pid('Carga absoluta', '%', 2, _cargaAbsoluta),
  0x44: Pid('Mezcla mandada (lambda)', '', 2, _lambda),
  0x45: Pid('Acelerador (posición relativa)', '%', 1, _carga),
  0x46: Pid('Temperatura exterior', '°C', 1, _menos40),
  0x47: Pid('Mariposa B (absoluta)', '%', 1, _carga),
  0x48: Pid('Mariposa C (absoluta)', '%', 1, _carga),
  0x49: Pid('Pedal del acelerador', '%', 1, _carga),
  0x4A: Pid('Pedal E', '%', 1, _carga),
  0x4B: Pid('Pedal F', '%', 1, _carga),
  0x4C: Pid('Apertura de mariposa mandada', '%', 1, _carga),
  0x4D: Pid('Tiempo con el testigo encendido', 'min', 2, _dosBytes),
  0x4E: Pid('Tiempo desde el último borrado', 'min', 2, _dosBytes),
  0x51: Pid.texto('Combustible que usa', 1, _tipoCombustible),
  0x52: Pid('Etanol en el combustible', '%', 1, _carga),
  0x53: Pid('Presión absoluta de vapores', 'kPa', 2, _vaporesAbsoluta),
  0x5A: Pid('Pedal (posición relativa)', '%', 1, _carga),
  0x5B: Pid('Carga de la batería híbrida', '%', 1, _carga),
  0x5C: Pid('Temperatura del aceite', '°C', 1, _menos40),
  0x5E: Pid('Consumo instantáneo', 'L/h', 2, _consumo),
  0x5F: Pid('Norma de emisiones', '', 1, _crudoA),
  0x61: Pid('Par pedido por el conductor', '%', 1, _parMotor),
  0x62: Pid('Par motor real', '%', 1, _parMotor),
  0x63: Pid('Par motor de referencia', 'Nm', 2, _dosBytes),
  0x7F: Pid('Horas de funcionamiento del motor', 'h', 4, _horas),

  /// El cuentakilómetros. Lo pide todo el mundo y casi ningún coche lo da:
  /// es del modo 01 solo desde 2021, y antes de eso el dato vive en el cuadro
  /// y no en la centralita del motor. Si el coche lo soporta, aquí sale.
  0xA6: Pid('Cuentakilómetros', 'km', 4, _odometro),
};

double _carga(List<int> b) => (b[0] * 100) / 255;
double _menos40(List<int> b) => (b[0] - 40).toDouble();
double _crudoA(List<int> b) => b[0].toDouble();
double _por3(List<int> b) => (b[0] * 3).toDouble();
// Los ajustes de mezcla y el par van con SIGNO: 128 es el cero
double _ajuste(List<int> b) => (b[0] * 100 / 128) - 100;
double _parMotor(List<int> b) => (b[0] - 125).toDouble();
double _avance(List<int> b) => (b[0] / 2) - 64;
double _cargaAbsoluta(List<int> b) => ((256 * b[0] + b[1]) * 100) / 255;
double _horas(List<int> b) =>
    (b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]).toDouble() / 3600;
double _odometro(List<int> b) =>
    (b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]).toDouble() / 10;
double _rpm(List<int> b) => (256 * b[0] + b[1]) / 4;
double _maf(List<int> b) => (256 * b[0] + b[1]) / 100;
double _dosBytes(List<int> b) => (256 * b[0] + b[1]).toDouble();
double _milivoltios(List<int> b) => (256 * b[0] + b[1]) / 1000;
double _consumo(List<int> b) => (256 * b[0] + b[1]) / 20;
double _tensionSonda(List<int> b) => b[0] / 200;
double _presionRelativa(List<int> b) => (256 * b[0] + b[1]) * 0.079;
double _presionRail(List<int> b) => (256 * b[0] + b[1]) * 10;
double _tempCatalizador(List<int> b) => ((256 * b[0] + b[1]) / 10) - 40;
double _lambda(List<int> b) => (256 * b[0] + b[1]) * 2 / 65536;
double _vaporesAbsoluta(List<int> b) => (256 * b[0] + b[1]) / 200;

/// Con SIGNO y en complemento a dos: la presión de vapores puede ser negativa
/// (depósito en depresión) y leerla sin signo da saltos de 65.000 Pa que
/// parecen una avería gravísima y no son nada.
double _vapores(List<int> b) {
  final crudo = 256 * b[0] + b[1];
  return (crudo > 32767 ? crudo - 65536 : crudo).toDouble();
}

/// PID 01: los dos primeros bits del byte A son el testigo del motor y
/// cuántos códigos hay guardados. Lo demás del byte son los monitores de a
/// bordo, que solo le dicen algo a un taller.
String _testigo(List<int> b) {
  final encendido = (b[0] & 0x80) != 0;
  final cuantos = b[0] & 0x7F;
  if (!encendido && cuantos == 0) return 'Apagado · sin códigos guardados';
  final codigos = cuantos == 1 ? '1 código guardado' : '$cuantos códigos guardados';
  return encendido ? 'ENCENDIDO · $codigos' : 'Apagado · $codigos';
}

const List<String> _modosCombustible = [
  'Sin datos',
  'En bucle abierto: motor todavía frío',
  'En bucle cerrado: usando la sonda lambda',
  'En bucle abierto: por carga o deceleración',
  'En bucle abierto: por fallo del sistema',
  'En bucle cerrado con algún fallo de sonda',
];

String _sistemaCombustible(List<int> b) {
  final valor = b[0];
  if (valor == 0) return 'Sin datos';
  // Es un mapa de bits: solo hay uno activo, y su posición es el modo
  for (var i = 0; i < 8; i++) {
    if ((valor & (1 << i)) != 0) {
      return i + 1 < _modosCombustible.length
          ? _modosCombustible[i + 1]
          : 'Modo $i';
    }
  }
  return 'Sin datos';
}

String _aireSecundario(List<int> b) {
  if ((b[0] & 0x01) != 0) return 'Al escape antes del catalizador';
  if ((b[0] & 0x02) != 0) return 'Aguas abajo del catalizador';
  if ((b[0] & 0x04) != 0) return 'A la atmósfera o desconectado';
  if ((b[0] & 0x08) != 0) return 'Bombeando para diagnóstico';
  return 'Sin datos';
}

String _sondas(List<int> b) {
  final presentes = <String>[];
  for (var i = 0; i < 8; i++) {
    if ((b[0] & (1 << i)) != 0) {
      presentes.add('banco ${i < 4 ? 1 : 2} · sonda ${(i % 4) + 1}');
    }
  }
  return presentes.isEmpty ? 'Ninguna declarada' : presentes.join(', ');
}

const Map<int, String> _normasObd = {
  1: 'OBD-II (California, ARB)',
  2: 'OBD (federal, EPA)',
  3: 'OBD y OBD-II',
  4: 'OBD-I',
  5: 'Sin OBD de a bordo',
  6: 'EOBD (Europa)',
  7: 'EOBD y OBD-II',
  8: 'EOBD y OBD',
  9: 'EOBD, OBD y OBD-II',
  10: 'JOBD (Japón)',
  11: 'JOBD y OBD-II',
  12: 'JOBD y EOBD',
  13: 'JOBD, EOBD y OBD-II',
};

String _normaObd(List<int> b) => _normasObd[b[0]] ?? 'Norma ${b[0]}';

const Map<int, String> _tiposCombustible = {
  1: 'Gasolina',
  2: 'Metanol',
  3: 'Etanol',
  4: 'Gasóleo',
  5: 'GLP',
  6: 'Gas natural comprimido',
  7: 'Propano',
  8: 'Eléctrico',
  9: 'Bifuel con gasolina',
  10: 'Bifuel con metanol',
  11: 'Bifuel con etanol',
  12: 'Bifuel con GLP',
  13: 'Bifuel con gas natural',
  14: 'Bifuel con propano',
  15: 'Bifuel eléctrico',
  17: 'Híbrido de gasolina',
  18: 'Híbrido de gasóleo',
  19: 'Híbrido eléctrico',
  23: 'Híbrido enchufable',
};

String _tipoCombustible(List<int> b) =>
    _tiposCombustible[b[0]] ?? 'Tipo ${b[0]}';

/// El orden en que se ENSEÑAN los datos, de más a menos interesante para una
/// persona. No es la lista de lo que se pide: eso lo decide el coche.
///
/// Antes esto ERA la lista de lo que se pedía, y con un Opel real cinco de
/// los diez PID contestaron `7F 01 10` (no soportado) mientras el coche tenía
/// otros que nadie le preguntó. Preguntar primero qué soporta y leer todo eso
/// da más datos y además evita esperar por respuestas que no van a llegar.
const List<int> ordenDeInteres = [
  0x01, 0xA6, 0x42, 0x05, 0x2F, 0x0C, 0x0D, 0x5C, 0x46, 0x11, 0x45, 0x5A,
  0x04, 0x43, 0x10, 0x0B, 0x33, 0x0F, 0x03, 0x1C, 0x51, 0x1F, 0x7F,
  0x21, 0x31, 0x4D, 0x4E, 0x13, 0x14, 0x15,
];

/// Ordena lo leído por interés. Detrás de los de la lista van los demás que la
/// app SÍ entiende, y al final del todo los que solo sabe repetir en
/// hexadecimal: son datos de verdad y tienen que verse, pero no compitiendo
/// por el sitio con la temperatura del refrigerante.
List<Lectura> porInteres(List<Lectura> lecturas) {
  int rango(Lectura l) {
    if (!l.reconocido) return 10000 + l.pid;
    final i = ordenDeInteres.indexOf(l.pid);
    return i < 0 ? 1000 + l.pid : i;
  }

  final copia = [...lecturas];
  copia.sort((a, b) => rango(a).compareTo(rango(b)));
  return copia;
}

class Lectura {
  final int pid;
  final String nombre;
  final String unidad;

  /// Null cuando el dato no es un número (un enumerado, un mapa de bits, o un
  /// PID que esta app todavía no sabe interpretar).
  final double? valor;

  /// Lo que se enseña cuando no hay número. Para un PID desconocido son sus
  /// bytes en hexadecimal, que no es bonito pero es LA VERDAD y se puede
  /// buscar; callárselo sería peor.
  final String? texto;

  /// Los bytes tal cual llegaron. Se guardan siempre: es lo que permite
  /// enseñar el volcado sin tener que repetir la conversación con el coche.
  final List<int> crudo;

  const Lectura(
    this.pid,
    this.nombre,
    this.unidad,
    this.valor, {
    this.texto,
    this.crudo = const [],
  });

  bool get esNumero => valor != null;

  /// Si la app sabe lo que significa o solo sabe repetirlo. Se usa para
  /// agrupar al final los que no entiende, en vez de mezclarlos con los demás
  /// y que parezca que el coche contesta cosas raras.
  bool get reconocido => pids.containsKey(pid);
}

class Averia {
  final String codigo;
  final String descripcion;
  const Averia(this.codigo, this.descripcion);
}

/// Por dónde viaja el diálogo. Lo implementa el Bluetooth clásico, y también
/// un simulador para poder probar sin coche.
abstract class Transporte {
  Future<String> enviar(String comando);
  Future<void> cerrar();
}

String _hex2(int n) => n.toRadixString(16).toUpperCase().padLeft(2, '0');

/// Un ELM327 contesta en hexadecimal, pero CÓMO lo escribe depende de su
/// configuración: con ATS0 manda "410C1AF8" de una pieza; sin él, "41 0C 1A
/// F8". Y por el medio cuela texto suyo (SEARCHING..., NO DATA, BUS INIT) y
/// numeración de trama ("0:", "1:").
///
/// LOS PUNTOS SE QUITAN ANTES DE MIRAR SI ES HEXADECIMAL. Mientras busca el
/// protocolo, el ELM327 escribe un punto por intento y los pega a la
/// respuesta: `SEARCHING... ..4100FE3FB811`. Exigir hexadecimal puro tiraba
/// ese trozo ENTERO, y con él la respuesta. Se notó tarde porque el primer
/// comando de la sesión solía ser uno que el coche no soporta, así que
/// perderlo daba igual; en cuanto el primero pasó a ser el que pregunta qué
/// PID soporta, la lectura se quedó en blanco.
List<int> aBytes(String texto) {
  final trozos = texto.split(RegExp(r'[\s>]+'));
  final hex = StringBuffer();
  for (final bruto in trozos) {
    final t = bruto.replaceAll('.', '');
    if (t.isEmpty || t.contains(':')) continue;
    if (!RegExp(r'^[0-9A-Fa-f]+$').hasMatch(t)) continue;
    hex.write(t);
  }
  final s = hex.toString();
  final bytes = <int>[];
  for (var i = 0; i + 1 < s.length; i += 2) {
    bytes.add(int.parse(s.substring(i, i + 2), radix: 16));
  }
  return bytes;
}

bool esError(String texto) => RegExp(
      r'NO DATA|ERROR|UNABLE TO CONNECT|STOPPED|CAN ERROR|BUS INIT|\?',
      caseSensitive: false,
    ).hasMatch(texto);

/// El bastidor llega en VARIAS TRAMAS, y cada una empieza por su cabecera
/// `49 02 NN` (NN = número de trama). Hay que partir por esas cabeceras y
/// quedarse solo con los datos.
///
/// La primera versión filtraba el flujo entero por "solo letras y dígitos", y
/// eso dejaba pasar el propio `0x49` de cada cabecera — que en ASCII es la
/// letra **I**. Con un Opel real (W0L0TGF4836137256) salía
/// `0TIGF48I3613I7256`: tres íes metidas de contrabando, las tres primeras
/// letras perdidas y un bastidor que no es el del coche. Un bastidor mal leído
/// es peor que ninguno, porque es el que ata el historial a ESE coche.
String? vinDeRespuesta(List<int> bytes) {
  final trozos = <int>[];
  var i = 0;
  var encontrado = false;
  while (i + 2 < bytes.length) {
    if (bytes[i] == 0x49 && bytes[i + 1] == 0x02) {
      encontrado = true;
      // El byte i+2 es el número de trama; los datos empiezan detrás
      var j = i + 3;
      while (j + 2 < bytes.length && !(bytes[j] == 0x49 && bytes[j + 1] == 0x02)) {
        trozos.add(bytes[j]);
        j++;
      }
      // La última trama no tiene otra detrás: se recoge hasta el final
      if (!(j + 2 < bytes.length)) {
        while (j < bytes.length) {
          trozos.add(bytes[j]);
          j++;
        }
      }
      i = j;
    } else {
      i++;
    }
  }
  if (!encontrado) return null;

  // Los bytes de relleno a cero de la primera trama no son parte del bastidor
  final texto = trozos
      .where((b) => (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A))
      .map((b) => String.fromCharCode(b))
      .join();
  if (texto.isEmpty) return null;
  // Un VIN son 17 caracteres; si llega de más, los buenos son los últimos
  return texto.length > 17 ? texto.substring(texto.length - 17) : texto;
}

const List<String> _sistemas = ['P', 'C', 'B', 'U'];

/// Cada código son 2 bytes: los dos primeros bits dicen el sistema, los dos
/// siguientes el primer dígito, y el resto son tres dígitos hex.
String? decodificarDtc(int alto, int bajo) {
  if (alto == 0 && bajo == 0) return null; // hueco vacío, no es un código
  final sistema = _sistemas[(alto & 0xC0) >> 6];
  final primerDigito = (alto & 0x30) >> 4;
  final resto = (alto & 0x0F).toRadixString(16) + _hex2(bajo).toLowerCase();
  return '$sistema$primerDigito$resto'.toUpperCase();
}

/// Qué significa un código, hasta donde se puede decir SIN INVENTAR. La letra
/// y el primer dígito están en el estándar; la avería concreta depende del
/// fabricante, y ahí es mejor callarse que adivinar.
const Map<String, String> _familias = {
  'P0': 'Motor o transmisión · código genérico',
  'P1': 'Motor o transmisión · específico del fabricante',
  'P2': 'Motor o transmisión · código genérico',
  'P3': 'Motor o transmisión · genérico o del fabricante',
  'C0': 'Chasis · código genérico',
  'C1': 'Chasis · específico del fabricante',
  'B0': 'Carrocería · código genérico',
  'B1': 'Carrocería · específico del fabricante',
  'U0': 'Red de comunicación · código genérico',
  'U1': 'Red de comunicación · específico del fabricante',
};

String describirDtc(String codigo) =>
    _familias[codigo.substring(0, 2)] ?? 'Código de avería';

/// Arranque de un ELM327, tal cual viene en su hoja de datos.
const List<String> arranque = ['ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP0'];

/// El diálogo con el adaptador. `mirar` es opcional y sirve para que un banco
/// de pruebas registre CADA comando y CADA respuesta: sin eso, un volcado no
/// enseñaría los mapas de PID soportados y mentiría por omisión justo en la
/// parte que explica por qué falta un dato.
class Sesion {
  final Transporte transporte;
  final void Function(String que, String texto)? mirar;
  bool _iniciada = false;

  Sesion(this.transporte, {this.mirar});

  Future<String> mandar(String comando) async {
    mirar?.call('envia', comando);
    String r;
    try {
      r = await transporte.enviar(comando);
    } catch (e) {
      mirar?.call('falla', e.toString());
      rethrow;
    }
    mirar?.call('recibe', r);
    return r;
  }

  Future<bool> iniciar() async {
    if (_iniciada) return true;
    for (final c in arranque) {
      final r = await mandar(c);
      // ATZ contesta con su versión; los demás con OK. Si algo falla, se corta.
      if (esError(r) && c != 'ATZ') return false;
    }
    _iniciada = true;
    return true;
  }

  /// Los bytes de datos de un PID, sin interpretar. Devuelve null si el coche
  /// no contesta a eso.
  Future<List<int>?> leerPidCrudo(int pid, {int? cuantos}) async {
    final r = await mandar('01${_hex2(pid)}');
    if (esError(r)) return null;

    final bytes = aBytes(r);

    /// La respuesta empieza por 41 y repite el PID pedido. Se busca esa pareja
    /// en vez de dar por hecho que va la primera: algunos coches cuelan bytes
    /// antes, y un byte de desplazamiento cambia el valor entero.
    var i = bytes.indexOf(0x41);
    while (i >= 0 && (i + 1 >= bytes.length || bytes[i + 1] != pid)) {
      i = bytes.indexOf(0x41, i + 1);
    }
    if (i < 0) return null;

    final datos = bytes.sublist(i + 2);
    if (cuantos == null) return datos.isEmpty ? null : datos;
    if (datos.length < cuantos) return null;
    return datos.sublist(0, cuantos);
  }

  /// Una lectura del modo 01. Devuelve null si el coche no da ese dato.
  ///
  /// UN PID QUE ESTA APP NO CONOCE NO SE TIRA A LA BASURA. Si el coche lo
  /// anuncia y lo contesta, sale con su número de PID y sus bytes en
  /// hexadecimal. Antes se descartaba en silencio, y el resultado era una
  /// pantalla con menos datos de los que el coche había dado sin explicar por
  /// qué faltaban: la app parecía rota cuando el que no llegaba era yo.
  Future<Lectura?> leerPid(int pid) async {
    final def = pids[pid];
    final datos = await leerPidCrudo(pid, cuantos: def?.bytes);
    if (datos == null) return null;

    if (def == null) {
      return Lectura(pid, 'PID 0x${_hex2(pid)}', '', null,
          texto: datos.map(_hex2).join(' '), crudo: datos);
    }
    if (def.describir != null) {
      return Lectura(pid, def.nombre, '', null,
          texto: def.describir!(datos), crudo: datos);
    }
    return Lectura(pid, def.nombre, def.unidad, def.calcular!(datos),
        crudo: datos);
  }

  /// Lee lo que el coche DE VERDAD ofrece.
  ///
  /// Primero le pregunta qué PID soporta (los mapas de bits del 01 00/20/40),
  /// y de esos lee los que esta app sabe interpretar. Antes se leía una lista
  /// fija de diez, y con un coche real la mitad contestaba "no soportado"
  /// mientras otros datos que sí tenía no se pedían nunca.
  ///
  /// `avisar` va para poder enseñar el progreso: preguntar de uno en uno son
  /// unos segundos y quedarse mudo parece que se ha colgado.
  Future<List<Lectura>> leerLoQueHaya({
    void Function(int hechos, int total)? avisar,
  }) async {
    final soportados = await pidsSoportados();

    /// SE PIDE TODO LO QUE EL COCHE ANUNCIA, no solo lo que la app sabe
    /// traducir. Los que no conoce salen con su número de PID y su
    /// hexadecimal, y así el usuario ve lo mismo que ve el protocolo. Antes se
    /// filtraba aquí y la pantalla enseñaba doce datos de los dieciocho que el
    /// coche había dicho tener, sin decir en ningún sitio que faltaban seis.
    var utiles = [...soportados];

    /// SI LA ENUMERACIÓN NO DA NADA, SE PRUEBA IGUAL. El primer comando de una
    /// sesión llega sucio (el ELM327 escupe SEARCHING y puntos mientras busca
    /// el protocolo) y si justo ese es el que pregunta qué PID hay, un fallo
    /// de lectura dejaba la pantalla EN BLANCO teniendo el coche delante. Peor
    /// que preguntar de más es no preguntar nada.
    if (utiles.isEmpty) {
      utiles = ordenDeInteres.where(pids.containsKey).toList();
    }

    final salida = <Lectura>[];
    for (var i = 0; i < utiles.length; i++) {
      avisar?.call(i + 1, utiles.length);
      final r = await leerPid(utiles[i]);
      if (r != null) salida.add(r);
    }
    return porInteres(salida);
  }

  /// Leer una lista concreta, para cuando ya se sabe qué se quiere.
  Future<List<Lectura>> leerTodo([List<int>? lista]) async {
    final salida = <Lectura>[];
    for (final pid in lista ?? ordenDeInteres) {
      final r = await leerPid(pid);
      if (r != null) salida.add(r);
    }
    return porInteres(salida);
  }

  /// Modo 01 PID 00/20/40/60: el coche dice QUÉ sabe contestar. La respuesta
  /// son 4 bytes = 32 bits, uno por PID del tramo. El último bit de cada tramo
  /// no es un dato: dice si hay tramo siguiente, y preguntar por uno que no se
  /// anuncia devuelve NO DATA y hace perder segundos.
  Future<List<int>> pidsSoportados() async {
    final lista = <int>[];
    var base = 0x00;
    while (base <= 0xC0) {
      final r = await mandar('01${_hex2(base)}');
      if (esError(r)) break;
      final bytes = aBytes(r);
      var i = bytes.indexOf(0x41);
      while (i >= 0 && (i + 1 >= bytes.length || bytes[i + 1] != base)) {
        i = bytes.indexOf(0x41, i + 1);
      }
      if (i < 0 || bytes.length < i + 6) break;

      final mapa = bytes.sublist(i + 2, i + 6);
      var siguiente = false;
      for (var b = 0; b < 4; b++) {
        for (var bit = 0; bit < 8; bit++) {
          if ((mapa[b] & (0x80 >> bit)) == 0) continue;
          final pid = base + b * 8 + bit + 1;
          if ((pid & 0x1F) == 0) {
            siguiente = true;
            continue;
          }
          lista.add(pid);
        }
      }
      if (!siguiente) break;
      base += 0x20;
    }
    return lista;
  }

  /// Modo 03: códigos guardados. Modo 07: los pendientes, aún sin confirmar.
  Future<List<Averia>> leerCodigos([int modo = 3]) async {
    final r = await mandar(modo == 7 ? '07' : '03');
    if (esError(r)) return [];
    final bytes = aBytes(r);
    final i = bytes.indexOf(modo == 7 ? 0x47 : 0x43);
    if (i < 0) return [];

    /// Tras 43 va el número de códigos y luego las parejas... salvo en los
    /// protocolos que no son CAN, donde algunos adaptadores se saltan la
    /// cuenta. Si se da por hecho que está, un byte de desplazamiento
    /// convierte P0420 en P0204 y el usuario se lleva un susto ajeno. Se
    /// comprueba: si ese byte cuadra con las parejas de detrás, es la cuenta.
    var cuerpo = bytes.sublist(i + 1);
    if (cuerpo.length > 1 && (cuerpo.length - 1) / 2 == cuerpo[0]) {
      cuerpo = cuerpo.sublist(1);
    }
    final vistos = <String>{};
    final salida = <Averia>[];
    for (var p = 0; p + 1 < cuerpo.length; p += 2) {
      final c = decodificarDtc(cuerpo[p], cuerpo[p + 1]);
      if (c != null && vistos.add(c)) salida.add(Averia(c, describirDtc(c)));
    }
    return salida;
  }

  /// Modo 09 PID 02: el bastidor, que llega en trozos y como texto ASCII.
  Future<String?> leerVin() async {
    final r = await mandar('0902');
    if (esError(r)) return null;
    return vinDeRespuesta(aBytes(r));
  }

  /// Modo 04: borrar códigos y apagar el testigo. NO se llama desde ninguna
  /// pantalla a propósito: borrar sin leer antes tira a la basura la
  /// información de una avería que el taller aún no ha visto.
  Future<bool> borrarCodigos() async => !esError(await mandar('04'));
}

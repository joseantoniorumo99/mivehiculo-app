/// EL MODELO DE DATOS. Lo que el dueño del coche escribe y nadie más.
///
/// Todo lo de aquí se guarda en el móvil y sale del móvil solo si él lo manda
/// (compartir el expediente, pedir una cita). Por eso cada clase sabe
/// convertirse a JSON y volver: el guardado es un fichero de texto que se
/// puede leer, copiar y respaldar sin depender de ningún servidor.
///
/// UNA REGLA QUE ATRAVIESA TODO EL FICHERO: un hueco vacío NO es un cero.
/// `km` nulo es "no lo sé"; `km` 0 es "el cuentakilómetros marcaba cero".
/// Confundirlos es lo que hace que una app enseñe un coche sin usar o un gasto
/// de 0 € donde en realidad no hay dato. Por eso los números que pueden faltar
/// son `int?` y `double?`, y no `int` con cero por defecto.
library;

/// Genera identificadores sin depender de un paquete: momento en milisegundos
/// más un contador. No hacen falta UUID —esto no se sincroniza con nadie— y
/// sí hace falta que dos anotaciones seguidas no compartan id.
int _secuencia = 0;
String nuevoId(String prefijo) {
  _secuencia = (_secuencia + 1) % 1000;
  return '$prefijo${DateTime.now().millisecondsSinceEpoch}'
      '${_secuencia.toString().padLeft(3, '0')}';
}

/// Los tipos de mantenimiento que la app conoce. La CLAVE es lo que se guarda
/// y con lo que se cuadran los avisos; el texto es lo que se lee. Cambiar una
/// clave rompe el historial ya escrito, así que no se cambian.
const Map<String, String> tiposMantenimiento = {
  'aceite': 'Cambio de aceite y filtro',
  'rueda': 'Neumáticos',
  'freno': 'Frenos',
  'itv': 'ITV',
  'filtro': 'Filtros (aire / habitáculo)',
  'bateria': 'Batería',
  'correa': 'Correa de distribución',
  'revision': 'Revisión general',
  'otro': 'Otro',
};

class Vehiculo {
  String id;
  String marca;
  String modelo;
  int? anio;

  /// Primera matriculación, "AAAA-MM" o "AAAA-MM-DD". La matrícula española da
  /// el mes, no el día, y con el mes ya se puede decir cuándo toca la ITV de
  /// verdad en vez de aproximarla por el año. Vacía = no se sabe.
  String matriculacion;

  String combustible;
  String matricula;
  int? km;

  /// "si" | "no" | "quizas" cuando lo ha confirmado el dueño mirando el tapón,
  /// y "auto" cuando deja que se deduzca de la normativa. "auto" NO es lo
  /// mismo que guardar la deducción de hoy congelada: si mañana afinamos la
  /// regla, el coche con "auto" se beneficia y el confirmado no se toca.
  String adBlue;

  /// El bastidor, cuando el lector OBD lo ha sacado. Es lo que ata el
  /// historial a ESTE coche y no a otro del mismo modelo.
  String bastidor;

  Vehiculo({
    String? id,
    this.marca = '',
    this.modelo = '',
    this.anio,
    this.matriculacion = '',
    this.combustible = '',
    this.matricula = '',
    this.km,
    this.adBlue = 'auto',
    this.bastidor = '',
  }) : id = id ?? nuevoId('v');

  String get nombre {
    final n = '$marca $modelo'.trim();
    return n.isEmpty ? (matricula.isEmpty ? 'Mi coche' : matricula) : n;
  }

  /// El año que vale para calcular: el de la matriculación si consta, y si no
  /// el que se haya escrito a mano.
  int? get anioEfectivo {
    if (matriculacion.length >= 4) {
      final a = int.tryParse(matriculacion.substring(0, 4));
      if (a != null && a > 1900) return a;
    }
    return anio;
  }

  Map<String, dynamic> aJson() => {
        'id': id,
        'marca': marca,
        'modelo': modelo,
        'anio': anio,
        'matriculacion': matriculacion,
        'combustible': combustible,
        'matricula': matricula,
        'km': km,
        'adBlue': adBlue,
        'bastidor': bastidor,
      };

  static Vehiculo deJson(Map<String, dynamic> j) => Vehiculo(
        id: j['id'] as String?,
        marca: (j['marca'] ?? '') as String,
        modelo: (j['modelo'] ?? '') as String,
        anio: _entero(j['anio']),
        matriculacion: (j['matriculacion'] ?? '') as String,
        combustible: (j['combustible'] ?? '') as String,
        matricula: (j['matricula'] ?? '') as String,
        km: _entero(j['km']),
        adBlue: (j['adBlue'] ?? 'auto') as String,
        bastidor: (j['bastidor'] ?? '') as String,
      );
}

/// Una línea del desglose de la factura.
///
/// Existe porque una factura de taller de verdad son cinco cosas —diagnosis,
/// motor de arranque, brazo de suspensión, aceite, mano de obra— y guardarla
/// como "Revisión general · 700 €" pierde justo lo que querría ver quien
/// compre el coche.
class Linea {
  String concepto;
  double importe;

  /// La clave de `tiposMantenimiento`, o vacío si esa línea no es un
  /// mantenimiento reconocible (mano de obra, por ejemplo).
  String tipo;

  Linea({this.concepto = '', this.importe = 0, this.tipo = ''});

  Map<String, dynamic> aJson() =>
      {'concepto': concepto, 'importe': importe, 'tipo': tipo};

  static Linea deJson(Map<String, dynamic> j) => Linea(
        concepto: (j['concepto'] ?? '') as String,
        importe: _decimal(j['importe']) ?? 0,
        tipo: (j['tipo'] ?? '') as String,
      );
}

/// Una entrada del diario: algo que se le hizo al coche.
class Intervencion {
  String id;
  String vehiculoId;

  /// "AAAA-MM-DD". Se guarda como texto a propósito: ordena bien por
  /// comparación de cadenas, se lee tal cual en el fichero de respaldo, y no
  /// arrastra zona horaria —una fecha de factura no tiene hora ni huso—.
  String fecha;

  /// La clave del tipo. Con varios conceptos distintos es "revision" A
  /// PROPÓSITO: poner "bateria" porque aparece un motor de arranque
  /// escondería el brazo de suspensión que iba en la misma factura.
  String tipo;

  String titulo;
  String taller;
  String nota;
  int? km;
  double? coste;
  List<Linea> lineas;

  /// Nombre del fichero de la foto de la factura dentro de la carpeta de la
  /// app. Se guarda el NOMBRE y no la ruta entera: en Android la carpeta de
  /// datos cambia de ruta entre instalaciones y una ruta absoluta guardada
  /// deja de existir.
  String factura;

  Intervencion({
    String? id,
    required this.vehiculoId,
    required this.fecha,
    this.tipo = 'otro',
    this.titulo = '',
    this.taller = '',
    this.nota = '',
    this.km,
    this.coste,
    List<Linea>? lineas,
    this.factura = '',
  })  : id = id ?? nuevoId('i'),
        lineas = lineas ?? [];

  String get tituloEfectivo => titulo.trim().isNotEmpty
      ? titulo.trim()
      : (tiposMantenimiento[tipo] ?? 'Intervención');

  /// Lo que suma el desglose. Es la BASE imponible, no el total: se compara
  /// con lo escrito arriba para avisar de que el IVA va aparte, porque si no
  /// parece un error de lectura.
  double get sumaLineas => lineas.fold(0.0, (s, l) => s + l.importe);

  /// Todos los tipos que toca esta intervención, contando el desglose. Es lo
  /// que permite que el aviso del aceite se dé por atendido cuando el aceite
  /// iba dentro de una revisión general.
  Set<String> get tiposTocados => {
        tipo.toLowerCase(),
        ...lineas.map((l) => l.tipo.toLowerCase()).where((t) => t.isNotEmpty),
      };

  Map<String, dynamic> aJson() => {
        'id': id,
        'vehiculoId': vehiculoId,
        'fecha': fecha,
        'tipo': tipo,
        'titulo': titulo,
        'taller': taller,
        'nota': nota,
        'km': km,
        'coste': coste,
        'lineas': lineas.map((l) => l.aJson()).toList(),
        'factura': factura,
      };

  static Intervencion deJson(Map<String, dynamic> j) => Intervencion(
        id: j['id'] as String?,
        vehiculoId: (j['vehiculoId'] ?? '') as String,
        fecha: (j['fecha'] ?? '') as String,
        tipo: (j['tipo'] ?? 'otro') as String,
        titulo: (j['titulo'] ?? '') as String,
        taller: (j['taller'] ?? '') as String,
        nota: (j['nota'] ?? '') as String,
        km: _entero(j['km']),
        coste: _decimal(j['coste']),
        lineas: ((j['lineas'] ?? []) as List)
            .map((l) => Linea.deJson(Map<String, dynamic>.from(l as Map)))
            .toList(),
        factura: (j['factura'] ?? '') as String,
      );
}

enum EstadoCita { solicitada, confirmada, rechazada, cancelada, hecha }

const Map<EstadoCita, String> nombreEstadoCita = {
  EstadoCita.solicitada: 'Solicitada',
  EstadoCita.confirmada: 'Confirmada',
  EstadoCita.rechazada: 'Rechazada',
  EstadoCita.cancelada: 'Cancelada',
  EstadoCita.hecha: 'Hecha',
};

/// Una cita pedida a un taller.
///
/// EN ESTA VERSIÓN NO SALE DEL MÓVIL: no hay servidor todavía, así que queda
/// anotada como "solicitada" y la pantalla lo dice con todas las letras. Un
/// botón que promete avisar a un taller y no avisa a nadie es peor que no
/// tenerlo, porque el dueño se presenta allí el martes a las diez.
class Cita {
  String id;
  String vehiculoId;
  String lugarId;
  String lugarNombre;
  String servicio;
  String fecha; // AAAA-MM-DD
  String hora; // HH:MM
  String nota;
  EstadoCita estado;

  /// Si de verdad llegó al taller: la creó la función del servidor con el
  /// permiso del taller. Mientras sea false, la pantalla dice que hay que
  /// llamar.
  bool enviada;

  /// El id de la fila en el servidor, cuando se envió. Es por donde vuelve la
  /// respuesta del taller (confirmada, rechazada) al sincronizar.
  String remotoId;

  Cita({
    String? id,
    required this.vehiculoId,
    required this.lugarId,
    this.lugarNombre = '',
    this.servicio = '',
    required this.fecha,
    this.hora = '',
    this.nota = '',
    this.estado = EstadoCita.solicitada,
    this.enviada = false,
    this.remotoId = '',
  }) : id = id ?? nuevoId('c');

  Map<String, dynamic> aJson() => {
        'id': id,
        'vehiculoId': vehiculoId,
        'lugarId': lugarId,
        'lugarNombre': lugarNombre,
        'servicio': servicio,
        'fecha': fecha,
        'hora': hora,
        'nota': nota,
        'estado': estado.name,
        'enviada': enviada,
        'remotoId': remotoId,
      };

  /// Los estados del servidor son los de la web: "completada" allí es "hecha"
  /// aquí, y lo que no se conozca se queda en "solicitada" en vez de romper.
  static EstadoCita estadoDeTexto(String? t) => switch (t) {
        'confirmada' => EstadoCita.confirmada,
        'rechazada' => EstadoCita.rechazada,
        'cancelada' => EstadoCita.cancelada,
        'completada' || 'hecha' => EstadoCita.hecha,
        _ => EstadoCita.solicitada,
      };

  static Cita deJson(Map<String, dynamic> j) => Cita(
        id: j['id'] as String?,
        vehiculoId: (j['vehiculoId'] ?? '') as String,
        lugarId: (j['lugarId'] ?? '') as String,
        lugarNombre: (j['lugarNombre'] ?? '') as String,
        servicio: (j['servicio'] ?? '') as String,
        fecha: (j['fecha'] ?? '') as String,
        hora: (j['hora'] ?? '') as String,
        nota: (j['nota'] ?? '') as String,
        estado: estadoDeTexto(j['estado'] as String?),
        enviada: (j['enviada'] ?? false) as bool,
        remotoId: (j['remotoId'] ?? '') as String,
      );
}

/// Lecturas del OBD guardadas. No van al diario como una intervención —no se
/// le ha hecho nada al coche— pero sí valen como prueba de por dónde iba el
/// cuentakilómetros y qué códigos había ese día.
class LecturaGuardada {
  String id;
  String vehiculoId;
  String cuando; // ISO-8601 completo: aquí SÍ importa la hora
  int? km;
  List<String> codigos;
  Map<String, String> valores; // nombre legible -> "35 °C"

  LecturaGuardada({
    String? id,
    required this.vehiculoId,
    required this.cuando,
    this.km,
    List<String>? codigos,
    Map<String, String>? valores,
  })  : id = id ?? nuevoId('o'),
        codigos = codigos ?? [],
        valores = valores ?? {};

  Map<String, dynamic> aJson() => {
        'id': id,
        'vehiculoId': vehiculoId,
        'cuando': cuando,
        'km': km,
        'codigos': codigos,
        'valores': valores,
      };

  static LecturaGuardada deJson(Map<String, dynamic> j) => LecturaGuardada(
        id: j['id'] as String?,
        vehiculoId: (j['vehiculoId'] ?? '') as String,
        cuando: (j['cuando'] ?? '') as String,
        km: _entero(j['km']),
        codigos:
            ((j['codigos'] ?? []) as List).map((c) => c.toString()).toList(),
        valores:
            Map<String, String>.from((j['valores'] ?? <String, dynamic>{}) as Map),
      );
}

/// Lee un número que puede venir como int, double, texto o nada. El JSON de un
/// respaldo viejo puede traer "120000" entrecomillado y eso no puede tirar la
/// app ni, peor, convertirse en un cero que parece un dato.
int? _entero(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  return int.tryParse(v.toString().replaceAll('.', '').trim());
}

double? _decimal(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '.').trim());
}

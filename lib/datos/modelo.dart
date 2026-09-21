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

import 'dart:convert';

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

  /// De dónde ha salido cada bastidor. El de la FICHA TÉCNICA es el documento;
  /// el del OBD es la posesión (para leerlo hay que estar dentro del coche con
  /// la llave). Cuando los dos coinciden, el coche está VERIFICADO: sin
  /// guardar ningún papel, y sin que se pueda fingir desde el sofá.
  String bastidorFicha;
  String bastidorObd;

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
    this.bastidorFicha = '',
    this.bastidorObd = '',
  }) : id = id ?? nuevoId('v');

  /// Verificado: el bastidor del documento y el del coche son el mismo.
  bool get verificado =>
      bastidorFicha.isNotEmpty && bastidorFicha == bastidorObd;

  /// Los dos bastidores existen pero no cuadran: o la foto se leyó mal, o el
  /// documento no es de este coche. Se dice, no se esconde.
  bool get bastidoresDiscrepan =>
      bastidorFicha.isNotEmpty && bastidorObd.isNotEmpty && bastidorFicha != bastidorObd;

  /// Pasos dados hacia la verificación (0, 1 o 2).
  int get pasosVerificacion => (bastidorFicha.isNotEmpty ? 1 : 0) + (bastidorObd.isNotEmpty ? 1 : 0);

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
        'bastidorFicha': bastidorFicha,
        'bastidorObd': bastidorObd,
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
        bastidorFicha: (j['bastidorFicha'] ?? '') as String,
        bastidorObd: (j['bastidorObd'] ?? '') as String,
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

  /// Más fotos: las piezas antigua y nueva que manda el taller con su
  /// informe, o las que haga el dueño. Nombres de fichero, como la factura.
  List<String> fotos;

  /// Quién lo escribió: 'taller' si viene del informe que mandó el taller
  /// desde su panel, 'propia' si lo anotó el dueño. No se puede cambiar a
  /// mano: es lo que hace creíble el historial.
  String origen;

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
    List<String>? fotos,
    this.origen = 'propia',
  })  : id = id ?? nuevoId('i'),
        lineas = lineas ?? [],
        fotos = fotos ?? [];

  /// Cuánto se puede creer esta anotación, en tres niveles. Es lo que el
  /// comprador del coche quiere saber de cada línea del historial.
  Credibilidad get credibilidad {
    if (origen == 'taller') return Credibilidad.taller;
    if (factura.isNotEmpty || fotos.isNotEmpty) return Credibilidad.conPrueba;
    return Credibilidad.sinPrueba;
  }

  bool get conPrueba => credibilidad != Credibilidad.sinPrueba;

  /// Todos los ficheros de imagen de esta anotación: la factura y las fotos.
  List<String> get ficheros => [if (factura.isNotEmpty) factura, ...fotos];

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
        'fotos': fotos,
        'origen': origen,
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
        fotos: ((j['fotos'] ?? []) as List).map((f) => f.toString()).where((f) => f.isNotEmpty).toList(),
        origen: (j['origen'] ?? 'propia') as String,
      );
}

/// Los tres niveles de credibilidad de una anotación del diario.
enum Credibilidad { taller, conPrueba, sinPrueba }

const Map<Credibilidad, String> nombreCredibilidad = {
  Credibilidad.taller: 'Hecho por el taller',
  Credibilidad.conPrueba: 'Con factura o fotos',
  Credibilidad.sinPrueba: 'Sin pruebas',
};

enum EstadoCita { solicitada, confirmada, rechazada, cancelada, hecha }

const Map<EstadoCita, String> nombreEstadoCita = {
  EstadoCita.solicitada: 'Solicitada',
  EstadoCita.confirmada: 'Confirmada',
  EstadoCita.rechazada: 'Rechazada',
  EstadoCita.cancelada: 'Cancelada',
  EstadoCita.hecha: 'Hecha',
};

/// Cómo se paga en el taller, con la misma clave que guarda el panel web.
const Map<String, String> formasDePago = {
  'efectivo': 'en efectivo',
  'tarjeta': 'con tarjeta',
  'bizum': 'por Bizum',
  'transferencia': 'por transferencia',
};

/// Una cita pedida a un taller.
///
/// Se anota en el móvil SIEMPRE y, con cuenta, se manda al taller por la
/// función del servidor. Lo que el taller conteste vuelve al sincronizar:
/// el estado (confirmada, rechazada), su RESPUESTA (tiempo aproximado, forma
/// de pago, presupuesto, mensaje) y, cuando el coche ya pasó por allí, el
/// INFORME de lo que se hizo, que el dueño añade a su diario de un toque.
///
/// Mientras `enviada` sea false, la pantalla dice que hay que llamar: un botón
/// que promete avisar a un taller y no avisa a nadie es peor que no tenerlo,
/// porque el dueño se presenta allí el martes a las diez.
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

  /// Lo que contestó el taller al aceptar o rechazar: `tiempo` (texto),
  /// `pago` (clave de `formasDePago`), `presupuesto` (número, aproximado),
  /// `mensaje`, `motivo` (si rechaza) y `cuando`. Vacío si no ha contestado.
  Map<String, dynamic> respuesta;

  /// El informe del taller cuando terminó: `titulo`, `fecha`, `km`, `total`
  /// (con IVA), `lineas` [{concepto, importe, tipo}], `notas`, `cuando`.
  /// Vacío mientras no lo mande.
  Map<String, dynamic> informe;

  /// Ya se pasó el informe al diario. Se recuerda para no ofrecerlo dos veces
  /// y para no duplicar la intervención si se sincroniza de nuevo.
  bool informeAnadido;

  /// El último suceso del que ya se avisó al dueño ('confirmada',
  /// 'rechazada', 'informe'). Con esto un aviso sale UNA vez, lo detecte la
  /// app abierta o la comprobación en segundo plano.
  String avisado;

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
    Map<String, dynamic>? respuesta,
    Map<String, dynamic>? informe,
    this.informeAnadido = false,
    this.avisado = '',
  })  : id = id ?? nuevoId('c'),
        respuesta = respuesta ?? {},
        informe = informe ?? {};

  bool get hayRespuesta => respuesta.isNotEmpty;
  bool get hayInforme => informe.isNotEmpty;

  String get tiempo => (respuesta['tiempo'] ?? '').toString().trim();
  String get mensaje => (respuesta['mensaje'] ?? '').toString().trim();
  String get motivo => (respuesta['motivo'] ?? '').toString().trim();
  String get pago => formasDePago[(respuesta['pago'] ?? '').toString()] ?? '';
  double? get presupuesto => _decimal(respuesta['presupuesto']);

  String get informeTitulo => (informe['titulo'] ?? '').toString().trim();
  String get informeFecha => (informe['fecha'] ?? '').toString().trim();
  String get informeNotas => (informe['notas'] ?? '').toString().trim();
  int? get informeKm => _entero(informe['km']);
  double? get informeTotal => _decimal(informe['total']);
  List<Linea> get informeLineas => ((informe['lineas'] ?? []) as List)
      .whereType<Map>()
      .map((l) => Linea.deJson(Map<String, dynamic>.from(l)))
      .toList();

  /// Las fotos del informe: `id` del fichero en el cubo del servidor (las que
  /// subió el taller) o `datos` (una imagen pequeña dentro, en la demo web),
  /// y `tipo` 'antigua' | 'nueva'.
  List<FotoInforme> get informeFotos => ((informe['fotos'] ?? []) as List)
      .whereType<Map>()
      .map((f) => FotoInforme(
            id: (f['id'] ?? '').toString(),
            datos: (f['datos'] ?? '').toString(),
            tipo: (f['tipo'] ?? '').toString(),
          ))
      .where((f) => f.id.isNotEmpty || f.datos.startsWith('data:'))
      .toList();

  /// Las fotos del informe que ya están bajadas a este móvil: id → fichero.
  Map<String, String> get fotosBajadas =>
      Map<String, String>.from((informe['_bajadas'] ?? <String, dynamic>{}) as Map);

  /// Lo que el taller ha hecho con la cita y que merece un aviso. El informe
  /// manda sobre el estado: si ya llegó, es lo último que ha pasado.
  String get suceso {
    if (hayInforme) return 'informe';
    if (estado == EstadoCita.confirmada) return 'confirmada';
    if (estado == EstadoCita.rechazada) return 'rechazada';
    return '';
  }

  /// La respuesta del taller en una frase, para la tarjeta y para el aviso.
  String get textoRespuesta {
    final partes = <String>[];
    if (tiempo.isNotEmpty) partes.add('Tiempo aproximado: $tiempo');
    final p = presupuesto;
    if (p != null) {
      final texto = p % 1 == 0 ? p.toStringAsFixed(0) : p.toStringAsFixed(2).replaceAll('.', ',');
      partes.add('Presupuesto aprox.: $texto €');
    }
    if (pago.isNotEmpty) partes.add('Pago: $pago');
    return partes.join(' · ');
  }

  /// El informe del taller convertido en una entrada del diario. Un solo tipo
  /// en las líneas → ese tipo; varios distintos → revisión general (poner
  /// "batería" porque aparece un motor de arranque escondería el brazo de
  /// suspensión); ninguno → otro. `fotos` son los ficheros ya bajados.
  Intervencion informeComoIntervencion({List<String> fotos = const []}) {
    final lineas = informeLineas;
    final tipos = lineas.map((l) => l.tipo).where((t) => t.isNotEmpty).toSet();
    final tipo = tipos.length == 1 ? tipos.first : (tipos.length > 1 ? 'revision' : 'otro');
    return Intervencion(
      vehiculoId: vehiculoId,
      fecha: informeFecha.isNotEmpty ? informeFecha : fecha,
      tipo: tipo,
      titulo: informeTitulo.isNotEmpty ? informeTitulo : servicio,
      taller: lugarNombre,
      nota: informeNotas,
      km: informeKm,
      coste: informeTotal,
      lineas: lineas,
      fotos: fotos,
      origen: 'taller',
    );
  }

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
        'respuesta': respuesta,
        'informe': informe,
        'informeAnadido': informeAnadido,
        'avisado': avisado,
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
        respuesta: mapaTolerante(j['respuesta']),
        informe: mapaTolerante(j['informe']),
        informeAnadido: (j['informeAnadido'] ?? false) as bool,
        avisado: (j['avisado'] ?? '') as String,
      );
}

/// Una foto del informe del taller.
class FotoInforme {
  final String id; // fichero en el cubo del servidor, o vacío
  final String datos; // data: URL pequeña (demo), o vacío
  final String tipo; // 'antigua' | 'nueva'
  const FotoInforme({this.id = '', this.datos = '', this.tipo = ''});

  String get titulo => tipo == 'nueva' ? 'Pieza nueva' : (tipo == 'antigua' ? 'Pieza antigua' : 'Foto');
}

/// Algo que ha hecho el taller con una cita y que el dueño todavía no sabe.
/// Es lo que se convierte en un aviso en la bandeja del móvil.
class NovedadCita {
  final Cita cita;
  final String suceso; // 'confirmada' | 'rechazada' | 'informe'
  const NovedadCita(this.cita, this.suceso);

  String get _taller => cita.lugarNombre.isEmpty ? 'El taller' : cita.lugarNombre;

  String get titulo => switch (suceso) {
        'confirmada' => '$_taller ha confirmado tu cita',
        'rechazada' => '$_taller no puede atenderte ese día',
        'cambiada' => '$_taller ha cambiado la fecha de tu cita',
        _ => '$_taller te ha mandado el informe',
      };

  String get cuerpo {
    if (suceso == 'cambiada') {
      return 'Ahora es el ${cita.fecha}${cita.hora.isNotEmpty ? ' a las ${cita.hora}' : ''}.'
          '${cita.mensaje.isNotEmpty ? ' «${cita.mensaje}»' : ''}';
    }
    if (suceso == 'informe') {
      final t = cita.informeTitulo.isNotEmpty ? cita.informeTitulo : cita.servicio;
      final total = cita.informeTotal;
      final precio = total == null ? '' : ' · ${total.toStringAsFixed(2).replaceAll('.', ',')} €';
      return '$t$precio · Añádelo a tu diario desde Citas';
    }
    final cuando = '${cita.fecha}${cita.hora.isNotEmpty ? ' a las ${cita.hora}' : ''}';
    if (suceso == 'rechazada') {
      return cita.motivo.isNotEmpty ? cita.motivo : 'Cita del $cuando. Puedes pedir otra fecha.';
    }
    final r = cita.textoRespuesta;
    return r.isNotEmpty ? r : 'Cita del $cuando';
  }
}

/// Un mapa que puede venir como mapa, como texto JSON (así lo guarda la
/// tabla del servidor) o como nada. Cualquier otra cosa es un mapa vacío.
Map<String, dynamic> mapaTolerante(Object? v) {
  if (v == null) return {};
  if (v is Map) return Map<String, dynamic>.from(v);
  if (v is String && v.trim().startsWith('{')) {
    try {
      final d = jsonDecode(v);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
  }
  return {};
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

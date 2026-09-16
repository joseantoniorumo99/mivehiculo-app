/// LA MATRÍCULA ESPAÑOLA DICE CUÁNDO SE MATRICULÓ EL COCHE.
///
/// Desde septiembre de 2000 las matrículas se emiten en serie y sin saltos:
/// 0000 BBB, 0001 BBB… 9999 BBB, 0000 BCB, y así. Así que la posición de la
/// serie en esa secuencia es una fecha disfrazada. Interpolando entre anclas
/// conocidas —la primera serie emitida en enero de cada año— sale el mes con
/// bastante acierto.
///
/// PARA QUÉ SIRVE ESTO DE VERDAD: con el mes de matriculación la ITV se dice
/// exacta ("toca en jun de 2027") en vez de aproximada ("hacia 2027"). Es la
/// diferencia entre un aviso al que se hace caso y uno que se ignora, y sale
/// gratis de un dato que el dueño ya tiene en el bolsillo.
///
/// LO QUE ESTO NO ES: no es la ficha técnica. Marca, modelo y motor NO se
/// pueden sacar de la matrícula sin la DGT o un proveedor de pago, y por eso
/// la app pide esos tres a mano en vez de inventarlos. Las anclas son
/// orientativas (tablas públicas de series por mes, contrastadas entre sí):
/// la fecha oficial solo la da la ficha técnica o un informe de la DGT, y la
/// app lo dice cuando la usa.
library;

const String _letras = 'BCDFGHJKLMNPRSTVWXYZ';

/// Primera serie emitida en enero de cada año. El primer par no es enero: es
/// el 18 de septiembre de 2000, el día que arrancó el sistema.
const List<List<Object>> _anclas = [
  ['BBB', 2000.71],
  ['BDS', 2001.0], ['BSM', 2002.0], ['CDW', 2003.0], ['CRW', 2004.0],
  ['DFG', 2005.0], ['DVX', 2006.0], ['FKZ', 2007.0], ['FZS', 2008.0],
  ['GKT', 2009.0], ['GTD', 2010.0], ['HBR', 2011.0], ['HJD', 2012.0],
  ['HNV', 2013.0], ['HVP', 2014.0], ['JCK', 2015.0], ['JLB', 2016.0],
  ['JWP', 2017.0], ['KHH', 2018.0], ['KTK', 2019.0], ['LFJ', 2020.0],
  ['LMM', 2021.0], ['LWF', 2022.0], ['MDT', 2023.0], ['MNC', 2024.0],
  ['MYD', 2025.0], ['NKG', 2026.0],
];

/// "KYT" -> posición en la secuencia (0 = BBB). Es base 20 con las consonantes
/// como dígitos.
int? indiceDeSerie(String serie) {
  var n = 0;
  for (final letra in serie.split('')) {
    final pos = _letras.indexOf(letra);
    if (pos < 0) return null;
    n = n * 20 + pos;
  }
  return n;
}

String normalizarMatricula(String m) =>
    m.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');

class PartesMatricula {
  final String numeros;
  final String serie;
  final String limpia;
  const PartesMatricula(this.numeros, this.serie, this.limpia);
}

/// Solo el formato vigente (1234 ABC). Las matrículas provinciales anteriores
/// a 2000 no se pueden datar así, y la app pide el año a mano en ese caso en
/// vez de fingir que lo sabe.
PartesMatricula? partesDeMatricula(String matricula) {
  final limpia = normalizarMatricula(matricula);
  final m = RegExp(r'^(\d{4})([BCDFGHJKLMNPRSTVWXYZ]{3})$').firstMatch(limpia);
  if (m == null) return null;
  return PartesMatricula(m.group(1)!, m.group(2)!, limpia);
}

String formatearMatricula(String matricula) {
  final p = partesDeMatricula(matricula);
  return p == null ? normalizarMatricula(matricula) : '${p.numeros} ${p.serie}';
}

class FechaMatricula {
  final int anio;
  final int mes; // 1-12
  const FechaMatricula(this.anio, this.mes);

  /// "AAAA-MM", que es justo lo que guarda el vehículo y lo que necesita el
  /// cálculo de la ITV.
  String get iso => '$anio-${mes.toString().padLeft(2, '0')}';
}

/// Fecha aproximada de primera matriculación, interpolando entre anclas.
/// Devuelve null cuando no se puede datar: formato antiguo, letras raras, o
/// una serie anterior al arranque del sistema.
FechaMatricula? fechaDeMatricula(String matricula) {
  final p = partesDeMatricula(matricula);
  if (p == null) return null;
  final indice = indiceDeSerie(p.serie);
  if (indice == null) return null;

  final anclas = _anclas
      .map((a) => [indiceDeSerie(a[0] as String)!, a[1] as double])
      .toList();

  double? momento;
  for (var i = 0; i < anclas.length - 1; i++) {
    final iA = anclas[i][0] as int, mA = anclas[i][1] as double;
    final iB = anclas[i + 1][0] as int, mB = anclas[i + 1][1] as double;
    if (indice >= iA && indice < iB) {
      momento = mA + ((indice - iA) / (iB - iA)) * (mB - mA);
      break;
    }
  }

  // Posterior a la última ancla: se sigue el ritmo del último tramo.
  if (momento == null) {
    final iUlt = anclas.last[0] as int, mUlt = anclas.last[1] as double;
    final iPen = anclas[anclas.length - 2][0] as int;
    final mPen = anclas[anclas.length - 2][1] as double;
    if (indice < iPen) return null; // anterior a 2000: sin datar
    final ritmo = (iUlt - iPen) / (mUlt - mPen); // series por año
    momento = mUlt + (indice - iUlt) / ritmo;
  }

  final anio = momento.floor();
  var mes = ((momento - anio) * 12).floor();
  if (mes < 0) mes = 0;
  if (mes > 11) mes = 11;
  return FechaMatricula(anio, mes + 1);
}

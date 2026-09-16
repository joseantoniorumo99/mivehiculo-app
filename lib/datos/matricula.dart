/// LA MATRÍCULA ESPAÑOLA DICE CUÁNDO SE MATRICULÓ EL COCHE.
///
/// Desde septiembre de 2000 las matrículas se emiten en serie y sin saltos:
/// 0000 BBB, 0001 BBB… 9999 BBB, 0000 BCB, y así. Así que la posición de la
/// serie en esa secuencia es una fecha disfrazada.
///
/// ANTES SE INTERPOLABA entre una ancla por año, y eso daba errores de hasta
/// dos años en los meses lejos del ancla: un C3 de 2018 salió como de 2020.
/// Ahora se usa la TABLA MENSUAL completa —la última serie asignada al final
/// de cada mes desde 2000— y la fecha sale al mes, sin interpolar. La fuente
/// son las tablas públicas que publican los sitios que siguen las series de
/// la DGT (fechamatriculacion.es y otros), contrastadas entre sí.
///
/// LO QUE ESTO NO ES: no es la ficha técnica. Marca, modelo y motor NO se
/// pueden sacar de la matrícula sin la DGT o un proveedor de pago. Y la fecha
/// que sale es la de la matriculación EN ESPAÑA: un coche importado de
/// segunda mano lleva matrícula del día que llegó, no del día que se fabricó,
/// y para la ITV cuenta su primera matriculación en origen. Por eso el año
/// que escriba el dueño manda sobre lo que diga la matrícula.
library;

const String _letras = 'BCDFGHJKLMNPRSTVWXYZ';

/// Última serie asignada al final de cada mes, desde el arranque del sistema
/// (18 de septiembre de 2000). Una entrada por mes, sin saltos: la posición
/// en la lista ES el mes.
const List<String> _finDeMes = [
  // 2000 (sep-dic)
  'BCD', 'BCY', 'BDR', 'BDR',
  // 2001
  'BFJ', 'BGF', 'BHG', 'BJC', 'BKB', 'BLC', 'BMF', 'BMW', 'BNL', 'BPG', 'BRB', 'BRT',
  // 2002
  'BSL', 'BTF', 'BTZ', 'BVW', 'BWT', 'BXP', 'BYP', 'BZF', 'BZV', 'CBP', 'CCH', 'CDC',
  // 2003
  'CDV', 'CFM', 'CGJ', 'CHF', 'CJC', 'CKB', 'CLD', 'CLV', 'CMM', 'CNK', 'CPF', 'CRC',
  // 2004
  'CRV', 'CSS', 'CTT', 'CVR', 'CWR', 'CXT', 'CYY', 'CZP', 'DBJ', 'DCH', 'DDG', 'DFF',
  // 2005
  'DFZ', 'DGX', 'DHZ', 'DKB', 'DLD', 'DMJ', 'DNP', 'DPK', 'DRG', 'DSC', 'DTB', 'DVB',
  // 2006
  'DVW', 'DWT', 'DXZ', 'DYY', 'FBC', 'FCJ', 'FDP', 'FFK', 'FGF', 'FHD', 'FJD', 'FKC',
  // 2007
  'FKY', 'FLV', 'FNB', 'FNZ', 'FRC', 'FSJ', 'FTP', 'FVJ', 'FWC', 'FXB', 'FXY', 'FYY',
  // 2008
  'FZR', 'GBN', 'GCK', 'GDH', 'GFC', 'GFY', 'GGV', 'GHG', 'GHT', 'GJJ', 'GJV', 'GKH',
  // 2009
  'GKS', 'GLC', 'GLP', 'GMC', 'GMN', 'GNF', 'GNY', 'GPJ', 'GPW', 'GRM', 'GSC', 'GSR',
  // 2010
  'GTC', 'GTS', 'GVM', 'GWC', 'GWV', 'GXP', 'GYD', 'GYM', 'GYX', 'GZJ', 'GZT', 'HBG',
  // 2011
  'HBP', 'HCB', 'HCR', 'HDC', 'HDR', 'HFF', 'HFT', 'HGC', 'HGM', 'HGX', 'HHH', 'HHT',
  // 2012
  'HJC', 'HJM', 'HKB', 'HKL', 'HKX', 'HLK', 'HLW', 'HMD', 'HML', 'HMT', 'HNC', 'HNK',
  // 2013
  'HNT', 'HPC', 'HPN', 'HPY', 'HRK', 'HRX', 'HSK', 'HSS', 'HSZ', 'HTK', 'HTV', 'HVF',
  // 2014
  'HVN', 'HVZ', 'HWM', 'HXB', 'HXN', 'HYD', 'HYT', 'HZB', 'HZL', 'HZZ', 'JBL', 'JBY',
  // 2015
  'JCK', 'JCY', 'JDR', 'JFG', 'JFX', 'JGR', 'JHJ', 'JHT', 'JJH', 'JJW', 'JKK', 'JKZ',
  // 2016
  'JLN', 'JMF', 'JMY', 'JNR', 'JPK', 'JRG', 'JRZ', 'JSK', 'JTB', 'JTN', 'JVH', 'JVZ',
  // 2017
  'JWN', 'JXF', 'JYB', 'JYT', 'JZP', 'KBM', 'KCH', 'KCT', 'KDH', 'KFC', 'KFW', 'KGN',
  // 2018
  'KHG', 'KHY', 'KJV', 'KKR', 'KLN', 'KMM', 'KNK', 'KPD', 'KPS', 'KRJ', 'KRZ', 'KSS',
  // 2019
  'KTJ', 'KVB', 'KVX', 'KWT', 'KXR', 'KYN', 'KZK', 'KZY', 'LBN', 'LCG', 'LCY', 'LDR',
  // 2020
  'LFH', 'LFY', 'LGG', 'LGH', 'LGP', 'LHG', 'LJD', 'LJR', 'LKF', 'LKV', 'LLJ', 'LMC',
  // 2021
  'LML', 'LMX', 'LNN', 'LPD', 'LPW', 'LRP', 'LSF', 'LSP', 'LTD', 'LTP', 'LVD', 'LVV',
  // 2022
  'LWD', 'LWR', 'LXD', 'LXS', 'LYJ', 'LYZ', 'LZP', 'LZZ', 'MBN', 'MBZ', 'MCR', 'MDD',
  // 2023
  'MDS', 'MFG', 'MFX', 'MGN', 'MHG', 'MHY', 'MJR', 'MKD', 'MKP', 'MLH', 'MLY', 'MMN',
  // 2024
  'MNC', 'MNT', 'MPL', 'MRD', 'MRW', 'MSS', 'MTK', 'MTV', 'MVL', 'MWD', 'MWS', 'MXP',
  // 2025
  'MYC', 'MYV', 'MZS', 'NBL', 'NCG', 'NDG', 'NFC', 'NFR', 'NGJ', 'NHC', 'NHX', 'NJS',
  // 2026 (ene-abr)
  'NKF', 'NKY', 'NMZ', 'NPZ',
];

const int _primerAnio = 2000;
const int _primerMes = 9;

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

  /// False cuando la serie es más nueva que el último mes de la tabla y se ha
  /// extrapolado siguiendo el ritmo de los últimos meses.
  final bool exacta;
  const FechaMatricula(this.anio, this.mes, {this.exacta = true});

  /// "AAAA-MM", que es justo lo que guarda el vehículo y lo que necesita el
  /// cálculo de la ITV.
  String get iso => '$anio-${mes.toString().padLeft(2, '0')}';
}

/// Mes de la primera matriculación en España, buscando la serie en la tabla
/// mensual. Devuelve null cuando no se puede datar: formato antiguo o letras
/// que no son del sistema.
FechaMatricula? fechaDeMatricula(String matricula) {
  final p = partesDeMatricula(matricula);
  if (p == null) return null;
  final indice = indiceDeSerie(p.serie);
  if (indice == null) return null;

  for (var i = 0; i < _finDeMes.length; i++) {
    final fin = indiceDeSerie(_finDeMes[i])!;
    if (indice <= fin) {
      final meses = (_primerMes - 1) + i;
      return FechaMatricula(_primerAnio + meses ~/ 12, (meses % 12) + 1);
    }
  }

  // Más nueva que la tabla: se sigue el ritmo de los últimos doce meses.
  final ultimo = indiceDeSerie(_finDeMes.last)!;
  final hace12 = indiceDeSerie(_finDeMes[_finDeMes.length - 13])!;
  final porMes = (ultimo - hace12) / 12;
  final mesesDeMas = porMes <= 0 ? 0 : ((indice - ultimo) / porMes).ceil();
  final meses = (_primerMes - 1) + (_finDeMes.length - 1) + mesesDeMas;
  return FechaMatricula(_primerAnio + meses ~/ 12, (meses % 12) + 1, exacta: false);
}

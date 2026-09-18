/// El informe en PDF se genera con un diario de verdad y sale un PDF de
/// verdad. No se comprueba el dibujo, se comprueba que no rompe con lo que
/// rompe: acentos y euros, coche sin datos, diario vacío, líneas sin tipo.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:mivehiculo/datos/informe_pdf.dart';
import 'package:mivehiculo/datos/modelo.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late pw.Font regular;
  late pw.Font negrita;

  setUpAll(() async {
    regular = pw.Font.ttf(await rootBundle.load('assets/fuentes/Roboto-Regular.ttf'));
    negrita = pw.Font.ttf(await rootBundle.load('assets/fuentes/Roboto-Bold.ttf'));
  });

  final coche = Vehiculo(
    id: 'v1',
    marca: 'Citroën',
    modelo: 'C3',
    matriculacion: '2018-03',
    combustible: 'Diésel',
    matricula: '1234 KLM',
    km: 98500,
    bastidor: 'VF7SXHMZ0JT123456',
  );

  test('con un diario completo sale un PDF', () async {
    final diario = [
      Intervencion(
        vehiculoId: 'v1',
        fecha: '2024-06-10',
        tipo: 'revision',
        titulo: 'Revisión 80.000',
        taller: 'Talleres Hermanos Ruiz',
        km: 80000,
        coste: 412.5,
        nota: 'Cambio de aceite y filtros; ruedas al 60 %.',
        lineas: [
          Linea(concepto: 'Aceite 5W30 y filtro', importe: 95, tipo: 'aceite'),
          Linea(concepto: 'Filtro de habitáculo', importe: 22, tipo: 'filtro'),
          Linea(concepto: 'Mano de obra', importe: 224),
        ],
        factura: 'f1.jpg',
      ),
      Intervencion(vehiculoId: 'v1', fecha: '2025-04-02', tipo: 'itv', km: 91000, coste: 45.3),
    ];
    final lecturas = [
      LecturaGuardada(
        vehiculoId: 'v1',
        cuando: '2026-09-10T08:12:00.000Z',
        km: 98400,
        codigos: ['P0420'],
        valores: {'Temperatura del refrigerante': '89 °C', 'Tensión': '14,2 V', 'Lectura': 'automática'},
      ),
    ];
    final citas = [
      Cita(
        vehiculoId: 'v1',
        lugarId: 'osmnode1',
        lugarNombre: 'Talleres Hermanos Ruiz',
        servicio: 'Frenos',
        fecha: '2026-09-16',
        estado: EstadoCita.hecha,
        enviada: true,
        informe: {
          'fecha': '2026-09-16',
          'km': 98450,
          'titulo': 'Frenos delanteros',
          'total': 193.6,
          'lineas': [
            {'concepto': 'Pastillas', 'importe': 60, 'tipo': 'freno'},
            {'concepto': 'Mano de obra', 'importe': 100, 'tipo': ''},
          ],
          'notas': 'Los traseros aguantan otros 20.000 km.',
        },
      ),
    ];
    final bytes = await InformePdf.construirConLetra(
      coche: coche,
      diario: diario,
      lecturas: lecturas,
      citas: citas,
      regular: regular,
      negrita: negrita,
      hoyPara: DateTime(2026, 9, 18),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(20000)); // lleva la letra incrustada
  });

  test('con un coche recién dado de alta y sin nada anotado también', () async {
    final bytes = await InformePdf.construirConLetra(
      coche: Vehiculo(id: 'v2'),
      diario: const [],
      lecturas: const [],
      regular: regular,
      negrita: negrita,
      hoyPara: DateTime(2026, 9, 18),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('cargando la letra de los assets', () async {
    final bytes = await InformePdf.construir(
      coche: coche,
      diario: const [],
      lecturas: const [],
      hoyPara: DateTime(2026, 9, 18),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}

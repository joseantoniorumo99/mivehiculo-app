/// La cita con la respuesta y el informe del taller: lo que vuelve del
/// servidor, cómo se lee, y cómo el informe se convierte en diario.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mivehiculo/datos/modelo.dart';

void main() {
  group('mapaTolerante', () {
    test('acepta mapa, texto JSON y nada', () {
      expect(mapaTolerante(null), isEmpty);
      expect(mapaTolerante(''), isEmpty);
      expect(mapaTolerante('no es json'), isEmpty);
      expect(mapaTolerante({'a': 1}), {'a': 1});
      expect(mapaTolerante('{"tiempo":"Medio día"}'), {'tiempo': 'Medio día'});
    });
  });

  group('Cita', () {
    Cita citaConRespuesta() => Cita(
          vehiculoId: 'v1',
          lugarId: 'osmnode1',
          lugarNombre: 'Talleres Hermanos Ruiz',
          servicio: 'Frenos',
          fecha: '2026-09-25',
          hora: '09:00',
          estado: EstadoCita.confirmada,
          enviada: true,
          respuesta: {'tiempo': 'Medio día', 'pago': 'bizum', 'presupuesto': 160, 'mensaje': 'Trae el libro'},
        );

    test('la respuesta se lee en una frase con euros y forma de pago', () {
      final c = citaConRespuesta();
      expect(c.tiempo, 'Medio día');
      expect(c.pago, 'por Bizum');
      expect(c.presupuesto, 160);
      expect(c.textoRespuesta, 'Tiempo aproximado: Medio día · Presupuesto aprox.: 160 € · Pago: por Bizum');
      expect(c.suceso, 'confirmada');
    });

    test('con decimales el presupuesto lleva coma', () {
      final c = citaConRespuesta()..respuesta = {'presupuesto': '85.5'};
      expect(c.textoRespuesta, 'Presupuesto aprox.: 85,50 €');
    });

    test('el informe manda sobre el estado como suceso', () {
      final c = citaConRespuesta()..informe = {'titulo': 'Frenos', 'total': 190};
      expect(c.suceso, 'informe');
      expect(c.hayInforme, isTrue);
    });

    test('sin nada que contar no hay suceso', () {
      final c = Cita(vehiculoId: 'v1', lugarId: 'x', fecha: '2026-09-25');
      expect(c.suceso, '');
    });

    test('sobrevive al JSON con los campos nuevos y sin ellos', () {
      final c = citaConRespuesta()
        ..informe = {'titulo': 'Frenos', 'lineas': [{'concepto': 'Pastillas', 'importe': 60, 'tipo': 'freno'}]}
        ..informeAnadido = true
        ..avisado = 'informe';
      final copia = Cita.deJson(jsonDecode(jsonEncode(c.aJson())) as Map<String, dynamic>);
      expect(copia.respuesta['pago'], 'bizum');
      expect(copia.informeLineas.single.concepto, 'Pastillas');
      expect(copia.informeAnadido, isTrue);
      expect(copia.avisado, 'informe');

      // Una cita guardada por la 1.2.0 no tiene estos campos.
      final vieja = Cita.deJson({'vehiculoId': 'v1', 'lugarId': 'x', 'fecha': '2026-01-01'});
      expect(vieja.respuesta, isEmpty);
      expect(vieja.informe, isEmpty);
      expect(vieja.avisado, '');
    });

    test('el informe se convierte en una intervención con su desglose', () {
      final c = citaConRespuesta()
        ..informe = {
          'fecha': '2026-09-25',
          'km': 87400,
          'titulo': 'Frenos delanteros',
          'total': 193.6,
          'notas': 'Revisar los traseros en 20.000 km',
          'lineas': [
            {'concepto': 'Pastillas', 'importe': 60, 'tipo': 'freno'},
            {'concepto': 'Discos', 'importe': 80, 'tipo': 'freno'},
            {'concepto': 'Mano de obra', 'importe': 20, 'tipo': ''},
          ],
        };
      final i = c.informeComoIntervencion();
      expect(i.vehiculoId, 'v1');
      expect(i.fecha, '2026-09-25');
      expect(i.km, 87400);
      expect(i.coste, 193.6);
      expect(i.titulo, 'Frenos delanteros');
      expect(i.taller, 'Talleres Hermanos Ruiz');
      expect(i.nota, 'Revisar los traseros en 20.000 km');
      expect(i.lineas.length, 3);
      // Un solo tipo de mantenimiento en las líneas: ese es el tipo.
      expect(i.tipo, 'freno');
    });

    test('varios tipos distintos en el informe son una revisión general', () {
      final c = citaConRespuesta()
        ..informe = {
          'lineas': [
            {'concepto': 'Aceite', 'importe': 60, 'tipo': 'aceite'},
            {'concepto': 'Pastillas', 'importe': 80, 'tipo': 'freno'},
          ],
        };
      expect(c.informeComoIntervencion().tipo, 'revision');
      // Y sin fecha en el informe, la de la cita.
      expect(c.informeComoIntervencion().fecha, '2026-09-25');
    });

    test('sin tipos reconocibles es "otro" y el título cae al servicio', () {
      final c = citaConRespuesta()..informe = {'lineas': [{'concepto': 'Diagnosis', 'importe': 40}]};
      final i = c.informeComoIntervencion();
      expect(i.tipo, 'otro');
      expect(i.titulo, 'Frenos');
    });
  });

  group('NovedadCita', () {
    test('cada suceso tiene su frase', () {
      final c = Cita(
        vehiculoId: 'v1',
        lugarId: 'x',
        lugarNombre: 'Taller Pepe',
        fecha: '2026-09-25',
        hora: '10:00',
        estado: EstadoCita.confirmada,
        respuesta: {'tiempo': '2 horas', 'pago': 'tarjeta'},
      );
      expect(NovedadCita(c, 'confirmada').titulo, 'Taller Pepe ha confirmado tu cita');
      expect(NovedadCita(c, 'confirmada').cuerpo, 'Tiempo aproximado: 2 horas · Pago: con tarjeta');

      c.respuesta = {'motivo': 'Cerramos por vacaciones'};
      expect(NovedadCita(c, 'rechazada').titulo, 'Taller Pepe no puede atenderte ese día');
      expect(NovedadCita(c, 'rechazada').cuerpo, 'Cerramos por vacaciones');

      c.informe = {'titulo': 'Aceite', 'total': 85};
      expect(NovedadCita(c, 'informe').titulo, 'Taller Pepe te ha mandado el informe');
      expect(NovedadCita(c, 'informe').cuerpo, 'Aceite · 85,00 € · Añádelo a tu diario desde Citas');
    });
  });
}

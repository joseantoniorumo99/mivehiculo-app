/// EL DIARIO: lo que se le ha hecho al coche. Mecánica, siniestros, ITV,
/// recambios. Solo eso.
///
/// Las lecturas del OBD NO van aquí: van en su propia sección. Una lectura
/// automática de camino al trabajo no es una intervención, y mezclarlas
/// enterraría las facturas —que son lo que vale— entre docenas de "35 °C".
///
/// Y se LEE antes que se edita: tocar un hito abre la intervención en modo
/// lectura, sin un solo campo. Consultar es lo que se hace siempre; editar,
/// casi nunca, y no debe estar a un toque.
library;

import 'package:flutter/material.dart';

import '../datos/mantenimiento.dart';
import '../datos/modelo.dart';
import '../estado.dart';
import '../tema.dart';
import 'editar_intervencion.dart';
import 'elegir_taller.dart';
import 'lecturas.dart';
import 'ver_intervencion.dart';

class PantallaDiario extends StatelessWidget {
  const PantallaDiario({super.key});

  @override
  Widget build(BuildContext context) {
    final almacen = context.almacen;
    return ListenableBuilder(
      listenable: almacen,
      builder: (context, _) {
        final coche = almacen.coche;
        final diario = almacen.diarioDelCoche;
        final lecturas = almacen.lecturasDelCoche;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Diario'),
            actions: [
              // Pedir cita desde donde se mira lo que le falta al coche, sin
              // pasar por el mapa: los talleres que ya conoces salen primero.
              if (coche != null)
                IconButton(
                  tooltip: 'Pedir cita',
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const PantallaElegirTaller())),
                  icon: const Icon(Icons.event_available_outlined),
                ),
              IconButton(
                tooltip: 'Lecturas del OBD',
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const PantallaLecturas())),
                icon: Badge.count(
                  count: lecturas.length,
                  isLabelVisible: lecturas.isNotEmpty,
                  child: const Icon(Icons.monitor_heart_outlined),
                ),
              ),
            ],
          ),
          floatingActionButton: coche == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const PantallaEditarIntervencion())),
                  icon: const Icon(Icons.add),
                  label: const Text('Anotar'),
                ),
          body: SafeArea(
            child: coche == null
                ? const Vacio(
                    icono: Icons.menu_book_outlined,
                    titulo: 'Primero el coche',
                    texto: 'El diario es del coche, no de la persona. Da de alta el tuyo '
                        'en el inicio y empieza a anotar.',
                  )
                : diario.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          Vacio(
                            icono: Icons.menu_book_outlined,
                            titulo: 'El diario está vacío',
                            texto: 'Anota cada cosa que se le haga al coche: aceite, ITV, '
                                'frenos, un golpe. Con la factura hecha foto, si la tienes. '
                                'Es lo que hace que los avisos funcionen y lo que enseñas '
                                'cuando lo vendas.',
                            accion: FilledButton(
                              onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const PantallaEditarIntervencion())),
                              child: const Text('Anotar la primera'),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                        itemCount: diario.length,
                        itemBuilder: (context, i) => _hito(context, diario[i],
                            primero: i == 0, ultimo: i == diario.length - 1),
                      ),
          ),
        );
      },
    );
  }

  Widget _hito(BuildContext context, Intervencion d,
      {required bool primero, required bool ultimo}) {
    final icono = switch (d.tipo) {
      'aceite' => Icons.opacity,
      'rueda' => Icons.tire_repair,
      'freno' => Icons.disc_full_outlined,
      'itv' => Icons.verified_outlined,
      'filtro' => Icons.air,
      'bateria' => Icons.battery_charging_full,
      'correa' => Icons.settings_outlined,
      'revision' => Icons.build_outlined,
      _ => Icons.handyman_outlined,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // El carril de la cronología: una línea y un galón por hito
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Expanded(
                  child: Container(width: 2, color: primero ? Colors.transparent : Tono.regla),
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(color: Tono.azul, shape: BoxShape.circle),
                ),
                Expanded(
                  child: Container(width: 2, color: ultimo ? Colors.transparent : Tono.regla),
                ),
              ],
            ),
          ),
          Expanded(
            child: Tarjeta(
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => PantallaVerIntervencion(id: d.id))),
              child: Row(
                children: [
                  PozoIcono(icono, tamano: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.tituloEfectivo,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            fechaCorta(d.fecha),
                            if (d.km != null) '${conMiles(d.km!)} km',
                            if (d.taller.isNotEmpty) d.taller,
                          ].join(' · '),
                          style: const TextStyle(fontSize: 12, color: Tono.tintaSuave),
                        ),
                        if (d.lineas.length > 1)
                          Text('${d.lineas.length} conceptos',
                              style: const TextStyle(fontSize: 12, color: Tono.tintaSuave)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(enEuros(d.coste),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontFeatures: [FontFeature.tabularFigures()])),
                      if (d.factura.isNotEmpty)
                        const Icon(Icons.receipt_long, size: 16, color: Tono.tintaSuave),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

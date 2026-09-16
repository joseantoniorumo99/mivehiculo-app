/// EL GARAJE: varios coches y cuál está en uso.
///
/// Se entra tocando el nombre del coche en el inicio, que es el botón del
/// garaje. El diario, las citas y las lecturas son DEL COCHE, no de la
/// persona: cambiar de coche aquí cambia todo lo demás.
library;

import 'package:flutter/material.dart';

import '../datos/mantenimiento.dart';
import '../datos/modelo.dart';
import '../estado.dart';
import '../tema.dart';
import 'alta_vehiculo.dart';

class PantallaGaraje extends StatelessWidget {
  const PantallaGaraje({super.key});

  @override
  Widget build(BuildContext context) {
    final almacen = context.almacen;
    return Scaffold(
      appBar: AppBar(title: const Text('Mis coches')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: almacen,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              ...almacen.vehiculos.map((v) => _fila(context, v, v.id == almacen.coche?.id)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PantallaAltaVehiculo())),
                icon: const Icon(Icons.add),
                label: const Text('Añadir otro coche'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fila(BuildContext context, Vehiculo v, bool activo) {
    final almacen = context.almacen;
    return Tarjeta(
      onTap: activo ? null : () => almacen.activar(v.id),
      child: Row(
        children: [
          PozoIcono(Icons.directions_car,
              fondo: activo ? Tono.azulFilm : const Color(0x121F2D44),
              tinta: activo ? Tono.azulTinta : Tono.tintaSuave),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.nombre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (v.matricula.isNotEmpty) v.matricula,
                    if (v.anioEfectivo != null) '${v.anioEfectivo}',
                    if (v.km != null) '${conMiles(v.km!)} km',
                  ].join(' · '),
                  style: const TextStyle(color: Tono.tintaSuave, fontSize: 13),
                ),
              ],
            ),
          ),
          if (activo) const ChipEstado('En uso', tono: TonoEstado.accion),
          PopupMenuButton<String>(
            onSelected: (que) async {
              if (que == 'editar') {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => PantallaAltaVehiculo(editar: v)));
              } else if (que == 'quitar') {
                final ok = await confirmar(
                  context,
                  titulo: 'Quitar ${v.nombre}',
                  texto: 'Se borra el coche con TODO su diario, sus citas y sus '
                      'lecturas de este móvil${context.nube.conSesion ? ' y de tu cuenta' : ''}. '
                      'No se puede deshacer.',
                  accion: 'Quitar el coche',
                );
                if (ok) await almacen.quitarVehiculo(v.id);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'editar', child: Text('Corregir datos')),
              PopupMenuItem(value: 'quitar', child: Text('Quitar este coche')),
            ],
          ),
        ],
      ),
    );
  }
}

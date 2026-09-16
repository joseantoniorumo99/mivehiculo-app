/// EL PERFIL: la cuenta, la copia en la nube, las citas y el garaje.
///
/// Aquí se dice la verdad sobre dónde están los datos: "en este móvil" o
/// "en este móvil y en tu cuenta, copiado a las 12:41". Una app que guarda
/// cosas tiene que poder decir dónde las guarda.
library;

import 'package:flutter/material.dart';

import '../datos/mantenimiento.dart';
import '../estado.dart';
import '../tema.dart';
import 'acceso.dart';
import 'citas.dart';
import 'expediente.dart';
import 'garaje.dart';
import 'lecturas.dart';

class PantallaPerfil extends StatelessWidget {
  const PantallaPerfil({super.key});

  @override
  Widget build(BuildContext context) {
    final almacen = context.almacen;
    final nube = context.nube;
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([almacen, nube]),
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _cuenta(context),
              const TituloSeccion('Tu coche'),
              _enlace(context, Icons.garage_outlined,
                  almacen.variosVehiculos ? 'Mis coches' : 'Mi coche',
                  almacen.coche?.nombre ?? 'Sin coche todavía',
                  const PantallaGaraje()),
              _enlace(context, Icons.event_outlined, 'Citas',
                  '${almacen.citasDelCoche.length} anotadas', const PantallaCitas()),
              _enlace(context, Icons.monitor_heart_outlined, 'Lecturas del OBD',
                  '${almacen.lecturasDelCoche.length} guardadas', const PantallaLecturas()),
              _enlace(context, Icons.folder_open_outlined, 'Expediente',
                  'El historial completo, para compartir', const PantallaExpediente()),
              const TituloSeccion('Sobre la app'),
              const Tarjeta(
                child: Text(
                  'Mi Vehículo · 1.0.0\n\n'
                  'Tus datos son tuyos: viven en este móvil y, si tienes cuenta, en '
                  'ella. No hay anuncios ni se vende nada a nadie. El lector OBD se '
                  'lee al abrir la app si el coche tiene el contacto dado, y nunca en '
                  'segundo plano.\n\n'
                  'Mapas y sitios: © OpenStreetMap y sus colaboradores (ODbL). '
                  'Catálogo de coches: Agencia Europea de Medio Ambiente.',
                  style: TextStyle(color: Tono.tintaSuave, height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cuenta(BuildContext context) {
    final nube = context.nube;
    final almacen = context.almacen;

    if (!nube.arrancada) {
      return const Tarjeta(child: Text('Comprobando la cuenta…'));
    }

    if (!nube.conSesion) {
      return Tarjeta(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sin cuenta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'Todo lo que anotas vive en este móvil. Con una cuenta se copia a la '
              'nube y sale también en el ordenador y en otros móviles.',
              style: TextStyle(color: Tono.tintaSuave, height: 1.4),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PantallaAcceso(ofrecerSinCuenta: false))),
              child: const Text('Entrar o crear cuenta'),
            ),
          ],
        ),
      );
    }

    final ultima = nube.ultimaSincronizacion;
    final String estado;
    if (nube.sincronizando) {
      estado = 'Copiando a la nube…';
    } else if (ultima != null) {
      estado = 'Copiado a las ${ultima.hour}:${ultima.minute.toString().padLeft(2, '0')}'
          '${almacen.hayPendiente ? ' · hay cambios por subir' : ''}';
    } else {
      estado = 'Todavía no se ha copiado nada en esta sesión';
    }

    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PozoIcono(Icons.person_outline),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nube.nombre.isEmpty ? 'Tu cuenta' : nube.nombre,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(nube.correo, style: const TextStyle(color: Tono.tintaSuave, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                nube.ultimoAviso != null
                    ? Icons.cloud_off
                    : (nube.sincronizando ? Icons.cloud_sync : Icons.cloud_done_outlined),
                size: 18,
                color: nube.ultimoAviso != null ? Tono.naranjaTinta : Tono.tealTinta,
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(estado, style: const TextStyle(fontSize: 13))),
            ],
          ),
          if (nube.ultimoAviso != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Recuadro(nube.ultimoAviso!,
                  tono: nube.servidorListo ? TonoEstado.atencion : TonoEstado.neutro),
            ),
          if (!nube.correoVerificado)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Recuadro(
                'El correo no está verificado.',
                consejo: 'Busca el mensaje de verificación en tu buzón. Sin verificar, '
                    'no se puede recuperar la contraseña.',
                tono: TonoEstado.neutro,
                accion: TextButton(
                  onPressed: () async {
                    try {
                      await nube.reenviarVerificacion();
                      if (context.mounted) avisar(context, 'Correo de verificación enviado.');
                    } catch (e) {
                      if (context.mounted) avisar(context, 'No se ha podido enviar: $e');
                    }
                  },
                  child: const Text('Volver a enviar el correo'),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  onPressed: nube.sincronizando ? null : () => nube.sincronizar(almacen),
                  child: const Text('Copiar ahora'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  onPressed: () async {
                    final ok = await confirmar(
                      context,
                      titulo: 'Cerrar sesión',
                      texto: 'Los datos se quedan en este móvil; solo se deja de copiar a '
                          'la cuenta. ${almacen.hayPendiente ? 'OJO: hay cambios que todavía no se han subido.' : ''}',
                      accion: 'Cerrar sesión',
                    );
                    if (!ok) return;
                    await nube.salir();
                    await almacen.olvidarNube();
                  },
                  child: const Text('Cerrar sesión'),
                ),
              ),
            ],
          ),
          if (ultima == null && !nube.sincronizando)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Última copia conocida: ${_ultimaMarca(almacen)}',
                style: const TextStyle(fontSize: 12, color: Tono.tintaSuave),
              ),
            ),
        ],
      ),
    );
  }

  String _ultimaMarca(dynamic almacen) {
    String? max;
    for (final id in almacen.todosLosIds) {
      final e = almacen.enviadoEn(id) as String?;
      if (e != null && (max == null || e.compareTo(max) > 0)) max = e;
    }
    return max == null ? 'ninguna' : fechaCorta(max);
  }

  Widget _enlace(BuildContext context, IconData icono, String titulo, String sub, Widget destino) =>
      Tarjeta(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: const EdgeInsets.only(bottom: 10),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => destino)),
        child: Row(
          children: [
            PozoIcono(icono, tamano: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(sub, style: const TextStyle(fontSize: 12, color: Tono.tintaSuave)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Tono.tintaSuave),
          ],
        ),
      );
}

/// EL PERFIL: la cuenta, la copia en la nube, las citas y el garaje.
///
/// Aquí se dice la verdad sobre dónde están los datos: "en este móvil" o
/// "en este móvil y en tu cuenta, copiado a las 12:41". Una app que guarda
/// cosas tiene que poder decir dónde las guarda.
library;

import 'package:flutter/material.dart';

import '../config_build.dart';
import '../datos/enlaces.dart';
import '../datos/mantenimiento.dart';
import '../datos/notificador.dart';
import '../estado.dart';
import '../tema.dart';
import 'acceso.dart';
import 'citas.dart';
import 'expediente.dart';
import 'garaje.dart';
import 'lectura_automatica.dart';
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
          listenable: Listenable.merge([almacen, nube, context.actualizacion]),
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
              _enlace(context, Icons.autorenew, 'Lectura automática',
                  'Cuándo lee el OBD sola, y lo que cuesta', const PantallaLecturaAutomatica()),
              // En la versión de Play no hay nada que comprobar: Play no deja
              // que la app se actualice a sí misma (ver config_build.dart).
              if (!esVersionPlay) ...[
                const TituloSeccion('Versión'),
                _actualizacion(context),
              ],
              const TituloSeccion('Sobre la app'),
              const Tarjeta(
                child: Text(
                  'Tus datos son tuyos: viven en este móvil y, si tienes cuenta, en '
                  'ella. No se vende nada a nadie. El lector OBD se '
                  'lee al abrir la app si el coche tiene el contacto dado, en vivo '
                  'mientras miras la pestaña, y en segundo plano solo si tú lo '
                  'enciendes.\n\n'
                  'Mapas y sitios: © OpenStreetMap y sus colaboradores (ODbL). '
                  'Catálogo de coches: Agencia Europea de Medio Ambiente.',
                  style: TextStyle(color: Tono.tintaSuave, height: 1.45),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 4,
                children: [
                  TextButton(
                      onPressed: () => Enlaces.abrir(Enlaces.privacidad),
                      child: const Text('Privacidad')),
                  TextButton(
                      onPressed: () => Enlaces.abrir(Enlaces.condiciones),
                      child: const Text('Condiciones de uso')),
                  TextButton(
                      onPressed: () => Enlaces.abrir(Enlaces.soporte),
                      child: const Text('Soporte')),
                ],
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
                    // Sin sesión no hay citas que comprobar en segundo plano.
                    await pararComprobacionDeCitas();
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
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: Tono.rojoTinta),
              onPressed: () => _borrarCuenta(context),
              child: const Text('Borrar mi cuenta'),
            ),
          ),
        ],
      ),
    );
  }

  /// Borrar la cuenta se lleva todo lo del servidor en el acto. Se pide
  /// escribir BORRAR: un sí/no se acepta sin leerlo, y esto no se deshace.
  /// Después se ofrece borrar también lo del móvil, que es otra decisión:
  /// hay quien quiere irse del servidor y seguir con su diario en el teléfono.
  Future<void> _borrarCuenta(BuildContext context) async {
    final nube = context.nube;
    final almacen = context.almacen;
    final control = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, poner) => AlertDialog(
          title: const Text('Borrar mi cuenta'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Se borran en el acto la cuenta y todo lo copiado a ella: coches, '
                'diario, facturas, lecturas y citas. No se puede deshacer.\n\n'
                'Escribe BORRAR para confirmar.',
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: control,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'BORRAR'),
                onChanged: (_) => poner(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            TextButton(
              onPressed: control.text.trim().toUpperCase() == 'BORRAR'
                  ? () => Navigator.pop(c, true)
                  : null,
              style: TextButton.styleFrom(foregroundColor: Tono.rojoTinta),
              child: const Text('Borrar la cuenta'),
            ),
          ],
        ),
      ),
    );
    control.dispose();
    if (ok != true || !context.mounted) return;
    final fallo = await nube.borrarCuenta();
    if (!context.mounted) return;
    if (fallo != null) {
      avisar(context, fallo);
      return;
    }
    await almacen.olvidarNube();
    await pararComprobacionDeCitas();
    if (!context.mounted) return;
    final tambienMovil = await confirmar(
      context,
      titulo: 'Cuenta borrada',
      texto: 'Tu cuenta y su copia ya no existen. Lo que hay en este móvil sigue aquí: '
          '¿lo borramos también? Si lo dejas, la app sigue funcionando sin cuenta.',
      accion: 'Borrar también el móvil',
    );
    if (tambienMovil) await almacen.borrarTodo();
    if (context.mounted) avisar(context, tambienMovil ? 'Todo borrado.' : 'Cuenta borrada. Tus datos siguen en este móvil.');
  }

  /// La versión, y la nueva si la hay. La comprobación de fondo es cada seis
  /// horas; el botón la fuerza. Instalar abre el instalador del sistema, que
  /// pide permiso la primera vez y conserva los datos: misma firma, misma app.
  Widget _actualizacion(BuildContext context) {
    final a = context.actualizacion;
    a.leerVersionActual();
    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Mi Vehículo ${a.versionActual.isEmpty ? '' : a.versionActual}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              if (a.hayNueva)
                ChipEstado('Nueva: ${a.versionNueva}', tono: TonoEstado.accion)
              else if (!a.comprobando && a.ultimaComprobacion != null)
                const ChipEstado('Al día', tono: TonoEstado.calma),
            ],
          ),
          if (a.hayNueva) ...[
            const SizedBox(height: 8),
            if (a.notas.trim().isNotEmpty)
              Text(a.notas.trim(),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Tono.tintaSuave, height: 1.4)),
            const SizedBox(height: 10),
            if (a.descargando) ...[
              LinearProgressIndicator(value: a.progreso, minHeight: 6, borderRadius: BorderRadius.circular(3)),
              const SizedBox(height: 6),
              Text('Descargando… ${(a.progreso * 100).round()} %',
                  style: const TextStyle(fontSize: 12, color: Tono.tintaSuave)),
            ] else
              FilledButton.icon(
                onPressed: () async {
                  final motivo = await a.descargarEInstalar();
                  if (motivo != null && context.mounted) avisar(context, motivo);
                },
                icon: const Icon(Icons.system_update),
                label: Text('Descargar e instalar ${a.versionNueva}'
                    '${a.tamanoApk > 0 ? ' · ${(a.tamanoApk / 1048576).round()} MB' : ''}'),
              ),
          ],
          if (a.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(a.error!, style: const TextStyle(fontSize: 12, color: Tono.naranjaTinta)),
            ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: a.comprobando ? null : () => a.comprobar(forzar: true),
            child: Text(a.comprobando ? 'Comprobando…' : 'Buscar una versión nueva'),
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

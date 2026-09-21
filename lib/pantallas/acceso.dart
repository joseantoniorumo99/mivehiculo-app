/// ENTRAR, CREAR CUENTA, O SEGUIR SIN CUENTA.
///
/// La cuenta es OPCIONAL y se dice claro: sin ella todo funciona y los datos
/// viven en este móvil. Con ella, se copian a la nube y salen en el
/// ordenador (la versión web) y en cualquier otro móvil. No se pide nada más
/// que correo y contraseña: el nombre es para saludar.
library;

import 'package:flutter/material.dart';

import '../estado.dart';
import '../datos/nube.dart';
import '../tema.dart';

class PantallaAcceso extends StatefulWidget {
  /// Si se puede salir sin cuenta (primera vez) o es un "entrar" desde el
  /// perfil, donde ya se está sin cuenta.
  final bool ofrecerSinCuenta;
  const PantallaAcceso({super.key, this.ofrecerSinCuenta = true});

  @override
  State<PantallaAcceso> createState() => _PantallaAccesoState();
}

class _PantallaAccesoState extends State<PantallaAcceso> {
  bool _creando = false;
  final _forma = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  bool _verClave = false;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _correo.dispose();
    _clave.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_forma.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    final nube = context.nube;
    final almacen = context.almacen;
    try {
      if (_creando) {
        await nube.registrar(_nombre.text, _correo.text, _clave.text);
      } else {
        await nube.entrar(_correo.text, _clave.text);
      }
      // Lo de este móvil se sube y lo de la cuenta se baja. Sin esperar aquí:
      // la pantalla del perfil enseña cómo va.
      // ignore: unawaited_futures
      nube.sincronizar(almacen);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = Nube.explicar(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Con Google no hay contraseña que teclear ni correo que verificar: Google
  /// ya lo verificó. Es la puerta que más gente usa en el móvil.
  Future<void> _conGoogle() async {
    setState(() {
      _enviando = true;
      _error = null;
    });
    final nube = context.nube;
    final almacen = context.almacen;
    try {
      await nube.entrarConGoogle();
      // ignore: unawaited_futures
      nube.sincronizar(almacen);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // Cerrar el navegador sin terminar no es un error que haya que explicar
      final texto = Nube.explicar(e);
      setState(() => _error = texto.toLowerCase().contains('cancel') ? null : texto);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _claveNueva() async {
    if (_correo.text.trim().isEmpty) {
      setState(() => _error = 'Escribe tu correo arriba y vuelve a pulsar.');
      return;
    }
    try {
      await context.nube.pedirClaveNueva(_correo.text);
      if (mounted) avisar(context, 'Te hemos mandado un correo para poner una contraseña nueva.');
    } catch (e) {
      setState(() => _error = Nube.explicar(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_creando ? 'Crear cuenta' : 'Entrar')),
      body: SafeArea(
        child: Form(
          key: _forma,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const Text(
                'Con cuenta, tu coche y tu diario se copian a la nube y salen en el '
                'ordenador y en cualquier otro móvil. Sin cuenta, todo funciona igual '
                'y vive solo en este teléfono.',
                style: TextStyle(color: Tono.tintaSuave, height: 1.45),
              ),
              const SizedBox(height: 18),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Ya tengo cuenta')),
                  ButtonSegment(value: true, label: Text('Crear una')),
                ],
                selected: {_creando},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() {
                  _creando = s.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: 18),
              if (_creando) ...[
                TextFormField(
                  controller: _nombre,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Cómo te llamas'),
                  validator: (t) => (t == null || t.trim().isEmpty) ? 'Un nombre, para saludarte' : null,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _correo,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Correo'),
                validator: (t) => (t == null || !t.contains('@')) ? 'Un correo válido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _clave,
                obscureText: !_verClave,

                /// SIN CORRECTOR NI SUGERENCIAS. Un teclado como el de Samsung
                /// "corrige" lo que escribes en un campo normal aunque vaya
                /// oculto, y una contraseña corregida es una contraseña
                /// distinta: el usuario la tecleaba bien y no entraba, hasta
                /// que la cambió por otra. No era la contraseña, era el
                /// corrector.
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  helperText: _creando ? 'Al menos 8 caracteres' : null,
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _verClave = !_verClave),
                    icon: Icon(_verClave ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
                validator: (t) => (t == null || t.length < 8) ? 'Al menos 8 caracteres' : null,
                onFieldSubmitted: (_) => _enviar(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Recuadro(_error!, tono: TonoEstado.urgente),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _enviando ? null : _enviar,
                child: Text(_enviando ? 'Un momento…' : (_creando ? 'Crear la cuenta' : 'Entrar')),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _enviando ? null : _conGoogle,
                icon: const Icon(Icons.g_mobiledata, size: 28),
                label: const Text('Continuar con Google'),
              ),
              if (!_creando)
                TextButton(onPressed: _claveNueva, child: const Text('He olvidado la contraseña')),
              if (widget.ofrecerSinCuenta) ...[
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Seguir sin cuenta'),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Puedes crearla más tarde desde el perfil; lo que anotes hasta '
                  'entonces se subirá.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Tono.tintaSuave),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

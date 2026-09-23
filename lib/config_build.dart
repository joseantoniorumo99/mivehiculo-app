/// Qué variante de la app es esta compilación.
///
/// Se decide en el momento de compilar, con `--dart-define=PLAY_STORE=true`.
/// Sin ese argumento (la compilación de siempre, para GitHub) vale `false`.
///
/// Por qué existe: Google Play prohíbe que una app se actualice a sí misma
/// instalando otro APK por su cuenta ("Apps distributed via Google Play may
/// not modify, replace or update their own APK... using any method other
/// than Google Play's update mechanism"). La versión de Play tiene que ser
/// una app distinta en ese sentido: sin el permiso REQUEST_INSTALL_PACKAGES
/// (quitado en el manifiesto del flavor `play`) y sin el código que
/// comprueba y descarga versiones de GitHub, para que ni el permiso ni el
/// comportamiento aparezcan en el binario que sube a la consola.
///
/// La versión de GitHub sigue exactamente igual que siempre: este valor es
/// `false` si no se dice lo contrario, así que un `flutter build apk
/// --release --flavor github` sin más se comporta como antes de que esto
/// existiera.
const bool esVersionPlay = bool.fromEnvironment('PLAY_STORE');

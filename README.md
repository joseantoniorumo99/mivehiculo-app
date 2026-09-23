# Mi Vehículo

App de Android para llevar el libro de mantenimiento de tu coche: el diario
de lo que se le hace, los avisos de lo que toca, la lectura del motor por
**OBD-II** con un lector ELM327 de Bluetooth clásico, los talleres cercanos y
el expediente completo para enseñar cuando lo vendas.

**Versión 1.7.0: la vista del dueño del coche.** El lado del taller vive en
la versión web (PC): las citas que se piden desde el móvil le llegan allí a
través de la cuenta, y lo que el taller conteste —confirmada, con su tiempo y
forma de pago, o el informe de lo que hizo— vuelve al móvil como aviso.

## Qué hace

- **Inicio**: kilómetros, gasto del periodo, próxima ITV y avisos abiertos,
  con la gráfica de gasto por meses, bimestres o años. Ningún porcentaje sin
  dos periodos comparables de verdad; ninguna gráfica plana fingiendo dato.
- **Diario**: cada intervención con fecha, km, coste, taller, desglose de la
  factura línea a línea y la foto de la factura, guardada dentro de la app.
- **Avisos**: ITV por la norma (a los 4 años, cada 2 hasta los 10, luego
  anual) desde la fecha de matriculación —que sale sola de la matrícula, al
  mes— y, si hay una ITV anotada, **desde esa ITV**, que es la que vale;
  aceite, neumáticos, frenos y correa desde la última anotación del diario,
  contando también lo que iba dentro de una revisión general. Sin saber
  cuándo se hizo la última vez, **no se avisa**: adivinar sería mentir.
- **OBD**: conecta con el lector, pregunta al coche qué datos soporta y los
  lee todos; testigo del motor, códigos de avería, bastidor, sondas lambda…
  Lo que la app aún no sabe interpretar lo enseña en hexadecimal en vez de
  callárselo. Y **en vivo**: tras la primera pasada los datos se refrescan
  cada segundo mientras miras la pestaña, y «Guardar» coge ese momento.
- **Lecturas automáticas**, aparte del diario: al abrir la app con el coche
  en contacto se lee sola; y, si lo enciendes en «Lectura automática»,
  también cuando el móvil se conecta al Bluetooth del coche o cada cierto
  tiempo. Cada opción dice lo que cuesta en batería. Nunca hay un servicio
  permanente escuchando.
- **Mapa**: talleres, gasolineras, lavaderos, recambios y desguaces de
  OpenStreetMap, con distancia desde ti, horario y «abierto ahora», llamar y
  cómo llegar. Un aviso lleva directo a los talleres que hacen eso.
- **Citas**: «Pedir cita» está a un toque desde el inicio, el diario y las
  citas, y enseña primero los talleres que ya conoces; el mapa es para
  encontrar otro. Con cuenta se envían al taller por la función del servidor
  (la misma que usa la web); sin cuenta, o si el taller no usa la app, se
  anotan en el móvil y la pantalla dice que hay que llamar.
- **Avisos del taller**: cuando el taller confirma (con tiempo aproximado,
  forma de pago, presupuesto y mensaje), rechaza con motivo o manda el
  **informe** de lo que hizo, llega un aviso a la bandeja del móvil. Son
  avisos locales, sin servicio de push: los pone la app al sincronizar y una
  comprobación cada media hora con la app cerrada. El informe se añade al
  diario con un botón, con su desglose línea a línea.
- **Ficha técnica por foto**: una foto de la tarjeta ITV rellena marca, modelo,
  año, combustible, motor y bastidor. Se lee en el móvil (ML Kit, sin conexión)
  buscando los códigos de la tarjeta (D.1, D.3, E, P.1…); rellena solo lo que
  esté vacío, valida el bastidor y lo dice todo antes de guardar.
- **Mejoras para tu coche**: piezas y trabajos que mejoran rendimiento, consumo
  o vida del coche, deducidos del combustible, la edad, los kilómetros y el
  diario. Cada uno con su motivo, lo que se gana y los talleres que lo hacen.
- **Lo que publica el taller**: en la ficha de un taller salen sus servicios con
  tiempo aproximado y precio de partida, y lo que ofrece además, tal y como él
  lo rellenó en su panel. Sus fotos de las piezas llegan con el informe y pasan
  al diario con la intervención.
- **Credibilidad y coche verificado**: cada anotación dice si la hizo el taller,
  si el dueño la anotó con factura o fotos, o sin pruebas. Y el coche queda
  «verificado» cuando el bastidor de la ficha técnica coincide con el que lee
  el OBD dentro del coche: posesión y documento, sin guardar papeles.
- **Ofertas de talleres**: apartado propio con lo que publican los talleres
  cerca, por cercanía. Es la única publicidad de la app y vive aparte.
- **Informe completo en PDF**: el historial del coche para quien lo compre
  (datos, resumen, ITV y avisos, todas las intervenciones con desglose, las
  lecturas del OBD, los informes de taller, y los años sin documentar a la
  vista). Se genera en el móvil y se comparte desde él; también como texto.
- **Cuenta (opcional)**, con correo o con Google: sin ella todo funciona y vive en el móvil. Con ella,
  se copia a la nube y sale en la web y en otros móviles.
- **Se actualiza sola**: comprueba las releases de GitHub cada seis horas,
  avisa en el inicio, y descarga e instala desde el perfil.

## Por qué una app y no la web

Porque un ELM327 corriente habla **Bluetooth clásico (SPP/RFCOMM)** y ningún
navegador llega ahí:

| | Bluetooth clásico (SPP) | BLE |
|---|---|---|
| **Web Bluetooth** | ❌ no expone SPP, por diseño | ✅ |
| **Web Serial** | ✅ pero **solo en ordenador** (puerto COM) | — |
| **Android nativo** | ✅ | ✅ |
| **iOS** | ❌ Apple no expone SPP sin licencia MFi | ✅ |

El síntoma es inconfundible: el lector aparece en los ajustes de Bluetooth
del móvil y **no** aparece en el selector del navegador.

## Cómo está montado

```
lib/datos/modelo.dart          vehículos, intervenciones, citas, lecturas (JSON)
lib/datos/almacen.dart         el guardado local y las marcas de sincronización
lib/datos/nube.dart            la cuenta y la copia en Appwrite
lib/datos/actualizacion.dart   la autoactualización desde las releases de GitHub
lib/datos/mantenimiento.dart   ITV, avisos, AdBlue, huecos, formato
lib/datos/panel.dart           la serie de gasto y las cuatro cifras del inicio
lib/datos/matricula.dart       de la matrícula española al mes de matriculación
lib/datos/catalogo.dart        51 marcas, 763 modelos, 5.522 motorizaciones (EEA)
lib/lugares/lugares.dart       OpenStreetMap → sitios, horarios, distancias
lib/obd/protocolo.dart         el protocolo OBD-II, sin saber por dónde viaja
lib/obd/transporte_bluetooth.dart  el diálogo con el ELM327 + un simulador
lib/obd/enlace_classic.dart    lo único que sabe qué paquete de Bluetooth se usa
lib/obd/lectura_fondo.dart     la lectura en segundo plano (WorkManager)
lib/pantallas/                 una pantalla por fichero
android/.../ReceptorBluetooth.kt  despierta la app cuando el móvil se conecta al coche
```

**El móvil manda y la nube es la copia.** La app arranca, funciona y guarda
sin cuenta y sin red. Con cuenta, cada cambio se sube en cuanto hay red y al
volver a la app se baja lo que haya de otros aparatos; si el mismo dato se
tocó en dos sitios, gana el más reciente. En el servidor hay una sola tabla
con el objeto entero en JSON y permisos por usuario impuestos por el
servidor, y un cubo para las fotos de las facturas.

**Un cero es un dato; la ausencia, no.** Un `km` que no se sabe es `null`,
nunca `0`. Confundirlos es lo que hace que una app enseñe un coche sin usar.

**El año que escribe el dueño manda sobre la matrícula.** La matrícula data
la matriculación en España al mes (tabla mensual completa desde 2000); un
coche importado lleva la matrícula del día que llegó, y para la ITV cuenta su
primera matriculación en origen. Por eso las motorizaciones nunca se esconden
por año: se ordenan, y se enseñan con sus años de venta y sus cm³.

## El OBD, escrito desde el estándar

- Comandos del adaptador → hoja de datos pública del **ELM327**.
- PIDs del modo 01 y sus fórmulas → **SAE J1979** (68 PID, incluidos los que
  no son números: testigo, sistema de combustible, norma OBD, sondas).
- Estructura de los códigos de avería → **SAE J2012**.

Se miró [AndrOBD](https://github.com/fr3ts0n/AndrOBD) para entender cómo se
comporta un adaptador real, pero **no se ha copiado ni portado nada suyo**:
es GPL-3.0 y obligaría a abrir toda la app bajo la misma licencia.

Lo que costó que conectara de verdad, por si a alguien le sirve: antes de
abrir el socket hay que **parar la búsqueda de Bluetooth** (mientras dura, la
radio salta de canal y cualquier RFCOMM se cae), hay que **emparejar** si no
lo está (PIN 1234 o 0000), y muchos clones solo aceptan **socket inseguro**.
Y aceptan **un móvil a la vez**: si otro teléfono sigue enganchado, el
segundo no entra.

## Probar

```bash
flutter pub get
flutter test        # 144 pruebas: protocolo, ITV, avisos, panel, matrícula, sitios, almacén, citas, PDF, ficha técnica, consejos
flutter run         # con el móvil conectado por USB
```

Para leer un coche de verdad: enchufa el lector y **da el contacto** (se
alimenta del pin 16 del conector; sin eso ni se enciende). La app busca el
lector, lo empareja y lee.

## Releases

Dos flavors de Android, misma app, mismo `applicationId`:

- **`github`**: la de siempre. Se actualiza sola desde las Releases de este
  repo. `flutter build apk --release --flavor github`.
- **`play`**: para Google Play, que prohíbe que una app instale otro APK por
  su cuenta. No lleva el permiso `REQUEST_INSTALL_PACKAGES`
  (`android/app/src/play/AndroidManifest.xml` lo quita) ni el código que
  comprueba y descarga versiones (`lib/config_build.dart`, apagado con
  `--dart-define=PLAY_STORE=true`). `flutter build appbundle --release
  --flavor play --dart-define=PLAY_STORE=true`.

Con flavors definidos, `flutter build` sin `--flavor` para y pide elegir uno.

Cada versión de GitHub se publica como release con el APK adjunto. Todas van
firmadas con la **misma clave** (fuera del repo, en `android/key.properties`,
ignorado por git): sin eso Android no instalaría una versión encima de la
anterior y habría que desinstalar. La de Play, en su primera subida, usa la
misma clave como "clave de subida" (Play App Signing la vuelve a firmar con la
suya para distribuir).

## Servidor (opcional)

La cuenta usa un proyecto de Appwrite. Para montarlo hace falta una tabla
`documentos` y un cubo `facturas` con seguridad por fila y por fichero, y
registrar la app como plataforma Android (`es.regislab.mivehiculo`). Las citas
van por una tabla `citas` (con las columnas de texto `respuesta` e `informe`,
JSON) y una función `citas` que las crea con el permiso del taller. Sin
servidor la app funciona igual: lo dice en el perfil y se queda en local.

## Datos de terceros

- Mapas y sitios: © OpenStreetMap y sus colaboradores, ODbL.
- Catálogo de coches: matriculaciones en España publicadas por la Agencia
  Europea de Medio Ambiente. Cubre 2010–2022; fuera de ahí se elige a mano.
- Series de matrículas por mes: tablas públicas de seguimiento de la DGT.

## Licencia

Sin licencia declarada todavía. Las dependencias son MIT y BSD.

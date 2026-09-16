# Mi Vehículo

App de Android para llevar el libro de mantenimiento de tu coche: el diario
de lo que se le hace, los avisos de lo que toca, la lectura del motor por
**OBD-II** con un lector ELM327 de Bluetooth clásico, los talleres cercanos y
el expediente completo para enseñar cuando lo vendas.

**Versión 1.0.0: la vista del dueño del coche.** Sin nada de talleres (ese
lado vive en la versión web).

## Qué hace

- **Inicio**: kilómetros, gasto del periodo, próxima ITV y avisos abiertos,
  con la gráfica de gasto por meses, bimestres o años. Ningún porcentaje sin
  dos periodos comparables de verdad; ninguna gráfica plana fingiendo dato.
- **Diario**: cada intervención con fecha, km, coste, taller, desglose de la
  factura línea a línea y la foto de la factura, guardada dentro de la app.
- **Avisos**: ITV por la norma (a los 4 años, cada 2 hasta los 10, luego
  anual) desde la fecha de matriculación —que sale sola de la matrícula—;
  aceite, neumáticos, frenos y correa desde la última anotación del diario,
  contando también lo que iba dentro de una revisión general. Sin saber
  cuándo se hizo la última vez, **no se avisa**: adivinar sería mentir.
- **OBD**: conecta con el lector, pregunta al coche qué datos soporta y los
  lee todos; testigo del motor, códigos de avería, bastidor, sondas lambda…
  Lo que la app aún no sabe interpretar lo enseña en hexadecimal en vez de
  callárselo. Al abrir la app, si el lector contesta (o sea, si estás en el
  coche con el contacto dado), se hace una lectura sola y se guarda en
  **Lecturas**, aparte del diario. Nunca queda nada escuchando en segundo
  plano.
- **Mapa**: talleres, gasolineras, lavaderos, recambios y desguaces de
  OpenStreetMap, con distancia desde ti, horario y «abierto ahora», llamar y
  cómo llegar. Un aviso lleva directo a los talleres que hacen eso.
- **Citas**: se anotan en el móvil y se confirman llamando. Hasta que el
  taller use la app, la pantalla lo dice con todas las letras.
- **Expediente**: el historial entero con los años sin documentar a la vista,
  para compartir como texto.
- **Cuenta (opcional)**: sin ella todo funciona y vive en el móvil. Con ella,
  se copia a la nube y sale en la web y en otros móviles.

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
lib/datos/mantenimiento.dart   ITV, avisos, AdBlue, huecos, formato
lib/datos/panel.dart           la serie de gasto y las cuatro cifras del inicio
lib/datos/matricula.dart       de la matrícula española al mes de matriculación
lib/datos/catalogo.dart        52 marcas, 955 modelos, 3.905 motorizaciones (EEA)
lib/lugares/lugares.dart       OpenStreetMap → sitios, horarios, distancias
lib/obd/protocolo.dart         el protocolo OBD-II, sin saber por dónde viaja
lib/obd/transporte_bluetooth.dart  el diálogo con el ELM327 + un simulador
lib/obd/enlace_classic.dart    lo único que sabe qué paquete de Bluetooth se usa
lib/pantallas/                 una pantalla por fichero
```

**El móvil manda y la nube es la copia.** La app arranca, funciona y guarda
sin cuenta y sin red. Con cuenta, cada cambio se sube en cuanto hay red y al
volver a la app se baja lo que haya de otros aparatos; si el mismo dato se
tocó en dos sitios, gana el más reciente. En el servidor hay una sola tabla
con el objeto entero en JSON y permisos por usuario impuestos por el
servidor, y un cubo para las fotos de las facturas.

**Un cero es un dato; la ausencia, no.** Un `km` que no se sabe es `null`,
nunca `0`. Confundirlos es lo que hace que una app enseñe un coche sin usar.

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
Y aceptan **un móvil a la vez**.

## Probar

```bash
flutter pub get
flutter test        # 96 pruebas: protocolo, ITV, avisos, panel, matrícula, sitios, almacén
flutter run         # con el móvil conectado por USB
```

Para leer un coche de verdad: enchufa el lector y **da el contacto** (se
alimenta del pin 16 del conector; sin eso ni se enciende). La app busca el
lector, lo empareja y lee.

## Servidor (opcional)

La cuenta usa un proyecto de Appwrite. Para montarlo hace falta una tabla
`documentos` y un cubo `facturas` con seguridad por fila y por fichero, y
registrar la app como plataforma Android (`es.regislab.mivehiculo`). Sin
servidor la app funciona igual: lo dice en el perfil y se queda en local.

## Datos de terceros

- Mapas y sitios: © OpenStreetMap y sus colaboradores, ODbL.
- Catálogo de coches: matriculaciones en España publicadas por la Agencia
  Europea de Medio Ambiente. Cubre 2010–2022; fuera de ahí se elige a mano.

## Licencia

Sin licencia declarada todavía. Las dependencias son MIT y BSD.

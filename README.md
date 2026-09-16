# Mi Vehículo — lectura OBD-II por Bluetooth clásico

App de Android que habla con un lector **ELM327** por **Bluetooth clásico
(SPP/RFCOMM)** y lee del coche sus datos de motor, sus códigos de avería y el
bastidor.

## Por qué existe

Porque desde un navegador **no se puede**, y no por falta de intentarlo:

| | Bluetooth clásico (SPP) | BLE |
|---|---|---|
| **Web Bluetooth** | ❌ no expone SPP, por diseño | ✅ |
| **Web Serial** | ✅ pero **solo en ordenador** (puerto COM) | — |
| **Android nativo** | ✅ | ✅ |
| **iOS** | ❌ Apple no expone SPP sin licencia MFi | ✅ |

La mayoría de los ELM327 baratos son **clásicos**. El síntoma es
inconfundible: el lector aparece en los ajustes de Bluetooth del móvil y **no**
aparece en el selector del navegador. De ahí esta app.

Un detalle que confunde a todo el mundo: en los ajustes del móvil el lector
sale **«emparejado pero no conectado»**, y eso es *normal*. El enlace RFCOMM
solo se abre cuando una app lo pide.

## Cómo está montado

```
lib/obd/protocolo.dart             el protocolo OBD-II, sin saber por dónde viaja
lib/obd/transporte_bluetooth.dart  el diálogo con el ELM327 + un simulador
lib/obd/enlace_classic.dart        lo único que sabe qué paquete de Bluetooth se usa
lib/pantalla_obd.dart              la pantalla
```

El protocolo habla con un `Transporte`, que solo tiene que saber mandar una
línea de texto y devolver lo que conteste el adaptador. Por eso el Bluetooth
clásico y el simulador son intercambiables sin tocar una coma del análisis, y
por eso cambiar de paquete de Bluetooth es reescribir un fichero de 60 líneas.

## Escrito desde el estándar

- Comandos del adaptador → hoja de datos pública del **ELM327**.
- PIDs del modo 01 y sus fórmulas → **SAE J1979**.
- Estructura de los códigos de avería → **SAE J2012**.

Se miró [AndrOBD](https://github.com/fr3ts0n/AndrOBD) para entender cómo se
comporta un adaptador real, que es legítimo, pero **no se ha copiado ni
portado nada suyo**: es GPL-3.0 y obligaría a abrir toda la app bajo la misma
licencia.

## Dos reglas que gobiernan el código

**1. El simulador no puede mentir.** Existe para poder ver la pantalla sin
coche, y devuelve el mismo hexadecimal que un ELM327 real para que el análisis
se ejercite de verdad. Pero sus valores son inventados, así que: va marcado en
una banda a la vista, y **no se puede guardar en el historial del coche**. Unos
códigos inventados en el historial no se descubren hasta que vas a venderlo,
que es justo cuando el historial tiene que valer algo.

Y su mapa de PID soportados se **calcula** de su tabla de valores en vez de
escribirse a mano, para que nunca anuncie un dato que luego no da. Hay una
prueba que lo comprueba.

**2. Un cero es un dato; la ausencia, no.** Si el coche no da un PID se
devuelve `null`, nunca `0`. Confundirlos es lo que hace que una app enseñe un
depósito vacío que en realidad no se ha medido.

## Probar

```bash
flutter pub get
flutter test        # 14 pruebas del protocolo, sin coche ni lector
flutter run         # con el móvil conectado por USB
```

Para leer un coche de verdad: enchufa el lector, **da el contacto** (se
alimenta del pin 16 del conector, sin eso ni se enciende), empareja el lector
en los ajustes de Bluetooth del móvil y pulsa «Conectar con mi lector».

## Estado

Primera rebanada: **solo el OBD**. El resto del producto —diario de
mantenimientos, expediente del coche, mapa de talleres, citas— vive de momento
en una versión web y se irá portando pantalla a pantalla.

## Licencia

Sin licencia declarada todavía. Las dependencias que usa son MIT
(`flutter_classic_bluetooth`) y BSD (Flutter).

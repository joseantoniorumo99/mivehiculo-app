package com.mivehiculo.app

import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.BackgroundWorker
import dev.fluttercommunity.workmanager.buildTaskInputData
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

/**
 * "SABER CUÁNDO CONDUCES" SIN GASTAR BATERÍA.
 *
 * Android avisa a las apps dormidas de muy pocas cosas, y una de ellas es que
 * el móvil se ha conectado por Bluetooth a un aparato. Si ese aparato es el
 * coche —el manos libres, la radio, el que el dueño eligió en los ajustes—,
 * es que acaba de arrancar. Este receptor no lee nada: encola un trabajo de
 * WorkManager para dentro de medio minuto (el lector OBD tarda unos segundos
 * en encenderse tras dar el contacto) y se vuelve a dormir. Cero consumo
 * cuando no se conduce, que es lo que no da un sondeo periódico.
 *
 * El trabajo lo ejecuta el plugin `workmanager` de Flutter: arranca un motor
 * Dart sin pantalla y llama a la función registrada en `lectura_fondo.dart`.
 * Aquí se construye la petición exactamente como la construye el propio
 * plugin, con sus mismas claves, para que la reconozca.
 *
 * TODO LO QUE PASA SE APUNTA en el mismo registro que lee la app (la clave
 * `flutter.obd_fondo_registro` de las preferencias de Flutter): cada aparato
 * que se conecta, si es el elegido o no, y si se encoló la lectura. Sin eso,
 * "no me funcionó" no se puede convertir en un fallo concreto.
 */
class ReceptorBluetooth : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != BluetoothDevice.ACTION_ACL_CONNECTED) return

        @Suppress("DEPRECATION")
        val aparato: BluetoothDevice? = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        val direccion = aparato?.address ?: return
        val nombre = try { aparato.name ?: "sin nombre" } catch (e: SecurityException) { "sin permiso para el nombre" }

        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val elegido = prefs.getString("flutter.obd_coche_bt", null)
        val direccionElegida = elegido?.substringBefore('|')
        val esElCoche = direccionElegida != null && direccionElegida.equals(direccion, ignoreCase = true)

        apuntar(context, "Bluetooth conectado: $nombre ($direccion)" +
            when {
                elegido == null -> " · no hay coche elegido en Lectura automática"
                esElCoche -> " · ES el coche: lectura en 30 s"
                else -> " · no es el coche elegido ($direccionElegida)"
            })
        if (!esElCoche) return

        val datos = buildTaskInputData(
            dartTask = "com.mivehiculo.app.lecturaObd",
            payload = mapOf("motivo" to "bluetooth", "aparato" to direccion),
            foregroundServiceConfig = null,
            uniqueName = "lectura-obd-bluetooth",
        )
        val peticion = OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
            .setInputData(datos)
            .setInitialDelay(30, TimeUnit.SECONDS)
            .build()

        // REPLACE y no KEEP: el coche se conecta y desconecta varias veces al
        // arrancar; la última conexión es la buena y reinicia los 30 segundos.
        WorkManager.getInstance(context)
            .enqueueUniqueWork("lectura-obd-bluetooth", ExistingWorkPolicy.REPLACE, peticion)
    }

    /** Mismo formato que `RegistroFondo.apuntar` en Dart: "dd/MM HH:mm:ss  texto", 40 líneas. */
    private fun apuntar(context: Context, texto: String) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val sello = SimpleDateFormat("dd/MM HH:mm:ss", Locale.getDefault()).format(Date())
        val lineas = (prefs.getString("flutter.obd_fondo_registro", "") ?: "")
            .split('\n').filter { it.isNotEmpty() }.toMutableList()
        lineas.add("$sello  $texto")
        while (lineas.size > 40) lineas.removeAt(0)
        prefs.edit().putString("flutter.obd_fondo_registro", lineas.joinToString("\n")).apply()
    }
}

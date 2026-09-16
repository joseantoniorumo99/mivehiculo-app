package es.regislab.mivehiculo

import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.BackgroundWorker
import dev.fluttercommunity.workmanager.buildTaskInputData
import java.util.concurrent.TimeUnit

/**
 * "SABER CUÁNDO CONDUCES" SIN GASTAR BATERÍA.
 *
 * Android avisa a las apps dormidas de muy pocas cosas, y una de ellas es que
 * el móvil se ha conectado por Bluetooth a un aparato. Si ese aparato es el
 * coche —el manos libres, la radio, el que el dueño eligió en los ajustes—,
 * es que acaba de arrancar. Este receptor no lee nada: encola un trabajo de
 * WorkManager para dentro de un minuto (el lector OBD tarda unos segundos en
 * encenderse tras dar el contacto) y se vuelve a dormir. Cero consumo cuando
 * no se conduce, que es lo que no da un sondeo periódico.
 *
 * El trabajo lo ejecuta el plugin `workmanager` de Flutter: arranca un motor
 * Dart sin pantalla y llama a la función registrada en `lectura_fondo.dart`.
 * Aquí se construye la petición exactamente como la construye el propio
 * plugin, con sus mismas claves, para que la reconozca.
 */
class ReceptorBluetooth : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != BluetoothDevice.ACTION_ACL_CONNECTED) return

        @Suppress("DEPRECATION")
        val aparato: BluetoothDevice? = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        val direccion = aparato?.address ?: return

        // El aparato que el dueño marcó como "el coche", guardado desde Dart
        // con shared_preferences: fichero FlutterSharedPreferences, clave con
        // el prefijo "flutter.", valor "MAC|nombre".
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val elegido = prefs.getString("flutter.obd_coche_bt", null) ?: return
        val direccionElegida = elegido.substringBefore('|')
        if (!direccionElegida.equals(direccion, ignoreCase = true)) return

        val datos = buildTaskInputData(
            dartTask = "es.regislab.mivehiculo.lecturaObd",
            payload = mapOf("motivo" to "bluetooth", "aparato" to direccion),
            foregroundServiceConfig = null,
            uniqueName = "lectura-obd-bluetooth",
        )
        val peticion = OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
            .setInputData(datos)
            .setInitialDelay(50, TimeUnit.SECONDS)
            .build()

        // KEEP: si ya hay una lectura encolada por esta misma conexión, no se
        // apilan dos. El coche se conecta y desconecta varias veces al arrancar.
        WorkManager.getInstance(context)
            .enqueueUniqueWork("lectura-obd-bluetooth", ExistingWorkPolicy.KEEP, peticion)
    }
}

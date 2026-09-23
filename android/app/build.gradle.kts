import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/* LA FIRMA DE RELEASE.
   Las claves NO van en el repo: viven en android/key.properties (ignorado por
   git) y apuntan a un keystore fuera del proyecto. Sin ese fichero se firma
   con la clave de depuración, que vale para probar en el propio móvil y
   para nada más.

   Por qué importa: Android solo instala una versión nueva ENCIMA de la vieja
   si las dos llevan la misma firma. La autoactualización de la app depende
   de que TODAS las releases se firmen con este mismo keystore. Si se pierde,
   nadie podrá actualizar: habrá que desinstalar y perder los datos locales. */
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hayFirmaDeRelease = keystorePropertiesFile.exists()
if (hayFirmaDeRelease) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "es.regislab.mivehiculo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications usa java.time; en Android viejo no
        // existe y hay que "desazucararlo" al compilar.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "es.regislab.mivehiculo"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    /* DOS FORMAS DE REPARTIR LA MISMA APP.
       "github": la de siempre, se actualiza sola desde GitHub Releases.
       "play": para Google Play, que PROHÍBE que una app instale otro APK por
       su cuenta ("Apps distributed via Google Play may not modify, replace or
       update their own APK... using any method other than Google Play's
       update mechanism"). El permiso REQUEST_INSTALL_PACKAGES se quita en
       src/play/AndroidManifest.xml, y el código que comprueba y descarga
       versiones no se ejecuta en esa variante (lib/config_build.dart).
       Mismo applicationId en las dos: es la misma app, solo cambia por dónde
       se reparte. Sin --flavor, `flutter build` para y pide elegir uno. */
    flavorDimensions += "distribucion"
    productFlavors {
        create("github") {
            dimension = "distribucion"
        }
        create("play") {
            dimension = "distribucion"
        }
    }

    signingConfigs {
        if (hayFirmaDeRelease) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Reglas de R8: solo silencia clases de ML Kit que no se incluyen.
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = if (hayFirmaDeRelease) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // El receptor de Bluetooth encola trabajos de WorkManager él mismo; el
    // plugin lo trae como dependencia interna y no lo expone al proyecto.
    implementation("androidx.work:work-runtime:2.10.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

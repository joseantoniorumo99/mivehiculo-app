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
    }

    defaultConfig {
        applicationId = "es.regislab.mivehiculo"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
}

flutter {
    source = "../.."
}

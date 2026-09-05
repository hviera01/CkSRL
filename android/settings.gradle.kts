pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP 9 es el que trae Flutter por defecto ahora mismo, pero varios
    // plugins que todavía usamos (file_picker, mobile_scanner, share_plus)
    // no terminan de andar bien con el nuevo "Built-in Kotlin" de AGP 9 —
    // file_picker literalmente no compilaba ("cannot find symbol:
    // FilePickerPlugin"). Bajar a un AGP 8.x hace que esos plugins usen su
    // propio camino viejo y probado (Kotlin Gradle Plugin clásico), que sí
    // funciona. 8.11.1 es el mínimo que pide mobile_scanner (androidx.camera)
    // y que Flutter recomienda como piso.
    id("com.android.application") version "8.11.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.4.4") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")

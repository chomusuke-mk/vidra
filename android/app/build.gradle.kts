import java.io.File
import java.io.FileInputStream
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

fun Properties.readClean(key: String): String? {
    return getProperty(key)
        ?.trim()
        ?.removeSurrounding("\"")
        ?.removeSurrounding("'")
        ?.replace('\\', File.separatorChar)
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val cleanedStoreFilePath = keystoreProperties.readClean("storeFile")
val cleanedStorePassword = keystoreProperties.readClean("storePassword")
val cleanedKeyAlias = keystoreProperties.readClean("keyAlias")
val cleanedKeyPassword = keystoreProperties.readClean("keyPassword")
val releaseTasksRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
val minimumJavaVersion = JavaVersion.VERSION_21

if (JavaVersion.current() < minimumJavaVersion) {
    error("Vidra requiere Java 21 o superior; se detectó ${JavaVersion.current()}.")
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

kotlin {
    jvmToolchain(21)
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_21)
    }
}

android {
    namespace = "dev.chomusuke.vidra"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = minimumJavaVersion
        targetCompatibility = minimumJavaVersion
        isCoreLibraryDesugaringEnabled = true
    }

    packaging {
      jniLibs {
        useLegacyPackaging = true
        keepDebugSymbols.add("*/arm64-v8a/libpython*.so")
        keepDebugSymbols.add("*/armeabi-v7a/libpython*.so")
        keepDebugSymbols.add("*/x86/libpython*.so")
        keepDebugSymbols.add("*/x86_64/libpython*.so")
      }
    }

    defaultConfig {
        applicationId = "dev.chomusuke.vidra"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
          abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64"))
        }
    }

    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
            // Generate both per-ABI APKs and the universal (fat) APK.
            isUniversalApk = true
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            val keystoreFile = cleanedStoreFilePath?.let { rootProject.file(it) }
            val hasCredentials = !cleanedStorePassword.isNullOrBlank() &&
                !cleanedKeyAlias.isNullOrBlank() &&
                !cleanedKeyPassword.isNullOrBlank()

            if (keystoreFile != null && keystoreFile.exists() && hasCredentials) {
                create("release") {
                    storeFile = keystoreFile
                    storePassword = cleanedStorePassword
                    keyAlias = cleanedKeyAlias
                    keyPassword = cleanedKeyPassword
                }
            } else {
                val message = buildString {
                    append("La configuraci\u00f3n del certificado no es v\u00e1lida. ")
                    append("Revisa key.properties y confirma que el archivo exista en \"${cleanedStoreFilePath ?: "(sin ruta)"}\".")
                }
                if (releaseTasksRequested) {
                    error(message)
                } else {
                    logger.warn(message)
                }
            }
        } else if (releaseTasksRequested) {
                error("No se encontró key.properties. No es posible firmar el APK release.")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("com.google.android.material:material:1.12.0")
    // Required by Flutter's Play Store deferred components integration; otherwise R8 fails with
    // missing com.google.android.play.core.* classes.
    implementation("com.google.android.play:core:1.10.3")
}
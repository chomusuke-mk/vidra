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


plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.chomusuke.vidra"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
        isCoreLibraryDesugaringEnabled = true
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
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
          abiFilters.addAll(listOf("arm64-v8a", "x86_64"))
        }
    }

    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "x86_64")
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
                    append("La configuración del certificado no es válida. ")
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21
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
@file:Suppress("DEPRECATION")

import java.util.Base64
import java.util.Properties
import java.io.FileInputStream
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

fun dartDefine(chave: String, padrao: String): String {
    val propriedade = project.findProperty("dart-defines")?.toString()

    if (propriedade.isNullOrBlank()) {
        return padrao
    }

    return propriedade
        .split(",")
        .mapNotNull { item ->
            try {
                String(Base64.getDecoder().decode(item))
            } catch (_: Exception) {
                null
            }
        }
        .firstOrNull { item ->
            item.startsWith("$chave=")
        }
        ?.substringAfter("=")
        ?.takeIf { it.isNotBlank() }
        ?: padrao
}

val appPackage = dartDefine(
    "APP_PACKAGE",
    "br.com.apppreco.appmercado",
)

val appNome = dartDefine(
    "APP_NAME",
    "App Mercado",
)

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // O namespace é onde está a MainActivity.
    // Pode continuar fixo mesmo com applicationId dinâmico.
    namespace = "br.com.apppreco.appmercado"

    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        resValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Package real instalado no Android.
        // Fica dinâmico por loja via:
        // --dart-define=APP_PACKAGE=br.com.apppreco.mercado.saomateus
        applicationId = appPackage

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Nome exibido no celular.
        // Fica dinâmico por loja via:
        // --dart-define=APP_NAME=SM Compras
        resValue("string", "app_name", appNome)
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

tasks.withType<KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

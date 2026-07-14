@file:Suppress("DEPRECATION")

import java.util.Base64
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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
    }

    defaultConfig {
        // Package real instalado no Android.
        // Agora fica dinâmico por loja via:
        // --dart-define=APP_PACKAGE=br.com.apppreco.mercado.saomateus
        applicationId = appPackage

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Nome exibido no celular.
        // Agora fica dinâmico por loja via:
        // --dart-define=APP_NAME=SM Compras
        resValue("string", "app_name", appNome)
    }

    buildTypes {
        release {
            // Assinando com debug por enquanto.
            // Depois configuramos uma assinatura release oficial.
            signingConfig = signingConfigs.getByName("debug")
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


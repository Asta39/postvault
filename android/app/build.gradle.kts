import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. The keystore and its password live outside the repo:
// in ~/.android-keys/postvault-release.properties, or in the environment
// variables POSTVAULT_KEYSTORE, POSTVAULT_KEYSTORE_PASSWORD,
// POSTVAULT_KEY_ALIAS and POSTVAULT_KEY_PASSWORD (for CI).
// When neither is present, or POSTVAULT_DEBUG_SIGN=1, the debug key is used.
val releaseProps = Properties().apply {
    val f = File(System.getProperty("user.home"), ".android-keys/postvault-release.properties")
    if (f.isFile) f.inputStream().use { load(it) }
}
fun signingValue(prop: String, env: String): String? =
    System.getenv(env)?.takeIf { it.isNotBlank() } ?: releaseProps.getProperty(prop)

val releaseStoreFile = signingValue("storeFile", "POSTVAULT_KEYSTORE")
val releaseStorePassword = signingValue("storePassword", "POSTVAULT_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "POSTVAULT_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "POSTVAULT_KEY_PASSWORD")
val useReleaseKey = System.getenv("POSTVAULT_DEBUG_SIGN") != "1" &&
    listOf(releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword).all { it != null } &&
    File(releaseStoreFile!!).isFile

android {
    namespace = "com.ianlove.postvault"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ianlove.postvault"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (useReleaseKey) {
            create("release") {
                storeFile = File(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (useReleaseKey) "release" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.streamio.streamio"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.streamio.streamio"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // CastControlChannel.kt talks to the Cast SDK directly, because
    // flutter_chrome_cast exposes no API for custom namespaces (see the class
    // comment there). flutter_chrome_cast already pulls this in, but as an
    // `implementation` dependency of *its* module — which keeps it off this
    // module's compile classpath. Keep the version equal to the one in that
    // plugin's android/build.gradle: two different versions on one classpath
    // is a dependency-resolution surprise waiting for a plugin upgrade.
    implementation("com.google.android.gms:play-services-cast-framework:21.5.0")
}

flutter {
    source = "../.."
}

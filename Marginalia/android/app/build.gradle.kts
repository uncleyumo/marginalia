plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.marginalia.reader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.marginalia.reader"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // The phone is arm64-v8a (a Xiaomi / Redmi), and a debug build otherwise
    // ships the Dart AOT snapshot, the engine and every plugin's native library
    // for ALL the ABIs Flutter supports. That made the APK 100 MB, which is
    // slow to install and is what triggered a timeout-ish install on a phone
    // that had to prompt for permission.
    //
    // Splitting by ABI means the arm64 one that actually gets installed is a
    // fraction of that. `flutter run` picks the matching split automatically;
    // nothing here changes how the app is built or what it does.
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            // universalApk keeps a single all-ABI file for anyone who wants it.
            isUniversalApk = true
        }
    }

    buildTypes {
        release {
            // Signing with the debug keys, so `flutter run --release` works.
            // A real release would replace this; the app ships no server and
            // stores no key of the reader's, so there is nothing to protect here
            // that a debug key does not already expose.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
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
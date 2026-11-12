plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ai.velopath.roadguard"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "ai.velopath.roadguard"
        minSdk = 26
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            pickFirsts += listOf("**/libvelopath_engine.so", "**/libonnxruntime.so", "**/libtflite_c.so")
            keepDebugSymbols += listOf("**/libvelopath_engine.so")
        }
    }

    aaptOptions {
        noCompress += listOf("tflite", "onnx")
    }

    signingConfigs {
        create("release") {
            val keyStorePath = System.getenv("ANDROID_KEYSTORE_PATH")
            val keyStorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            val keyName = System.getenv("ANDROID_KEY_ALIAS")
            val keyPasswordVal = System.getenv("ANDROID_KEY_PASSWORD")

            if (keyStorePath != null && file(keyStorePath).exists()) {
                storeFile = file(keyStorePath)
                storePassword = keyStorePassword
                keyAlias = keyName
                keyPassword = keyPasswordVal
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    buildTypes {
        release {
            val releaseConfig = signingConfigs.getByName("release")
            signingConfig = if (releaseConfig.storeFile != null && releaseConfig.storeFile!!.exists()) {
                releaseConfig
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

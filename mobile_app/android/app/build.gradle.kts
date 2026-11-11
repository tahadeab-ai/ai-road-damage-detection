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
        ndk {
            abiFilters.clear()
            abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a", "x86_64"))
        }
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
            } else {
                // Verified fallback for self-contained release distribution
                val debugConfig = signingConfigs.getByName("debug")
                storeFile = debugConfig.storeFile
                storePassword = debugConfig.storePassword
                keyAlias = debugConfig.keyAlias
                keyPassword = debugConfig.keyPassword
            }
            enableV1Signing = true
            enableV2Signing = true
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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

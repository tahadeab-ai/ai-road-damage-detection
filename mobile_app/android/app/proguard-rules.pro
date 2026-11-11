# Flutter and Android Core Proguard Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# TensorFlow Lite Native & JNI bindings
-dontwarn org.tensorflow.lite.gpu.**
-dontwarn org.tensorflow.lite.**
-keep class org.tensorflow.lite.** { *; }
-keep class com.tflite.** { *; }

# Camera, Hardware, Audio & Geolocator Plugins
-keep class io.flutter.plugins.camera.** { *; }
-keep class com.baseflow.geolocator.** { *; }
-keep class xyz.luan.audioplayers.** { *; }

# Hive & Persistence serialization
-keep class io.hive.** { *; }

# VeloPath AI Native FFI bindings
-keep class ai.velopath.roadguard.** { *; }
-dontwarn ai.velopath.roadguard.**
-keepclasseswithmembernames class * {
    native <methods>;
}

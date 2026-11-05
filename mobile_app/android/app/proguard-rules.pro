# TensorFlow Lite R8 / Proguard rules
-dontwarn org.tensorflow.lite.gpu.**
-dontwarn org.tensorflow.lite.**
-keep class org.tensorflow.lite.** { *; }

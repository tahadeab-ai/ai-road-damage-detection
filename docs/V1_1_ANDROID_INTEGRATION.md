# RoadGuard AI V1.1 — Android Edge Integration Guide

**Platform**: Android (minSdk 24, targetSdk 34, compileSdk 36)  
**Architectures**: `arm64-v8a` (Primary), `armeabi-v7a` (Fallback)  
**Runtimes**: Flutter 3.38+ / Dart 3.10+ with ONNX Runtime Mobile (`onnxruntime: ^1.2.1`)  

---

## 1. Native Dependencies & JNI Configuration

The production APK bundles native ONNX Runtime C/C++ engine libraries:
- `lib/arm64-v8a/libonnxruntime.so` (14.2 MB)
- `lib/armeabi-v7a/libonnxruntime.so` (9.8 MB)

### ProGuard Rules (`android/app/proguard-rules.pro`):
```proguard
-keep class ai.onnxruntime.** { *; }
-keep class com.roadguard.** { *; }
-dontwarn ai.onnxruntime.**
```

---

## 2. Model Asset Packaging

The mobile asset bundle contains:
- `assets/models/roadguard-yolo-v1.1.0.onnx`: Dynamic INT8 quantized 4-class detector (3.03 MB).
- `assets/models/labels.txt`: Class index mapping for `D00`, `D10`, `D20`, `D40`.

---

## 3. UI/UX Automotive Driving Experience

1. **Top Automotive HUD Bar**:
   - Real-time GPS Speedometer (`KM/H`).
   - Inference Latency and FPS Telemetry Tag.
   - Quick Language Switcher (`عربي` $\leftrightarrow$ `EN`).
   - Confirmed Hazard Counter.
2. **Scene Intelligence Status Pill**:
   - Displays real-time scene classification state:
     - 🔍 *Checking scene...*
     - 🛣️ *Road detected*
     - 🚫 *Road not detected* (Damage scanning automatically paused)
     - ⚠️ *Hazard detected*
     - 🎯 *Tracking hazard*
3. **Bounding Box Overlay**:
   - Dashed corner brackets with defect color.
   - Label with Track ID and confirmed confidence percentage: `#001 حفرة 84%`.
   - Pulsing emergency halo for severe potholes (`D40`).
   - Off-road watermark when non-road scene is observed.

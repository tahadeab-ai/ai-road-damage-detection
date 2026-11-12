# VeloPath AI v2.0.1 — Hotfix: Android Launch Crash & Local ARM64 Build

### 🚀 Critical Hotfix Overview
This patch release directly resolves the immediate Android launch crash ("VeloPath AI closed because this app has a bug") observed on Android 12–15 Samsung devices.

### 🛠️ Root Causes Resolved
1. **Package & Activity Mismatch (`ClassNotFoundException`):**
   - Relocated `MainActivity.kt` to `mobile_app/android/app/src/main/kotlin/ai/velopath/roadguard/MainActivity.kt`.
   - Updated package namespace to `ai.velopath.roadguard`, perfectly aligned with `applicationId` and `AndroidManifest.xml` (`.MainActivity`).
2. **Native Library Safety (`libvelopath_engine.so`):**
   - Packaged pre-compiled ARM64-v8a native Rust engine library into `jniLibs/arm64-v8a/`.
   - All FFI exports wrapped in `std::panic::catch_unwind` to prevent native `SIGABRT` crashes.
   - `rusqlite` statically compiled with `bundled` SQLite, avoiding Android 12+ private namespace linker blocks.
3. **Resilient Startup & Exception Boundary:**
   - Wrapped Dart `main()` in `runZonedGuarded` with a Cyber-Automotive Dark HUD `ErrorWidget.builder`.
   - FFI symbol loading in `velopath_rust_bridge.dart` is wrapped in safe `try/catch` fallbacks.
4. **Official Quantized Model Bundled:**
   - Bundled verified `yolo11n_int8.tflite` (3.24 MB, SHA256: `5e48e596...`) directly into `assets/flutter_assets/assets/models/`.

### 📦 Release Assets & Verification
- **Target Device:** Android 8.0+ (API 26+) ARM64 (Samsung Galaxy / Google Pixel / OnePlus)
- **APK File:** `app-arm64-v8a-release.apk`
- **File Size:** ~36.6 MB
- **SHA-256:** `98505ef28cd7ec8611a4626977933552d034ae5a218f49367e9889bac04f3bb0`

# VeloPath AI v2.2.0 — Production Hardware Stabilization & Genuine RDD2022 Neural Weights

### 🚀 Highlights & Critical Hardware Fixes:
1. **Samsung Semi-Planar UV Buffer Resilience (`RangeError` Elimination):**
   - Fixed native YUV420 semi-planar buffer access on Samsung Exynos/Snapdragon devices where UV planes are truncated (`width * height / 2 - 1`).
   - Implemented strict index bounds clamping (`safeYIndex`, `safeUIndex`, `safeVIndex`) and full fallback support for 3-plane YUV420, 2-plane NV12/NV21, and single-plane NV21 camera hardware.

2. **Zero-Lag Event Loop & Anti-Flooding Frame Gate:**
   - Added `_isSubmittingFrame` gate and `DetectionBloc.isProcessingFrame` check in `driving_detector_screen.dart` to prevent flooding the Dart event queue with unconsumed `CameraImage` objects.
   - Guaranteed `try / finally` state release so `_isProcessingFrame` resets immediately.

3. **Genuine RDD2022 4-Class INT8 Weights (`yolo11n_int8.tflite`):**
   - Replaced temporary COCO 80-class weights with genuine trained RDD2022 INT8 quantized weights exported via Ultralytics LiteRT in Google Colab.
   - Tensor shapes verified: Input `[1, 3, 640, 640]` float32, Output `[1, 8, 8400]` float32.
   - Damage taxonomy: `D00` (Longitudinal Crack), `D10` (Transverse Crack), `D20` (Alligator Crack), `D40` (Pothole).
   - SHA-256: `c9e96a6c569aa28116ebd639bd7aa2d21f7239d84e74a717e3a0c08996a23595`.

4. **Cockpit HUD Live Frame Pulse & Diagnostics:**
   - Added real-time glowing green frame pulse dot in Cockpit HUD top card that pulses on every active frame.
   - Added on-screen `PIPELINE WARNING` diagnostic banner in Amber/Crimson displaying any frame-level or hardware exceptions.
   - Bench Test Mode auto-switch: Bypasses surface gate, overrides speed threshold (`0 KM/H`), and lowers detection threshold to `0.12`.

5. **Cyber AR Reticle & Metric Sizing:**
   - Enhanced ADAS reticle with real-time metric width estimation (`~25cm`, `~1.2m`) alongside class badges, severity scores, and pulsing pothole halo.

---

### 📦 Release Assets:
- `app-arm64-v8a-release.apk` (54.2 MB) — Release APK for Android ARM64 devices (Android 8.0+ / SDK 26–34).
- `yolo11n_int8.tflite` (3.02 MB) — Genuine trained 4-class RDD2022 INT8 model weights.
- `libvelopath_engine.so` (2.05 MB) — Native Rust SIMD acceleration engine for ARM64.
- `model_manifest.json` — Model metadata and SHA-256 verification manifest.

# VeloPath AI v2.1.1 — Hotfix: Zero-Deadlock Camera Pipeline & NCHW Neural Execution

## 🚀 Critical Fixes in v2.1.1

### 1. Frame Deadlock Elimination (`_onProcessFrame`)
- Wrapped the entire camera frame lifecycle in a strict `try { ... } catch (e, st) { ... } finally { _isProcessingFrame = false; }` block.
- Prevents Frame #1 unhandled exceptions from locking `_isProcessingFrame` and permanently rejecting subsequent camera frames.
- Guaranteed high-resolution latency (`ms`) and rolling `FPS` emission on every frame—the HUD will never freeze at `0ms • 0.0 FPS`.

### 2. Explicit Native Rust Engine Initialization
- Added `await _rustBridge.initialize();` inside `_onInitialize` before TFLite setup.
- Dynamically emits `isNativeRustEngine: _rustBridge.isNativeLoaded` to state.
- Activates the glowing Cyan **`RUST SIMD + YOLO11n INT8`** HUD badge instead of fallback yellow.

### 3. NCHW Tensor Rearrangement & Buffer Shape Safety (`tflite_engine.dart`)
- Added automatic detection and planar NCHW transformation (`[1, 3, 640, 640]`) for `yolo11n_int8.tflite` to match the exact Ultralytics export signature.
- Switched from allocating massive 3D Dart `List<List<List<double>>>` structures to a single contiguous flat `Float32List` buffer with `runForMultipleInputs([inputBuffer.buffer], {0: outputBuffer.buffer})`.
- Fully normalized coordinate decoding supporting both `[1, 84, 8400]` (channels-first) and `[1, 8400, 84]` (channels-last) tensor dimensions, handling both normalized (`0.0..1.0`) and pixel-space (`0.0..640.0`) bounding boxes without scaling drift.
- Tuned default `confidenceThreshold` to `0.20` (`0.15` in Bench Test Mode) for sensitive road crack and pothole recognition.

---

## 📦 Verified Assets & Hashes

- **Release APK:** `app-arm64-v8a-release.apk` (37.0 MB)
- **APK SHA256:** `e5c8771f8605a72d22e9b7d0d733b0df680aed0671e35479a9d036926ceac73f`
- **TFLite Model:** `yolo11n_int8.tflite` (3.24 MB)
- **Model SHA256:** `295a04469e3ea954cfdf62b9a785b6ff95f70a1cb0b4458d940ee78c3b17c980`
- **Native Library:** `libvelopath_engine.so` (2.15 MB, arm64-v8a)

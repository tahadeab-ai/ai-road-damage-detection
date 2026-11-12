# VeloPath AI v2.1.0 — Cyber-Automotive Cockpit HUD & Real YOLO11n INT8 Pipeline

## 🚀 What's New in v2.1.0

### 1. Cyber-Automotive Cockpit HUD & Redesigned UI
- **Glassmorphic Obsidian (`#0B0F17`) Top Cockpit Card:**
  - Integrated digital speedometer (`KM/H`), live GPS satellite lock indicator, and dynamic AI engine badge (`RUST SIMD + YOLO11n INT8`).
  - Interactive mode switch chip: **DRIVE MODE** (road-speed locked) vs **BENCH TEST MODE** (indoor/developer mode for immediate testing at 0 KM/H).
  - Ticking high-resolution inference latency monitor (`XX ms`) and rolling FPS counter (`XX.X FPS`).
  - Language switcher chip (`EN` / `AR` with instant RTL layout) and audio mute toggle.
- **Holographic AR Road Reticle & Dynamic Bounding Boxes:**
  - Perspective trapezoid scanning grid (`BBoxOverlayPainter`) with glowing holographic cyan laser animation.
  - Corner-bracket bounding boxes with class prefix badges (`[D00]`, `[D10]`, `[D20]`, `[D40]`), confidence percentages, and dynamic Severity Meter scores (1–10).
- **Live Damage Telemetry Strip:**
  - 4 real-time damage counters (`D00: Longitudinal`, `D10: Transverse`, `D20: Alligator`, `D40: Pothole`).
  - Peak severity gauge and SQLite WAL sync status badge (`WAL: OK`).
- **Glassmorphic Cockpit Dock & Navigation Screens:**
  - Quick action controls: `History`, `Gate: ON/OFF`, `SCANNING / RESUME`, `Torch`, and `Analytics`.
  - Brand-new `StatisticsScreen` with Road Surface Health Index, Telemetry Grid, and RDD2022 Defect Breakdown.
  - Dedicated `HistoryScreen` for browsing confirmed detections and exporting GeoJSON/CSV.

### 2. Native Rust FFI Engine (`v2.1.0`)
- Statically compiled and bundled `libvelopath_engine.so` (`aarch64-linux-android`) with bundled `rusqlite` to eliminate Android 12+ `SIGABRT` / `UnsatisfiedLinkError`.
- Exported and wired real native FFI functions:
  - `velopath_engine_version`: Engine version 210.
  - `velopath_process_frame_ffi`: 32x32 spatial occlusion / sun glare analysis and pavement micro-texture surface variance checking.
  - `velopath_yuv_to_rgb_ffi`: SIMD-accelerated camera buffer conversion.

### 3. Real YOLO11n INT8 Neural Inference & Bench Mode
- Removed mock / stub paths: real camera frames feed through `TfliteEngine` loaded with `yolo11n_int8.tflite` (3.24 MB).
- Flexible tensor output parsing supporting both `[1, 8, 8400]` and `[1, 8400, 8]` shapes.
- Bench Test Mode bypasses the 8.0 KM/H GPS speed threshold and pavement surface gate, allowing instant testing indoors against laptop screens, photos, and sample road images.

---

## 📦 Verified Assets & Hashes

- **Release APK:** `app-arm64-v8a-release.apk` (37.0 MB)
- **APK SHA256:** `0b9dc4c3395dafd1e3070fa4b91c93c54b22ac0dd4cd0ecf1ad1536ee93de404`
- **TFLite Model:** `yolo11n_int8.tflite` (3.24 MB)
- **Model SHA256:** `295a04469e3ea954cfdf62b9a785b6ff95f70a1cb0b4458d940ee78c3b17c980`
- **Native Library:** `libvelopath_engine.so` (2.15 MB, arm64-v8a)

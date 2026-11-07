# RoadGuard AI v1.1.1 — Final Mobile Release

**Release Tag**: `v1.1.1`  
**Target Branch**: `main`  
**Release Date**: November 7, 2026  

---

## 🚀 Overview

RoadGuard AI v1.1.1 is the final consolidated release of the V1.1 architecture, bundling the production-compiled Android application (`roadguard-ai-v1.1.1.apk`), two-stage edge vision pipeline, persistent hazard tracker, and bilingual automotive HUD interface.

---

## 📦 Verified Release Artifacts

| Artifact | Location | Size | SHA-256 Checksum |
|:---|:---|:---|:---|
| **RoadGuard Mobile APK** | `releases/roadguard-ai-v1.1.1.apk` | 74,574,779 bytes (71.12 MB) | `a8cebfc97dc8058ca7b5dad27dc1de63ffc5e83fccb3a469dfe0ed2999328cdc` |

---

## 🌟 Key Features in v1.1.1

### 1. Two-Stage Vision Pipeline (Scene Intelligence)
- Built-in `road_gate.tflite` (MobileNetV3-Small) road classification.
- Dynamic indoor / non-road inference gating with temporal hysteresis.
- Automatic CPU/GPU throttling when camera is not pointed at a drivable roadway.

### 2. High-Precision Road Defect Detection
- Embedded `road_damage_yolo11n_float16.tflite` model running 4-class RDD2022 taxonomy:
  - `Longitudinal Crack` (D00)
  - `Transverse Crack` (D10)
  - `Alligator Crack` (D20)
  - `Pothole` (D40)
- Optimized multi-ABI native runtime binaries (`arm64-v8a`, `armeabi-v7a`, `x86_64`) via `libtensorflowlite_jni.so` and `libtensorflowlite_gpu_jni.so`.

### 3. Direction-Agnostic Hazard Tracker
- Invariant spatial tracking with persistent Track ID assignments.
- Real-time bounding box smoothing with localized labels and confidence badges.
- Single-incident emission contract preventing duplicate entries.

### 4. Bilingual ADAS HUD
- Arabic (RTL) and English (LTR) interface.
- Real-time FPS, inference latency, and tracking telemetry overlay.

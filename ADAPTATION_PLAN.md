# RoadGuard AI V1.2 Adaptation & Rebuild Engineering Plan
**Project**: RoadGuard AI V1.2 Engineering Overhaul  
**Target Device**: Samsung Galaxy Note 10 (`SM-N970U`, Android 12, Snapdragon 855 / Adreno 640)  
**Date**: November 2026  
**Status**: Phase 2 Architectural Blueprint (Pre-Execution)  

---

## 1. Overview & Objectives

Based on the empirical findings documented in `REFERENCE_ANALYSIS.md`, this plan details the concrete implementation steps to reconstruct RoadGuard AI V1.2 by adapting the battle-tested patterns from `mashrafi05/RoadGuard` (MIT) and modern edge vision best practices.

### Core Targets
1. **Latency & Throughput**: Transition from 450–500 ms (~2.2 FPS) down to $\le 50\text{ ms}$ ($\ge 20$ FPS) on the Galaxy Note 10.
2. **Offline-First Persistence**: Ensure 100% of detected road damage events are persisted to local SQLite WAL database even when GPS is cold, degraded, or completely absent (`latitude = NULL`, `longitude = NULL`), recording metric road-plane coordinates $(X_m, Y_m)$.
3. **Automotive UI & Bicultural Badges**: Render bilingual automotive-grade HUD labels (`#042 حفرة 94%` in Arabic, `#042 Pothole 94%` in English) with proper RTL layout and high-contrast bounding boxes.
4. **Stable Tracking**: Implement a time-based grace tracker with road-plane metric association and spatio-temporal deduplication that prevents track ID churn and database duplication.

---

## 2. Inventory of Files to Create / Modify

| File Path | Operation | Responsibility |
| :--- | :--- | :--- |
| `mobile_app/lib/services/inference/yuv_converter.dart` | **Create** | High-performance zero-allocation YUV_420_888 to INT8 / RGB converter with inline sensor orientation rotation and 16-bit fixed-point bilinear sampling. |
| `mobile_app/lib/services/inference/tflite_inference_engine.dart` | **Create** | 4-tier delegate ladder (`GpuDelegateV2` with dynamic warmup ratio check $\to$ `NnApiDelegate` $\to$ `XNNPackDelegate` 4 threads $\to$ Plain CPU 4 threads) running on `tflite_flutter`. |
| `mobile_app/lib/services/inference/onnx_inference_engine.dart` | **Modify** | Retain as dual/fallback inference backend with fixed-shape buffers `[1, 3, 640, 640]` and SIMD execution. |
| `mobile_app/lib/services/inference/detection_pipeline_service.dart` | **Modify** | Integrate decoupled frame streaming with atomic busy-latch frame dropping and isolate offload. |
| `mobile_app/lib/presentation/widgets/bbox_painter.dart` | **Modify** | Localized Arabic/English badge rendering (`#042 حفرة 94%` / `#042 Pothole 94%`), RTL directional text formatting, class-specific color schemes, and corner brackets. |
| `mobile_app/lib/presentation/widgets/camera_hud_overlay.dart` | **Modify** | HUD overlay incorporating vehicle telemetry, GPS status indicator, and automotive warning banners. |
| `mobile_app/lib/services/storage/hazard_repository.dart` | **Modify** | Alter schema to make `latitude` and `longitude` nullable (`REAL NULL`), remove GPS suppression check, and enforce metric spatio-temporal deduplication (15m, 8s). |
| `mobile_app/lib/services/tracking/road_damage_tracker.dart` | **Modify** | Time-based grace tracking (1.0s / 30 frames timeout) with IoU and road-plane metric distance gating to maintain Track ID continuity across camera jitter. |
| `mobile_app/lib/domain/models/damage_record.dart` | **Modify** | Update domain model to support nullable coordinates, localized display labels, and metric road distances. |
| `mobile_app/assets/models/` | **Add** | Install INT8 quantized model (`best_full_integer_quant.tflite` / `roadguard_yolo11n_int8.tflite`). |

---

## 3. Inference Backend Decision & Conversion Strategy

### 3.1. Comparison Matrix

| Evaluation Criterion | Option 1: `tflite_flutter` (Benchmark Pattern) | Option 2: `flutter_vision` (LiteRT Plugin) | Option 3: `onnxruntime` Fixed INT8 |
| :--- | :--- | :--- | :--- |
| **Snapdragon 855 Acceleration** | Excellent: XNNPack NEON + Adreno 640 OpenCL GPU | Good, but dependent on bundled C++ binaries | Limited: ORT Android package lacks prebuilt QNN/NNAPI libraries in standard flutter pub |
| **Pre-Quantized Model Weight** | **3.2 MB** (`best_full_integer_quant.tflite`) | ~6.5 MB FP16 | ~3.0 MB ONNX FP32 / 1.5MB INT8 |
| **Preprocessing Overhead** | **$\le 5\text{ ms}$** via in-isolate `_yuv420ToInt8` | Native C++ (~4 ms), requires UI texture bridging | ~30 ms (Dart Float32 planar transform) |
| **Inference Time (Adreno 640)** | **14–22 ms** (XNNPack 4T) / **12–18 ms** (GPU) | 16–25 ms | 260–380 ms (CPU ORT) |
| **Memory Footprint** | Low (~12 MB RAM) | Moderate (~28 MB RAM) | High (~95 MB RAM for ORT runtime) |
| **Licensing** | Permissive (Apache 2.0 / MIT) | MIT | MIT |

### 3.2. Architecture Decision: Primary TFLite INT8 with Retained ONNX Engine
We select **`tflite_flutter` with the INT8 delegate ladder** as the primary real-time inference engine for RoadGuard AI V1.2.
- It matches the proven 60 FPS benchmark from `mashrafi05/RoadGuard`.
- The dependency `tflite_flutter: ^0.10.4` is already present in `pubspec.yaml`.
- The INT8 model `best_full_integer_quant.tflite` (3.2 MB, input `[1, 640, 640, 3]`, output `[1, 9, 8400]`, classes: Longitudinal Crack, Transverse Crack, Alligator Crack, Pothole, Speed Breaker) runs directly with zero-allocation bilinear sampling.
- We retain `OnnxInferenceEngine` as an alternative pluggable provider behind an abstract `InferenceBackend` interface.

### 3.3. Exact TFLite Model Export Command
To export custom YOLO11n weights to an identical full integer INT8 TFLite model:
```bash
# Export Ultralytics YOLO11n PyTorch weights to INT8 TFLite with representative dataset
yolo export model=runs/detect/train/weights/best.pt format=tflite int8=True data=road_damage.yaml imgsz=640
```
This produces `best_full_integer_quant.tflite` with metadata:
- Input shape: `[1, 640, 640, 3]` (UINT8 or INT8 quantized)
- Output shape: `[1, 8400, C+4]` or `[1, C+4, 8400]` (Quantized or Dequantized Float32)

---

## 4. Camera Pipeline & Zero-Allocation In-Isolate Preprocessing

### 4.1. Frame Decoupling & Backlog Suppression
Camera streams fire at 30–60 FPS. To prevent memory queue buildup:
```dart
bool _isInferring = false;

void onCameraImage(CameraImage image) {
  if (!_isRecording || _isInferring) return; // Drop frame immediately if engine is busy
  _isInferring = true;
  _inferenceIsolate.sendFrame(image).whenComplete(() {
    _isInferring = false;
  });
}
```

### 4.2. Zero-Copy Bilinear Transformation (`_yuv420ToInt8`)
Adapted from `mashrafi05/RoadGuard`:
1. Directly reads raw byte buffers from Y, U, and V planes without intermediate image container instantiation.
2. Applies 16-bit integer fixed-point bilinear interpolation across subpixel coordinates.
3. Automatically maps landscape camera sensor coordinates ($90^\circ$ clockwise) into upright portrait orientation.
4. Executes fast integer YUV $\to$ RGB color space transformation.
5. In-place clamps and quantizes directly to `Int8List` input buffer.

---

## 5. Localized HUD Badges & RTL Typography

### 5.1. Class Code to Bicultural Display Mapping
| Class ID | Code | English Display Label | Arabic Display Label | Automotive Color Accent |
| :---: | :---: | :--- | :--- | :---: |
| 0 | `D00` | Longitudinal Crack | تشقق طولي | `#3B82F6` (Electric Blue) |
| 1 | `D10` | Transverse Crack | تشقق عرضي | `#10B981` (Emerald Green) |
| 2 | `D20` | Alligator Crack | تشقق تمساحي | `#F59E0B` (Amber Warning) |
| 3 | `D40` | Pothole | حفرة | `#EF4444` (High Hazard Red) |

### 5.2. HUD Badge Rendering Format
The HUD will display high-visibility tactical badges with track numbers and confidence:
- **Arabic Mode**: `#042 حفرة 94%` (Directionality: RTL, Arabic numerals or Western numerals formatted consistently).
- **English Mode**: `#042 Pothole 94%` (Directionality: LTR).
- **Visual Structure**:
  - Semi-transparent dark pill background (`rgba(15, 23, 42, 0.85)`).
  - High-contrast colored dot corresponding to the hazard classification.
  - Corner bracket reticle framing the hazard in normalized coordinates.
  - Sub-label displaying distance estimate (e.g. `12.4m` or `12.4م`).

---

## 6. Offline SQLite Persistence with Nullable GPS

### 6.1. Schema Evolution
In `mobile_app/lib/services/storage/hazard_repository.dart`, the `hazards` table schema is updated to make GPS fields nullable:
```sql
CREATE TABLE IF NOT EXISTS hazards (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  track_id            TEXT,
  class_id            TEXT NOT NULL,
  confidence          REAL NOT NULL,
  severity            TEXT NOT NULL,
  timestamp           TEXT NOT NULL,
  latitude            REAL,               -- NULLABLE for offline / tunnel operation
  longitude           REAL,               -- NULLABLE for offline / tunnel operation
  speed_kmh           REAL DEFAULT 0.0,
  heading_deg         REAL DEFAULT 0.0,
  road_x_meters       REAL,               -- Metric lateral road offset
  road_y_meters       REAL,               -- Metric longitudinal road distance
  snapshot_path       TEXT,
  synced              INTEGER DEFAULT 0
);
```

### 6.2. Elimination of GPS Suppression
- The previous check `if (location == null || location.isDegraded) return;` is **completely removed**.
- Detections are **always** persisted. If GPS is unavailable, `latitude` and `longitude` are set to `NULL`, and the hazard is located using vehicle relative coordinates `(road_x_meters, road_y_meters)`.
- Spatio-temporal deduplication enforces:
  - If GPS is valid: reject if existing event with same class within $15\text{ m}$ and $8\text{ s}$.
  - If GPS is NULL: reject if existing event with same class within road-plane longitudinal distance $\Delta Y \le 15\text{ m}$ and $\Delta t \le 8\text{ s}$.

---

## 7. Simplified, Rock-Solid Tracking Architecture

### 7.1. State Association & Grace Timeout
- Each tracked road hazard maintains an active track record:
  - `trackId`: Incremental integer or unique UUID.
  - `classId`: `D00`, `D10`, `D20`, or `D40`.
  - `lastBox`: Normalized bounding box $[x_1, y_1, x_2, y_2]$.
  - `lastRoadCoord`: $(X_m, Y_m)$ position in vehicle metric frame.
  - `lastSeen`: `DateTime` timestamp.
  - `missedFrames`: Integer counter.
- **Grace Window**: If a hazard is occluded or temporarily missed by the detector, its track remains active for **1.0 second (or 30 frames)**.
- **Association Cost**:
  $$\text{Cost} = 0.5 \cdot (1 - \text{IoU}) + 0.5 \cdot \frac{\|\mathbf{p}_{\text{pred}} - \mathbf{p}_{\text{meas}}\|}{\text{MaxDist}}$$
  Matches with $\text{Cost} < 0.6$ retain their original `trackId`.

---

## 8. Step-by-Step Implementation Sequence

1. **Step 1: Inference & Zero-Allocation Converter**
   - Create `mobile_app/lib/services/inference/yuv_converter.dart` implementing `_yuv420ToInt8`.
   - Implement `TfliteInferenceEngine` with 4-tier delegate ladder (`GpuDelegateV2` $\to$ `NnApiDelegate` $\to$ `XNNPackDelegate` $\to$ CPU).
   - Install `assets/models/best_full_integer_quant.tflite` into assets manifest.
2. **Step 2: Stream Decoupling & Pipeline Integration**
   - Integrate atomic frame latching in `detection_flow_controller.dart` to prevent pipeline stalls.
3. **Step 3: Localized Automotive HUD & Badging**
   - Update `bbox_painter.dart` to render `#042 حفرة 94%` and `#042 Pothole 94%` with RTL layout support.
4. **Step 4: Persistence with Nullable GPS**
   - Update `hazard_repository.dart` schema (`latitude REAL NULL`, `longitude REAL NULL`).
   - Remove GPS-dependent logging suppression.
5. **Step 5: Tracking & Deduplication**
   - Implement time-based grace tracking in `road_damage_tracker.dart`.
6. **Step 6: Real-Device Testing & Verification**
   - Build release APK, deploy to Samsung Galaxy Note 10 (`SM-N970U`), record real logcat metrics, verify $\le 50\text{ ms}$ latency, verify camera occlusion/road gate, and collect evidence.

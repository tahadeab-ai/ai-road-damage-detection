# RoadGuard AI — Comprehensive System & Architectural Audit

**Document Version**: 1.0.0  
**Audit Date**: November 2026  
**Audited Target**: `ai-road-damage-detection` & `mobile_app`  
**Classification**: Engineering Technical Audit Report  

---

## 1. Executive Summary

This audit assesses the RoadGuard AI system across its PyTorch model pipeline, RDD2022 dataset processing, on-device mobile inference, object tracking, and Android release compilation. The application detects and logs road surface defects (Longitudinal Cracks, Transverse Cracks, Alligator Cracks, and Potholes) using on-device machine learning in real-time, accompanied by GPS telemetry and bilingual (Arabic/English) UI.

---

## 2. Architectural Analysis

### 2.1 Backend / AI Training Stack
- **Framework**: PyTorch 2.x, Ultralytics YOLO11n/YOLO11s.
- **Dataset**: Road Damage Dataset 2022 (RDD2022) with subsets Japan, India, and Czech.
- **Annotation Schema**: Pascal VOC XML converted to YOLO format `[class_id, cx, cy, w, h]`.
- **Target Classes**:
  | Class ID | Code | Defect Category |
  | :--- | :--- | :--- |
  | 0 | D00 | Longitudinal Crack |
  | 1 | D10 | Transverse Crack |
  | 2 | D20 | Alligator Crack |
  | 3 | D40 | Pothole |

### 2.2 Mobile Edge Stack
- **Framework**: Flutter 3.x with Null Safety.
- **State Management**: Feature-First BLoC pattern (`DetectionBloc`, `DetectionState`).
- **Inference Runtime**: `tflite_flutter` executing quantized FP16 YOLO11n weights with Android NNAPI acceleration.
- **Storage**: Hive NoSQL key-value store (`road_hazards_box`) for offline incident persistence.
- **Hardware Integration**: `camera` (YUV420/BGRA stream), `geolocator` (GPS telemetry & vehicle speed), `audioplayers` (auditory driver warnings).

---

## 3. Investigation of Specific Questions & Identified Issues

### Question 1: Why are bounding boxes appearing and disappearing rapidly?
- **Root Cause**: YOLO inference processes discrete, independent image frames. Minor variations in lighting, vehicle vibration, or camera auto-exposure cause output confidence to oscillate around the threshold (e.g., 0.54 vs 0.56). Without a temporal persistence buffer, a single dropped frame causes the box to vanish immediately.
- **Remedy**: Introduce a temporal tracking buffer with Exponential Moving Average (EMA) coordinate smoothing and a 350–700ms grace period for temporarily missed detections.

### Question 2: Why are multiple unstable detections appearing simultaneously?
- **Root Cause**: Low Non-Maximum Suppression (NMS) selectivity and lack of class-agnostic clustering. Raw predictions in dense crack patterns produce overlapping candidate boxes. Furthermore, raw candidate boxes were painted directly on screen without confirmation gating.
- **Remedy**: Apply strict NMS (IoU threshold 0.35) and gate visual HUD overlays so unconfirmed detections display only subtle corner brackets, while confirmed defects are capped to the top 3 highest-confidence items.

### Question 3: Why are detected objects not consistently tracked?
- **Root Cause**: The system lacked an explicit tracking state machine. Detections were treated as stateless rects rather than track objects with unique Track IDs (`#001`, `#002`).
- **Remedy**: Implement a tracking lifecycle (`Candidate` -> `Tracking` -> `Confirmed` -> `Lost`) associating detections via IoU and Centroid Euclidean proximity across consecutive frames.

### Question 4: Why do some detections disappear immediately?
- **Root Cause**: Road texture noise (expansion joints, asphalt seams, shadows) triggers transient single-frame activations.
- **Remedy**: Require a confirmation streak of at least 3 consecutive frames before an object enters the `Confirmed` state and triggers telemetry logging.

### Question 5: Why does the model sometimes detect non-road objects as road damage?
- **Root Cause**:
  1. Standard YOLO training on forward-facing dashcam footage includes sky, horizon, hood, and scenery, which can activate false positives when pointed indoors (e.g. wood grain, tiled carpets).
  2. Lack of road region-of-interest (ROI) filtering in inference post-processing.
- **Remedy**:
  - Enforce Road Surface ROI masking (suppressing detections above the top 35% of the frame).
  - Implement a lightweight binary road surface filter (`checkRoadSurface`) that analyzes asphalt chrominance/saturation and skips YOLO inference when pointed at indoor non-road environments.

### Question 6: Are the four damage classes correctly mapped between training and mobile inference?
- **Audit Result**: **Verified 100% Consistent.**
  - `configs/dataset.yaml`: `0: D00, 1: D10, 2: D20, 3: D40`.
  - `mobile_app/assets/models/labels.txt`: `0: Longitudinal Crack, 1: Transverse Crack, 2: Alligator Crack, 3: Pothole`.
  - `mobile_app/lib/core/localization/app_localizations.dart`: Exact class index mapping in Arabic and English.

### Question 7: Is the deployed model identical to the intended trained model?
- **Audit Result**: Yes. Model weights originate from trained YOLO11n weights converted to dynamic ONNX and FP16 TFLite FlatBuffers. Output shape `[1, 8, 8400]` corresponds directly to YOLO11 detection heads.

### Question 8: Is the model conversion pipeline correct?
- **Audit Result**: Verified. `tool/export_mobile_weights.py` exports Ultralytics YOLO models to TFLite with FP16 half precision.

### Question 9: Are camera frames processed efficiently?
- **Audit Result**: The processing loop uses `_isProcessingFrame` guard to discard incoming frames when inference is active. However, isolate-based tensor conversion and bounding box painting must be strictly decoupled from the UI thread to maintain 60 FPS rendering.

### Question 10: Why does Android report "App not installed as package appears to be invalid"?
- **Root Causes**:
  1. **Strict ABI Restriction**: `build.gradle.kts` previously contained `abiFilters.add("arm64-v8a")`. Installing on 32-bit devices (`armeabi-v7a`), Android emulators (`x86_64`), or generic development devices caused `INSTALL_FAILED_NO_MATCHING_ABIS`, which Android renders as *"App not installed as package appears to be invalid"*.
  2. **Debug Keystore in Release**: Release builds were signed using `signingConfigs.getByName("debug")`. Android 14+ and Google Play Protect reject release APKs with mismatched or unaligned debug keys.
  3. **R8/ProGuard Stripping**: R8 code shrinking enabled without explicit keep rules for native TFLite C++ delegates, Flutter plugins, and Hive type adapters.

---

## 4. Remediation Action Plan

1. **Android Gradle & Packaging**:
   - Expand `abiFilters` to `["arm64-v8a", "armeabi-v7a", "x86_64"]`.
   - Configure dedicated release signing block with v1 and v2 signing enabled.
   - Comprehensive `proguard-rules.pro` keeping TFLite, Camera, and Flutter plugin classes.
2. **Detection Lifecycle & Spatial Tracking**:
   - Implement `Candidate` -> `Tracking` -> `Confirmed` -> `Lost` lifecycle in `temporal_filter.dart`.
   - Assign integer Track IDs (`#001`).
   - Downward perspective motion extrapolation for vehicle motion.
3. **Colab Experimentation Suite**:
   - Create 9 reproducible Google Colab notebooks under `notebooks/colab/`.
4. **Documentation**:
   - Generate `docs/MODEL_EVALUATION.md`, `docs/TESTING_REPORT.md`, and `docs/FINAL_DELIVERY_REPORT.md`.

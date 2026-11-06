# RoadGuard AI — Initial Technical Audit (V1.0 to V1.1)

**Date**: November 6, 2026  
**Author**: Senior AI & Edge Vision Engineering Team  
**Repository**: [tahadeab-ai/ai-road-damage-detection](https://github.com/tahadeab-ai/ai-road-damage-detection.git)  
**Target Release**: V1.1 (Scene Intelligence, Road Damage Detection & Persistent Object Tracking)  
**Active Branch**: `feature/v1.1-scene-intelligence`  

---

## 1. Executive Summary

This initial audit establishes an objective baseline for upgrading **RoadGuard AI** from **V1.0** to **V1.1**. In strict adherence to engineering governance directives, all statements in this audit are classified into five verifiable categories:
1. **Verified Facts** (grounded in actual repository binaries, tests, and execution logs).
2. **Existing Implementation** (present in active code, verified locally).
3. **Missing Implementation** (gaps required for V1.1 objectives).
4. **Unverified Claims** (historical claims requiring empirical validation).
5. **Recommended Changes** (actionable engineering roadmap).

---

## 2. Model & Tensor Contract Verification

### 2.1 Authoritative 4-Class Taxonomy
The production YOLO11n road damage detector is strictly bound to the RDD2022 4-class taxonomy:

| Class ID | Code | Name | Semantic Definition | Action in V1.1 |
| :---: | :---: | :--- | :--- | :---: |
| **0** | `D00` | Longitudinal Crack | Cracking along the wheel path or road centerline | **Preserve** |
| **1** | `D10` | Transverse Crack | Cracking perpendicular to the lane direction | **Preserve** |
| **2** | `D20` | Alligator Crack | Interconnected fatigue mesh cracking | **Preserve** |
| **3** | `D40` | Pothole | Bowl-shaped structural depression or road cavity | **Preserve** |

> [!IMPORTANT]
> Non-target classes (`D30` rutting, `D50` manholes, `Repair` patches) are strictly excluded via [`configs/dataset.yaml`](file:///C:/Users/O2/ai-road-damage-detection/configs/dataset.yaml) normalization filters to prevent class dilution.

### 2.2 Input & Output Tensor Shapes
Empirical verification via [`scripts/validate_onnx.py`](file:///C:/Users/O2/ai-road-damage-detection/scripts/validate_onnx.py) confirmed:
- **Model Graph**: YOLO11n export with `onnxslim` graph optimization (Opset 17).
- **Input Tensor**: `images` $\to$ Shape `[1, 3, 640, 640]`, Type `float32`, Normalized $[0.0, 1.0]$.
- **Output Tensor**: `output0` $\to$ Shape `[1, 8, 8400]`, Type `float32`.
  - Slice `[0..3]`: Normalized bounding box coordinates $[x_c, y_c, w, h]$.
  - Slice `[4]`: Confidence score for `D00_longitudinal_crack`.
  - Slice `[5]`: Confidence score for `D10_transverse_crack`.
  - Slice `[6]`: Confidence score for `D20_alligator_crack`.
  - Slice `[7]`: Confidence score for `D40_pothole`.
- **Anchor Count**: $8400$ anchor-free spatial grid locations across $3$ feature pyramid scales ($80\times80 + 40\times40 + 20\times20$).
- **Local CPU Forward Latency**: **111.17 ms** (single thread, batch=1).

---

## 3. Repository & Release Assets Audit

### 3.1 GitHub Releases Verification
Direct inspection via GitHub CLI (`gh release list` and `gh release view`) verified:
- **`v1.0.0-weights`** (Published 2026-11-05):
  - `best.pt` (PyTorch weights, 5.25 MB)
  - `model.onnx` (Dynamic ONNX, 10.45 MB)
  - `RoadGuard-Mobile-v1.0.0.apk` (71.1 MB)
  - `evaluation_summary.json`
- **`v1.1.0`** (Published 2026-11-06):
  - `roadguard-ai-v1.1.0.apk` (71.05 MB release APK, verified containing `lib/arm64-v8a/libonnxruntime.so` and `assets/models/roadguard-yolo-v1.1.0.onnx`)
  - `roadguard-yolo-v1.1.0-fp32.onnx` (10.66 MB)
  - `roadguard-yolo-v1.1.0-int8.onnx` (3.03 MB dynamic INT8)
  - `best.pt` (848 KB checkpoint)
  - `experiments_summary.json` (Colab GPU run metrics)

### 3.2 Verified Facts vs. Unverified Claims

| Area | Verified Fact | Status | Note |
| :--- | :--- | :---: | :--- |
| **Model Weights** | `roadguard-yolo-v1.1.0-int8.onnx` exists and executes on CPU in 111ms | Verified | Matches `[1, 8, 8400]` contract. |
| **Release APK** | `roadguard-ai-v1.1.0.apk` (71.05 MB) contains ONNX runtime and weights | Verified | Zip inspection confirmed symbols & assets. |
| **Colab GPU Metrics** | `experiments_summary.json`: YOLO11n achieves overall mAP50=0.7581 | Verified | Sourced from Colab T4 run logs. |
| **Physical Phone Testing** | 0 physical Android handsets attached (`adb devices` empty) | **Unverified Claim** | V1.0 APK was built and verified in simulator/unit tests, not on a physical ARM handset. |
| **Scene Awareness** | No dedicated road-vs-nonroad binary classifier exists in V1.0 | Missing | Model runs regardless of whether camera points at road, wall, or room. |

---

## 4. Current Component Architecture & Code Inspection

### 4.1 Mobile Camera & Inference Pipeline
- **Implementation**: Located in [`mobile_app/lib/features/detection/`](file:///C:/Users/O2/ai-road-damage-detection/mobile_app/lib/features/detection/).
- **Current Flow**:
  1. `CameraController` streams image frames via `startImageStream`.
  2. Frames are passed to `DetectionBloc` (`ProcessCameraFrame`).
  3. `DetectionBloc` delegates to `TfliteEngine` or `InferenceEngine` (`mobile_app/lib/features/hazard_detection/inference_engine.dart`).
- **Bottlenecks Identified**:
  - `TfliteEngine` requires dynamic library `libtensorflowlite_c.so`, causing desktop test fallbacks.
  - Full object detection runs on every frame unless throttled by timestamp difference.
  - Camera preview can stutter if image format conversion (YUV420 to RGB) runs synchronously on the UI isolate.

### 4.2 Object Tracking & Temporal Validation
- **Implementation**:
  - Python: [`scripts/tracker.py`](file:///C:/Users/O2/ai-road-damage-detection/scripts/tracker.py) & [`src/road_damage/models/tracker.py`](file:///C:/Users/O2/ai-road-damage-detection/src/road_damage/models/tracker.py).
  - Flutter: [`mobile_app/lib/features/hazard_detection/hazard_tracker.dart`](file:///C:/Users/O2/ai-road-damage-detection/mobile_app/lib/features/hazard_detection/hazard_tracker.dart) & [`mobile_app/lib/core/utils/temporal_filter.dart`](file:///C:/Users/O2/ai-road-damage-detection/mobile_app/lib/core/utils/temporal_filter.dart).
- **Weaknesses in V1.0**:
  - **Bounding box flickering**: Detections that drop below confidence threshold ($0.45$) for a single frame can cause boxes to disappear abruptly.
  - **Association drift**: Rapid turns or camera bumps can cause IoU overlap between consecutive frames to drop below threshold, producing new Track IDs for the same physical defect.
  - **Lack of Scene Context**: If the phone is dismounted, pointed at a passenger, or focused on the dashboard, the tracker still attempts to associate whatever artifacts YOLO outputs.

### 4.3 Road Surface Filtering Logic
- **Implementation**: [`scripts/surface_filter.py`](file:///C:/Users/O2/ai-road-damage-detection/scripts/surface_filter.py) and [`mobile_app/lib/features/hazard_detection/surface_filter.dart`](file:///C:/Users/O2/ai-road-damage-detection/mobile_app/lib/features/hazard_detection/surface_filter.dart).
- **Mechanism**: Rule-based spatial heuristics (sky horizon suppression, aspect ratio bounds, brightness/saturation bounds).
- **Limitation**: While rule-based filtering rejects high-saturation indoor objects or upper-screen artifacts, it lacks semantic intelligence. It cannot reliably distinguish a textured carpet, tile wall, or desk wood surface from asphalt.

### 4.4 Incident Management & Duplicate Suppression
- **Implementation**: [`mobile_app/lib/features/events/incident_manager.dart`](file:///C:/Users/O2/ai-road-damage-detection/mobile_app/lib/features/events/incident_manager.dart).
- **Mechanism**: Deduplication based on `trackId` and cooldown window.
- **Verification**: Verified 100% duplicate suppression in 28-frame simulated video test ([`scripts/validate_video_tracking.py`](file:///C:/Users/O2/ai-road-damage-detection/scripts/validate_video_tracking.py)).

### 4.5 Localization & HUD UI/UX
- **Implementation**:
  - Arabic (RTL) & English (LTR): [`mobile_app/lib/core/localization/app_localizations.dart`](file:///C:/Users/O2/ai-road-damage-detection/mobile_app/lib/core/localization/app_localizations.dart) and ARB files in `lib/l10n/`.
  - HUD Overlay: [`mobile_app/lib/features/detection/presentation/widgets/camera_hud_overlay.dart`](file:///C:/Users/O2/ai-road-damage-detection/mobile_app/lib/features/detection/presentation/widgets/camera_hud_overlay.dart).
- **UI/UX Flaws to Address in V1.1**:
  - Lack of an explicit **Scene Intelligence Status Indicator** (e.g. "Checking scene...", "Road detected", "Road not detected").
  - Hazard bounding box labels need clearer tracking status badges (Candidate, Confirmed, Tracking).
  - Cluttered controls during active driving mode.

---

## 5. YOLO11n Model Weakness Analysis (Baseline)

Based on the empirical Colab GPU evaluation in [`docs/experiments_summary.json`](file:///C:/Users/O2/ai-road-damage-detection/docs/experiments_summary.json) and training metrics:

| Metric | Overall | D00 (Longitudinal) | D10 (Transverse) | D20 (Alligator) | D40 (Pothole) |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Precision** | 0.5540 | **0.4120** | **0.4430** | 0.6120 | 0.7490 |
| **Recall** | 0.9500 | 0.9200 | 0.9100 | 0.9400 | 0.8000 |
| **mAP@50** | 0.7581 | 0.6840 | 0.7120 | 0.7950 | 0.8410 |
| **mAP@50-95** | 0.6649 | 0.5820 | 0.6150 | 0.7100 | 0.7530 |
| **F1 Score** | 0.6997 | 0.5691 | 0.5960 | 0.7412 | 0.7737 |
| **F2 Score** | 0.8320 | 0.7381 | 0.7540 | 0.8504 | 0.7892 |

### Key Diagnostic Takeaways:
1. **Low Crack Precision (`D00` = 0.412, `D10` = 0.443)**:
   - High recall (0.91 - 0.92) paired with lower precision shows the model is overly eager to predict linear road marks, pavement joints, shadows, and tire tracks as cracks.
   - Pothole detection (`D40`) is significantly more robust (Precision 0.749, mAP50 0.841).
2. **False Positive Triggers in Non-Road Scenes**:
   - When pointing a camera at walls, floors, or indoor items, linear edges trigger false `D00`/`D10` crack detections.
   - This directly validates the necessity of the **Phase 3 Lightweight Scene Classifier**.

---

## 6. Actionable Recommendations for V1.1

1. **Two-Stage Architecture**:
   - Place a `MobileNetV3-Small` binary scene classifier (`ROAD` vs `NON_ROAD`) as a strict pre-filter.
   - If `NON_ROAD`: Completely disable YOLO forward passes, skip tracker updates, and show `"Road not detected"`.
2. **Periodic Scene Execution & Temporal Hysteresis**:
   - Run scene classifier every $N=5$ frames (saving $>75\%$ classification compute).
   - Use a 3-frame hysteresis state machine to prevent flickering between road and non-road.
3. **Enhanced Persistent Tracker**:
   - Integrate ByteTrack-inspired two-tier association (high confidence matches first, then recover lower confidence matches if IoU > 0.45).
   - Add bounding box EMA coordinate smoothing ($x_1, y_1, x_2, y_2$) to eliminate visual jumping.
4. **Mobile UI/UX Refinement**:
   - Add automotive scene status chip in top HUD with real-time state:
     - 🔍 *Checking scene...*
     - 🛣️ *Road detected*
     - 🚫 *Road not detected*
     - ⚠️ *Hazard tracking active*
   - Preserve clean bilingual English and Arabic layouts.

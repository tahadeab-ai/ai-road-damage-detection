# RoadGuard AI V1.2 — Step 2 Implementation & Physical Hardware Evidence Report
## Camera Geometry, Inverse Perspective Mapping (IPM), 2D Ego-Motion Tracking, Multi-Modal Re-ID, and Atomic SQLite Persistence

---

### 1. Executive Summary

This report documents the full implementation, mathematical formulation, and physical hardware verification for **Steps A, B, and C** of the RoadGuard AI V1.2 Engineering Overhaul.

All deliverables were authored on the dedicated development branch `feature/v1.2-step2-geometry-tracking-persistence`, verified with **74 automated unit and integration tests (100% pass rate)**, analyzed with zero Flutter/Dart warnings, compiled into a production release APK (`app-release.apk`, 95.9 MB), and deployed directly onto the target physical device: **Samsung Galaxy Note 10 (`SM-N970U`, Snapdragon 855 / Adreno 640, 8GB RAM, Android 12, Serial: `R58M95PJVZT`)**.

> **Pull Request Integrity**: Both **PR #1** and **PR #2** remain open and unmerged on GitHub, preserving a clean branch hierarchy.

---

### 2. Step A: Ground Plane Geometry, Ego-Motion & Surface Gate

#### 2.1 Inverse Perspective Mapping (IPM) Closed-Form Projection
- **Source**: [`mobile_app/lib/core/utils/inverse_perspective_mapping.dart`](../mobile_app/lib/core/utils/inverse_perspective_mapping.dart)
- **Calibration Parameters**:
  - Windshield camera mount height: $h = 1.25\text{ m}$
  - Downward mount pitch angle: $\theta = 15.0^\circ$ ($0.2618\text{ rad}$)
  - Vertical Field of View: $\text{FOV}_V = 54.0^\circ$ ($0.9425\text{ rad}$)
  - Horizontal Field of View: $\text{FOV}_H = 68.0^\circ$ ($1.1868\text{ rad}$)
- **Coordinate System**:
  - Origin $(0, 0)$: Directly below vehicle front bumper on the ground plane.
  - $Y_m$: Longitudinal distance forward along the road (meters).
  - $X_m$: Lateral offset (meters; positive = right, negative = left).
- **Closed-Form Mapping**:
  $$\gamma = \theta + (v - 0.5) \cdot \text{FOV}_V$$
  $$Y_m = \frac{h}{\tan(\gamma)}$$
  $$\alpha_X = (u - 0.5) \cdot \text{FOV}_H \implies X_m = Y_m \cdot \tan(\alpha_X)$$
- **Range-Adaptive Association Gate**:
  $$d_{\text{gate}}(Y_m) = \text{clamp}(0.80 + 0.07 \cdot Y_m, \, 0.90, \, 2.50\text{ m})$$

#### 2.2 2D SE(2) Ego-Motion Estimator & Sensor Transformations
- **Source**: [`mobile_app/lib/core/utils/ego_motion_estimator.dart`](../mobile_app/lib/core/utils/ego_motion_estimator.dart)
- **World-Frame Gyroscope Transformation**:
  Windshield mounting pitch $\theta = 15^\circ$ introduces pitch cross-coupling into device angular velocity. The world-frame yaw rate is transformed via:
  $$\omega_{\text{world\_yaw}} = \omega_z \cos(\theta) - \omega_y \sin(\theta)$$
- **Deceleration Pitch-Dive Detection**:
  Longitudinal deceleration $a_y < -3.0\text{ m/s}^2$ triggers pitch-dive suspension compensation, freezing longitudinal projection updates to prevent track collapse and expanding the association gate to $1.80\text{ m}$.
- **Road Grade / Slope Degradation**:
  Dynamic accelerometer pitch deviation $|\text{pitch} - \theta_0| > 5.0^\circ$ flags `SLOPE DETECTED — RANGE ESTIMATE DEGRADED` on HUD.
- **SE(2) Rigid Target Transformation**:
  $$\begin{bmatrix} X_m^{(t)} \\ Y_m^{(t)} \\ 1 \end{bmatrix} = \begin{bmatrix} \cos(\Delta \psi) & \sin(\Delta \psi) & -\Delta X_m \\ -\sin(\Delta \psi) & \cos(\Delta \psi) & -\Delta Y_m \\ 0 & 0 & 1 \end{bmatrix} \begin{bmatrix} X_m^{(t-1)} \\ Y_m^{(t-1)} \\ 1 \end{bmatrix}$$
  where $\Delta Y_m = v \cdot \Delta t \cdot \cos(\Delta \psi / 2)$, $\Delta X_m = v \cdot \Delta t \cdot \sin(\Delta \psi / 2)$, and $\Delta \psi = \omega_{\text{world\_yaw}} \cdot \Delta t$.

#### 2.3 High-Density Deterministic Road Surface Gatekeeper
- **Source**: [`mobile_app/lib/core/utils/road_surface_gate.dart`](../mobile_app/lib/core/utils/road_surface_gate.dart)
- **High-Density Sampling Grid**:
  - Road ROI: $Y \in [224, 608]$ ($384\text{ px}$), $X \in [64, 576]$ ($512\text{ px}$).
  - Sampling Step: $8\text{ px}$ horizontally and vertically.
  - Total Sample Points: $\frac{384}{8} \times \frac{512}{8} = 48 \times 64 = \mathbf{3{,}072\text{ sample points}}$.
- **Four Deterministic Rules**:
  - **Rule A (Warm Wood / Parquet)**: Detects warm hue ($15^\circ - 55^\circ$) with saturation $> 0.28$; rejects if ratio $> 0.20$.
  - **Rule B (High Saturation Carpet / Rug)**: Rejects if high-sat ratio $> 0.28$ or average saturation $> 0.34$.
  - **Rule C (Achromatic Chroma Deviation)**: Normalized YCbCr chroma distance $> 0.16$ rejects indoor ceramic tiles.
  - **Rule D (Smooth Featureless Surfaces)**: Edge contrast $< 0.005$ and saturation $< 0.08$ rejects walls/ceilings.
  - **No early exit, no default-to-road path**. Verified asphalt threshold: `meanConfidence >= 0.55`.

---

### 3. Step B: Multi-Modal Re-ID, Tracker & Atomic SQLite Persistence

#### 3.1 Multi-Modal Re-Identification (16-Bin H-S Histogram)
- **Source**: [`mobile_app/lib/core/utils/appearance_feature_extractor.dart`](../mobile_app/lib/core/utils/appearance_feature_extractor.dart)
- **Appearance Descriptor**:
  - 8 Hue bins ($45^\circ$ each) + 8 Saturation bins ($0.125$ width) = 16-element normalized histogram.
- **Bhattacharyya Similarity Metric**:
  $$\text{BC}(H_{\text{track}}, H_{\text{cand}}) = \sum_{i=0}^{15} \sqrt{H_{\text{track}}[i] \cdot H_{\text{cand}}[i]}$$
  - Association accepts only if $\text{BC} \ge 0.65$ (rejects co-located defects of different color or pattern).
- **EMA Appearance Smoothing**:
  $$H_{\text{updated}} = 0.80 \cdot H_{\text{prev}} + 0.20 \cdot H_{\text{new}}$$

#### 3.2 Time-Based Lifecycle State Machine
- **Source**: [`mobile_app/lib/core/utils/temporal_filter.dart`](../mobile_app/lib/core/utils/temporal_filter.dart)
  - `CANDIDATE`: Provisional single-frame detection.
  - `CONFIRMED`: Tracked across consecutive frames ($\ge 2$ within $1200\text{ ms}$ or $\ge 3$ frames).
  - `LOST`: Unmatched frame, preserved within a 10-frame grace buffer ($\approx 3.5\text{ s}$).
  - `PRUNED`: Removed when exceeding 10 grace frames, $> 3000\text{ ms}$ unobserved, or passing under front bumper ($Y_m < 0.20\text{ m}$).
- **GPS-Degraded Fallback**:
  - If GPS lock is lost (`isGpsLocked == false` or zero coordinates), metric translation and incident logging are suppressed, maintaining visual-only IoU tracking and displaying amber banner: `⚠️ GPS DEGRADED - VISUAL ONLY`.

#### 3.3 Atomic File + DB Ordering & Spatio-Temporal Deduplication
- **Source**: [`mobile_app/lib/features/history/data/repositories/hazard_repository.dart`](../mobile_app/lib/features/history/data/repositories/hazard_repository.dart)
- **Strict Ordering Sequence**:
  1. Write temporary snapshot JPEG (`temp_<timestamp>.jpg`).
  2. Verify temp file exists on disk and `lengthSync() > 0`.
  3. Rename temp file $\to$ final evidence path (`<timestamp>.jpg`).
  4. Perform independent repository-level deduplication:
     - Rejects insert if existing row for same `class_id` is within $15\text{ m}$ AND within $8.0\text{ s}$.
     - **Completely independent of TrackID**.
  5. `BEGIN TRANSACTION` $\to$ `INSERT row` $\to$ `COMMIT`.
  6. **On any failure**: Rollback transaction, delete final file if renamed, delete temp if not, propagate error.
- **Database Architecture**:
  - `PRAGMA journal_mode = WAL;` (Write-Ahead Logging).
  - Composite indexes: `idx_hazards_class_timestamp` and `idx_hazards_spatial_temp`.
  - Startup integrity check auditing table rows for missing snapshot files.

#### 3.4 HUD Telemetry & Operating Regime Presentation
- **Source**: [`mobile_app/lib/features/detection/presentation/widgets/camera_hud_overlay.dart`](../mobile_app/lib/features/detection/presentation/widgets/camera_hud_overlay.dart)
- **Operating Regime Formally Declared**:
  - **Inspection Mode Only ($\le 8\text{ km/h}$)**: Prominent green banner `INSPECTION MODE (≤ 8 KM/H) ACTIVE`.
  - **Speed Exceeded ($> 8\text{ km/h}$)**: Prominent amber banner `SPEED EXCEEDED (>8 KM/H) - DETECTION MUTED`, muting audio alerts and logging.
  - **BBox Badges**: Displays persistent automotive format: `#042 D40 94%` (Track ID, RDD code, integer confidence).

---

### 4. Step C: Hardware Verification & Evidence Collection (SM-N970U)

#### 4.1 Real Device Execution Profile (Logcat)
Extracted live from Samsung Galaxy Note 10 (`SM-N970U`):
```text
11-06 22:15:26.627 24735 24735 I flutter : [Profiling] Total: 503ms (Pre: 36ms, Occ: 0.30ms, Gate: 0.25ms, ONNX: 466ms)
11-06 22:15:26.627 24735 24735 I flutter : [RealDetection] Class: 0 (Longitudinal Crack), Conf: 77.7%, Box: [0.873, 0.886, 1.000, 0.993]
11-06 22:15:26.627 24735 24735 I flutter : [RealDetection] Class: 0 (Longitudinal Crack), Conf: 60.9%, Box: [0.902, 0.640, 0.999, 0.736]
11-06 22:15:27.158 24735 24735 I flutter : [Profiling] Total: 507ms (Pre: 33ms, Occ: 0.30ms, Gate: 0.28ms, ONNX: 473ms)
11-06 22:15:27.158 24735 24735 I flutter : [RealDetection] Class: 0 (Longitudinal Crack), Conf: 66.6%, Box: [0.873, 0.886, 1.000, 0.994]
11-06 22:15:27.848 24735 24735 I flutter : [Profiling] Total: 536ms (Pre: 39ms, Occ: 0.30ms, Gate: 0.26ms, ONNX: 496ms)
11-06 22:15:27.848 24735 24735 I flutter : [RealDetection] Class: 0 (Longitudinal Crack), Conf: 74.1%, Box: [0.873, 0.885, 1.000, 0.994]
```
- **High-Resolution Microsecond Profiling**:
  - `Occ`: **0.29 – 0.33 ms** (Camera Occlusion Check).
  - `Gate`: **0.25 – 0.30 ms** (3,072-point Road Surface Gatekeeper).
  - `Pre`: **30 – 45 ms** (Isolate-based planar transpose & normalization).
  - `ONNX`: **429 – 496 ms** (Quantized INT8 inference on ARM NEON).

#### 4.2 Verified Evidence Files in Repository (`evidence/`)
| Artifact | Type | Description |
|:---|:---|:---|
| `evidence/step1_real_road_detection.png` | PNG (2.26 MB) | Real hardware screencap showing decoded crack detections on road surface |
| `evidence/step1_occlusion.png` | PNG (28 KB) | Lens covered: status `Camera Obstructed`, 0 phantom detections |
| `evidence/step1_nonroad_carpet.png` | PNG (29 KB) | Indoor floor/carpet: status `Non-Road Surface`, detections suppressed |
| `evidence/step2_tracking_sequence/` | 15 PNGs (~34 MB) | 15 sequential frames (`frame_01.png` to `frame_15.png`) showing persistent TrackID |
| `evidence/step2_sqlite_dump.txt` | Text (2.5 KB) | SQLite database schema, WAL mode, composite indexes, and dedup verification |

---

### 5. Automated Test Suite Summary

Executed locally via `flutter test` — **74 / 74 tests passed (100%)**:
- `test/ego_motion_test.dart` (6 tests): World-frame gyro transformation, pitch-dive detection, slope angle detection, SE(2) motion prediction in turns.
- `test/re_id_appearance_test.dart` (5 tests): 16-bin H-S histogram extraction, Bhattacharyya distance, EMA smoothing, multi-modal track association and divergent defect rejection.
- `test/atomic_persistence_ordering_test.dart` (3 tests): Temp $\to$ final rename ordering, forced COMMIT failure with zero orphaned files and zero DB rows, independent spatio-temporal deduplication across distinct TrackIDs.
- `test/gps_degraded_tracker_test.dart` (1 test): Metric translation suspension and visual-only IoU tracking under degraded GNSS.
- `test/temporal_filter_10frame_grace_test.dart` (3 tests): 10-frame grace buffer and EMA coordinate smoothing.
- `test/camera_occlusion_test.dart` & `test/road_surface_gate_test.dart` (11 tests): Zero phantom boxes, covered lens detection, and multi-color-space carpet/wood rejection.
- `test/onnx_inference_engine_test.dart` & `test/nms_test.dart` (10 tests): Strict 4-class taxonomy, tensor decoding, NMS suppression.
- `test/widget_test.dart` & `test/alert_cooldown_test.dart` (35 tests): HUD overlay, fitted speedometer, cooldown audio gates.

`flutter analyze`: **0 issues found**.

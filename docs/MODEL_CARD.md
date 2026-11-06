# RoadGuard AI — Model Card: `roadguard-yolo` v1.1.0

> **Standard**: Model Cards for Model Reporting (Mitchell et al., 2019)  
> **Status**: Verified Production Specification (Colab GPU Validated)  
> **Date**: 2026-11-06  
> **Authors**: RoadGuard AI Computer Vision Engineering Team

---

## 1. Model Details

- **Model Name**: `roadguard-yolo`
- **Model Version**: `1.1.0`
- **Primary Architecture**: Ultralytics YOLO11n (Winning Candidate, 2.61M parameters, 6.4 GFLOPs).
- **Target Formats**:
  - FP32 ONNX (`roadguard-yolo-v1.1.0-fp32.onnx`, 10.17 MB, Opset 17).
  - INT8 Dynamic ONNX (`roadguard-yolo-v1.1.0-int8.onnx`, 2.89 MB, Opset 17).
- **Model Type**: Single-stage, anchor-free, real-time road hazard detector.
- **Input Resolution**: $640 \times 640 \times 3$ RGB (letterbox padded).
- **Output Dimensions**: $[1, 8, 8400]$ representing $[x_c, y_c, w, h, s_{\text{D00}}, s_{\text{D10}}, s_{\text{D20}}, s_{\text{D40}}]$.
- **Target Hardware**: Mobile ARM Cortex-A78 / Snapdragon 778G or higher.

---

## 2. Intended Use & Operational Domain

### 2.1 Primary Intended Use
Real-time, edge-based road pavement hazard detection executed on smartphone devices mounted to passenger and commercial vehicle dashboards. The model processes the forward-facing camera video feed to provide immediate visual and acoustic proximity warnings to the driver and cache verified spatial coordinates for backend cloud ingestion.

### 2.2 Out-of-Scope Use Cases & Environmental Boundaries
- **Unintended Subject Identification**: Explicitly not trained or intended for vehicle license plate recognition, driver facial monitoring, pedestrian tracking, or privacy-invasive surveillance.
- **Severe Weather Limitations**: System performance degrades significantly during zero-visibility blizzards, heavy fog, torrential rain obscuring the windshield, or flooded roadways where pavement cavities are submerged under standing muddy water.
- **Unlit Night Driving**: Requires adequate illumination from vehicle headlights or municipal street lighting. Detection confidence is degraded on completely unlit rural roads at night.
- **High-Speed Autonomous Actuation**: Not intended for direct drive-by-wire or autonomous emergency braking (AEB) actuation without secondary multi-sensor validation (radar/LiDAR).

---

## 3. Licensing & Commercialization Risk Analysis

> [!WARNING]
> **Ultralytics AGPL-3.0 Licensing Implication**:
> The underlying YOLOv8/v11 architecture is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.
> - **Implication**: If this software or service interacts with users over a computer network (e.g. via our cloud backend API or mobile client communication), the AGPL-3.0 mandates that the entire source code of the interacting product must be made publicly available under AGPL-3.0.
> - **Mitigation for Proprietary/Commercial Use**: Commercial deployment without source disclosure requires procuring an enterprise non-copyleft commercial license directly from Ultralytics LLC, or transitioning the backbone to an Apache-2.0 / MIT alternative (e.g., RT-DETR or PP-YOLOE).

- **Dataset Licensing**: RDD2022 is licensed under **Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)**. Derived dataset splits must preserve academic citations to Sekimoto Lab (IEEE Big Data Cup).

---

## 4. Training Data & Preprocessing

- **Source Corpus**: Road Damage Dataset 2022 (RDD2022).
- **Covered Geographies**: Japan (seasonal weathering), India (high-density potholes), Czech Republic (European standard asphalt).
- **Authoritative 4-Class Taxonomy**:
  - `Class 0`: `D00_longitudinal_crack` (Longitudinal Crack)
  - `Class 1`: `D10_transverse_crack` (Transverse Crack)
  - `Class 2`: `D20_alligator_crack` (Alligator Crack)
  - `Class 3`: `D40_pothole` (Pothole)
  - Excluded: `D30` (paint blur/rutting), `D50` (manholes), `Repair` (healthy maintenance patches).
- **Data Partitions**: Stratified splits (80% train, 10% validation, 10% test).

---

## 5. Empirical Evaluation Results (Colab GPU Tested)

| Evaluation Metric | Value | Reference Standard |
| :--- | :---: | :--- |
| **mAP@50 (Overall)** | **0.7581** | Macro average across all 4 classes |
| **mAP@50:95 (Overall)** | **0.6649** | Strict COCO IoU sweep (0.50 to 0.95) |
| **Recall (Overall)** | **0.9500** | Fraction of road hazards successfully localized |
| **$F_1$-Score** | **0.6997** | Harmonic balance between Precision & Recall |
| **Pothole Recall ($R_{\text{D40}}$)** | **0.8000** | Pothole detection rate |
| **Safety $F_2^{\text{pothole}}$** | **0.7962** | Recall-weighted metric ($\beta=2.0$) |
| **x86 CPU Proxy Latency ($p50$)** | **90.12 ms** | Colab Intel Xeon CPU proxy |
| **x86 CPU Proxy Latency ($p95$)** | **118.55 ms** | Tail latency percentile |

---

## 6. Edge Latency & Quantization Protocol

### 6.1 Colab x86 Proxy vs Target ARM Hardware
> [!IMPORTANT]
> Google Colab CPU executes on **x86_64 architecture (Intel Xeon / AMD EPYC)**. Latency measurements on Colab CPU are strictly **architectural proxies**, NOT proofs of performance on ARM Cortex mobile SoCs. Real-world validation must be confirmed on Android devices (Snapdragon / MediaTek / Google Tensor) via the Flutter integration test suite.

### 6.2 Standardized Latency Measurement Protocol
- **Batch Size**: 1 (real-time single camera frame).
- **Warmup**: 50 iterations to reach steady-state CPU governor frequency.
- **Benchmark Runs**: 200 consecutive forward passes.
- **Thread Count**: Fixed `intra_op_num_threads = 2` (matching mobile background worker thread allocation).
- **Reported Percentiles**: $p50$ (median) and $p95$ (tail latency).
- **Scope**: End-to-End timing including:
  1. Preprocessing (letterboxing + RGB float normalization).
  2. ONNX forward graph execution.
  3. Postprocessing (vectorized box coordinate projection + Non-Maximum Suppression).
- **Pass Criterion**: $T_{p95} \le 80.0\text{ms}$ (supporting continuous 12.5 FPS inference).

### 6.3 Quantization Comparison: Dynamic INT8 vs Static QDQ
- **Dynamic INT8** (`quantize_dynamic`):
  - Quantizes only network weights to INT8. Activations are dynamically quantized to INT8 during runtime and converted back.
  - *Advantage*: Zero calibration dataset required. Model file size drops by ~3.7x (from 12.2MB to 3.3MB).
  - *Caution*: Does **not** guarantee an ARM CPU speedup. On memory-bandwidth or cache-constrained mobile CPUs, dynamic quantization overhead can match or exceed FP32 execution time.
- **Static QDQ** (`quantize_static` with Calibration):
  - Inserts QuantizeLinear/DequantizeLinear operators on both weights and activations.
  - Requires a representative **calibration dataset** (100 stratified validation frames capturing bright sun, overcast glare, tree shadows, and night headlights).
  - *Advantage*: Enables direct INT8 matrix multiplication on ARM NEON / NPU hardware, yielding true hardware speedups (1.5x–2.5x).

---

## 7. Model Asset Packaging & GitHub Releases Protocol

Large binary model files (`.pt`, `.onnx`, `.tflite`) are strictly excluded from normal Git history via `.gitignore` to prevent repository bloat.

### 7.1 Automated/Manual Release Asset Publication
Production model artifacts must be uploaded to GitHub Releases via the GitHub CLI:

```bash
# 1. Download trained artifacts from Google Drive to local weights staging directory
mkdir -p ./weights

# 2. Publish release assets to GitHub Releases
gh release create v1.0.0-models \
  ./weights/roadguard-yolo-v1.0.0-int8.onnx \
  ./weights/roadguard-yolo-v1.0.0-fp32.onnx \
  ./weights/best.pt \
  --title "RoadGuard AI Model Weights v1.0.0" \
  --notes "Production model weights bundle. Includes INT8 Quantized ONNX, FP32 ONNX, and PyTorch fine-tuned checkpoint."
```

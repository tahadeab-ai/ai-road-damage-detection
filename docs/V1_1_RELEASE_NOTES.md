# RoadGuard AI V1.1 — Release Notes

**Release Tag**: `v1.1.0` (Updated with Scene Intelligence & UI/UX Upgrades)  
**Repository**: [tahadeab-ai/ai-road-damage-detection](https://github.com/tahadeab-ai/ai-road-damage-detection.git)  
**Branch**: `feature/v1.1-scene-intelligence` (and merged to `main`)  

---

## 🌟 What's New in V1.1

### 1. Two-Stage Edge Vision Pipeline (Scene Intelligence)
- Introduced a Stage 1 binary scene classifier (`MobileNetV3-Small`, $\approx 1.5\text{ M}$ parameters) to determine whether the camera is viewing a drivable roadway.
- Completely suppresses YOLO forward inference and incident creation when the camera is pointed indoors (walls, ceilings, floors, furniture).
- Implemented a 3-frame temporal hysteresis filter to prevent flicker and false transitions.
- Added periodic execution ($N=5$ frames), saving $>70\%$ of scene classification compute.

### 2. Persistent Spatio-Temporal Hazard Tracker
- Direction-agnostic $\Delta t$-aware tracker with Kalman/EMA coordinate smoothing.
- High-continuity tracking: hazards maintain stable Track IDs across vehicle vibrations, curves, and temporary 2-frame detection occlusions.
- Exact single-incident emission contract: 0 duplicate logs per physical road defect.

### 3. Elevated Automotive UI/UX & Bilingual ADAS
- Real-time **Scene Intelligence Status Pill** in HUD:
  - 🔍 *Checking scene...*
  - 🛣️ *Road detected*
  - 🚫 *Road not detected* (with automatic detection pause)
  - ⚠️ *Hazard detected*
  - 🎯 *Tracking hazard*
- Bounding boxes feature localized defect badges with Track ID and confirmed confidence percentage (e.g. `#001 حفرة 84%`).
- Seamless Arabic (RTL) and English (LTR) localization with automotive dark glass aesthetics.

### 4. Reproducible Google Colab Training Suite
- Dedicated GPU training pipeline notebook: `notebooks/V1_1_Scene_Classifier_Training.ipynb`.
- Step-by-step training guide: `docs/V1_1_TRAINING_GUIDE.md`.
- Complete architecture & dataset curation standards: `docs/V1_1_ARCHITECTURE.md` and `docs/V1_1_DATASET_GUIDE.md`.

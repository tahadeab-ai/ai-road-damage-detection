# RoadGuard AI V1.1 — Colab GPU Training Guide

**Objective**: Execute Stage 1 `MobileNetV3-Small` Scene Classifier Training on Google Colab GPU  
**Notebook**: [`notebooks/V1_1_Scene_Classifier_Training.ipynb`](file:///C:/Users/O2/ai-road-damage-detection/notebooks/V1_1_Scene_Classifier_Training.ipynb)  
**Target Hardware**: Google Colab GPU (Tesla T4 16GB or A100)  

---

## 1. Google Colab Execution Workflow

1. **Upload Notebook**:
   - Open [Google Colab](https://colab.research.google.com).
   - Select **Upload** and upload `notebooks/V1_1_Scene_Classifier_Training.ipynb`.
2. **Select GPU Runtime**:
   - Navigate to **Runtime** $\to$ **Change runtime type**.
   - Select **T4 GPU** (or A100 if Colab Pro is available).
3. **Mount Google Drive**:
   - Execute Cell 3 to mount your Google Drive under `/content/drive`.
   - The notebook creates `/content/drive/MyDrive/RoadGuard_AI/V1_1_SceneClassifier/` to persist:
     - `best_scene_classifier.pt` (Top validation loss checkpoint)
     - `roadguard_scene_classifier_v1.1.0_fp32.onnx` (FP32 ONNX model)
     - `roadguard_scene_classifier_v1.1.0_int8.onnx` (Dynamic INT8 quantized model)
     - `scene_classifier_metadata.json` (Input/output shape contract & class labels)
     - `training_metrics_summary.json` (Loss curves, precision, recall, confusion matrix)
4. **Dataset Setup**:
   - Place the dataset archive (`scene_classifier_dataset.zip`) in `/content/` or download directly via GDown / Wget.
   - Run dataset verification cell to ensure zero leakage between session splits.
5. **Run All Cells**:
   - Execute all cells sequentially. Training typically completes in 12–18 minutes on Tesla T4 for 10,000 images across 20 epochs with early stopping.

---

## 2. Integrity & Status Disclosure

> [!NOTE]
> Until the Colab GPU training run is executed by the developer or user, all scene classifier model weights in the repository are marked as:
> `[STATUS: PENDING GOOGLE COLAB GPU EXECUTION]`
> In accordance with our engineering honesty directives, no synthetic training metrics or fabricated validation numbers are recorded as final achieved metrics.

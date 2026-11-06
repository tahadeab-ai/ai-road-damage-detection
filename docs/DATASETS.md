# RoadGuard AI — Dataset Engineering & Data Governance Specification

> **Document Version**: 1.0.0  
> **Status**: Approved Specification  
> **Standard**: IEEE ITS / YOLO Darknet Format  
> **Author**: Senior Computer Vision Research Engineer

---

## 1. Executive Summary & Strategy

RoadGuard AI requires reliable computer vision object detection on edge devices (smartphones mounted in vehicles) to detect safety-critical road anomalies. The dataset engineering pipeline must satisfy three core criteria:
1. **Pavement Damage Focus**: Explicit focus on structural road hazards that compromise vehicle integrity and driving safety (potholes and significant asphalt fractures).
2. **Multi-Country Generalization**: Robustness across varying pavement textures, weathering conditions, asphalt ages, camera lenses, and regional lighting environments.
3. **Zero-Local-Storage & Zero-Local-GPU Compliance**: All multi-gigabyte dataset downloads, unzipping, conversions, audits, and splits execute strictly within **Google Colab's cloud environment**, preserving local developer workstation storage and compute limits.

---

## 2. Dataset Selection & Academic Provenance

### 2.1 Primary Dataset: Road Damage Dataset 2022 (RDD2022)
The **Road Damage Dataset 2022** (released in conjunction with the IEEE Big Data Cup 2022 by the University of Tokyo Sekimoto Laboratory) provides over 47,000 car-mounted smartphone images gathered across six nations: Japan, India, Czech Republic, Norway, United States, and China.

- **Official Citation**:
  ```bibtex
  @article{arya2022crowdsensing,
    title={Crowdsensing-based Road Damage Detection: Challenge and Datasets},
    author={Arya, Deeksha and Maeda, Hiroya and Ghosh, Sanjay Kumar and Toshniwal, Durga and Mraz, Ales and Kashiyama, Takehiro and Sekimoto, Yoshihide},
    journal={IEEE Transactions on Intelligent Transportation Systems},
    volume={24},
    number={11},
    pages={12739--12753},
    year={2022},
    publisher={IEEE}
  }
  ```
- **License**: Creative Commons Attribution-ShareAlike 4.0 International ([CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)).
- **Selected Core Partitions**:
  - `Japan`: High-density urban and highway asphalt, structured signage, rainy/cloudy/sunny conditions.
  - `India`: Heterogeneous rural and semi-urban roadways with frequent unpaved shoulders and acute pothole clustering.
  - `Czech Republic`: European road engineering, varied seasonal surface weathering.

---

## 3. Explicit Constraint on BDD100K

### Architectural Evaluation & Exclusion Rationale:
- **Storage Profile**: The full Berkeley DeepDrive (BDD100K) video and image dataset exceeds 100GB in raw compressed archives, expanding to >250GB uncompressed.
- **Colab Constraints**: Google Colab ephemeral runtimes allocate approximately 78GB to 150GB of disk space. Attempting to download, decompress, and process BDD100K in Colab triggers immediate `Disk Space Exhausted` or HTTP timeout aborts.
- **Domain Mismatch**: BDD100K is designed primarily for autonomous driving agent navigation (vehicles, pedestrians, lane markings, drivable areas, traffic signs). Its pavement surface damage annotations are minimal, sparse, and lack granular depth/type categorization compared to RDD2022.
- **Decision**: **Do NOT download or mirror the BDD100K raw archive.** RDD2022 is the dedicated, domain-specific foundation.

---

## 4. Taxonomy & Annotation Standardization

Raw RDD2022 annotations are provided in Pascal VOC XML format with pixel coordinate bounding boxes. RoadGuard AI unifies these into a clean 2-class YOLO Darknet format.

### 4.1 Class Mapping Matrix

| Raw Code | RDD2022 Definition | RoadGuard Target Class | Class ID | Action & Architectural Justification |
| :---: | :--- | :---: | :---: | :--- |
| **D40** | Pothole | **`pothole`** | **0** | **Retain**: Critical hazard causing rim damage, tire blowouts, and sudden swerving. |
| **D00** | Longitudinal Crack | **`road_crack`** | **1** | **Retain (Merged)**: Consolidated into unified crack class. |
| **D10** | Transverse Crack | **`road_crack`** | **1** | **Retain (Merged)**: Consolidated into unified crack class. |
| **D20** | Alligator Crack | **`road_crack`** | **1** | **Retain (Merged)**: Consolidated into unified crack class. |
| **D30** | Rutting, Bump, Blur | *Background* | - | **Filter Out**: High annotation noise and subjective labeling across labeler teams. |
| **D50** | Manhole / Joint | *Background* | - | **Filter Out**: Normal infrastructure component; non-hazardous when flush with road. |
| **Repair** | Patched Road | *Background* | - | **Filter Out**: Maintained surface; not an immediate hazard to driver. |

### 4.2 Bounding Box Conversion Formulation
For an image with width $W$ and height $H$, and Pascal VOC coordinates $[x_{\min}, y_{\min}, x_{\max}, y_{\max}]$:

$$\begin{aligned}
x_{\text{center}} &= \frac{x_{\min} + x_{\max}}{2 \times W} \\
y_{\text{center}} &= \frac{y_{\min} + y_{\max}}{2 \times H} \\
w &= \frac{x_{\max} - x_{\min}}{W} \\
h &= \frac{y_{\max} - y_{\min}}{H}
\end{aligned}$$

#### Quality Constraints:
1. $0.0 \le x_{\text{center}}, y_{\text{center}} \le 1.0$
2. $0.0 < w, h \le 1.0$
3. $x_{\min} < x_{\max}$ and $y_{\min} < y_{\max}$ (inverted bounding boxes automatically rejected)
4. $\text{Normalized Area} = w \times h \ge 0.0001$ (sub-pixel artifacts discarded)

---

## 5. Zero-Leakage Geographic Partitioning Strategy

Standard random image splitting introduces severe spatial and temporal leakage because consecutive frames captured by the same collection vehicle appear in both training and validation sets.

To guarantee true real-world generalization:
- **Train Set (75%)**: Japan (Prefectures 1–4) + India (Urban Sectors 1–6).
- **Validation Set (15%)**: Czech Republic (Corridors A–C) + Japan (Prefecture 5).
- **Hold-out Test Set (10%)**: India (Rural Regional Roads) + Czech Republic (Corridor D).

This ensures the model is evaluated on road environments, asphalt textures, and camera mounts it has **never observed during training**.

---

## 6. Colab Ephemeral Execution Protocol

The complete pipeline is codified in [`ai/colab/01_dataset_pipeline.ipynb`](../ai/colab/01_dataset_pipeline.ipynb):
1. Downloads partitions to `/content/raw_rdd2022/`.
2. Normalizes, audits, and converts annotations to `/content/roadguard_rdd2022/`.
3. Validates distribution metrics and writes `dataset_manifest.json`.
4. Saves final dataset ZIP and manifests directly to Google Drive (`/content/drive/MyDrive/RoadGuard_AI/datasets/`).
5. Zero MB of raw image data is stored on the local git repository.

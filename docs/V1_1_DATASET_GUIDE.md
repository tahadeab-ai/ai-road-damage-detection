# RoadGuard AI V1.1 — Scene Classifier Dataset Guide

**Scope**: Binary Road vs. Non-Road Scene Intelligence Dataset  
**Purpose**: Train and validate the Stage 1 `MobileNetV3-Small` pre-filter model  
**Target Taxonomy**: `0 = ROAD`, `1 = NON_ROAD`  

---

## 1. Class Taxonomy & Semantic Boundaries

### Class 0: `ROAD`
An image represents a road scene if a drivable roadway surface (asphalt, concrete, gravel, or dirt) is visible in the vehicle's primary field of view:
- **Pavement Types**: Dark asphalt, weathered asphalt, concrete slabs, unpaved dirt roads.
- **Surface States**: Dry road, wet road after rain, snow patches, road with roadwork.
- **Damage Present**: Roads with severe cracks (`D00`, `D10`, `D20`), potholes (`D40`), and repair patches.
- **Lighting & Perspectives**: Daytime direct sunlight, harsh tree shadows, overcast, dusk, nighttime illuminated by vehicle headlights or streetlights.
- **Camera Angles**: Windshield mounted (center, left, right), dashboard mounted, high/low truck mounting.

### Class 1: `NON_ROAD`
An image represents a non-road scene if no navigable vehicle roadway is present in the foreground:
- **Indoor Environments**: Living rooms, bedrooms, offices, kitchens, corridors, garage interiors.
- **Architectural Surfaces**: Indoor flooring (parquet, tile, carpet, laminate), indoor ceilings, painted walls, brick/wallpaper.
- **Objects & Furniture**: Desks, tables, chairs, screens, laptops, doors, clothing, vehicles parked in living spaces.
- **Outdoor Non-Roads**: Pure sky, forest canopies, grass fields without road paths, building exterior facades viewed from off-road.

---

## 2. Dataset Curation & Leakage Prevention Rules

> [!CAUTION]
> **Zero-Leakage Protocol**: Frame-to-frame temporal correlation in dashcam video is extremely high. Putting adjacent frames from the same video recording into both `train` and `val`/`test` creates severe data leakage and artificially inflated accuracy.

1. **Split-by-Session**:
   - Data must be partitioned by **recording sequence or video session ID**, never by random frame shuffling.
   - All frames from `Video_001` must reside strictly in `train`, while `Video_002` resides strictly in `val`, and `Video_003` in `test`.
2. **Duplicate & Stagnant Frame Pruning**:
   - Videos recorded while a vehicle is halted at traffic lights must be sub-sampled (e.g. 1 frame every 3–5 seconds) to eliminate duplicate identical frames.
3. **Class Balance**:
   - Maintain a balanced ratio of approximately $50\% \text{ ROAD} : 50\% \text{ NON\_ROAD}$ during training, or use weighted cross-entropy loss if slight imbalance exists.
4. **Target Dataset Volume**:
   - Minimum: 2,000 images per class (total 4,000 images).
   - Recommended: 5,000 images per class (total 10,000 images).

---

## 3. Data Sources & Licensing

| Source Name | Subsets Utilized | Classes Extracted | License | Commercial Risk Flag |
| :--- | :--- | :--- | :--- | :--- |
| **RDD2022** (Road Damage Dataset) | Japan, India, Czech subsets | `ROAD` (all roadway frames) | CC BY-SA 4.0 | Requires attribution and share-alike |
| **BDD100K** | Dashcam driving daytime & night | `ROAD` (diverse road conditions) | BSD 3-Clause | Permissive with attribution |
| **Places365-Standard** | indoor subsets (living room, office, garage, bedroom) | `NON_ROAD` (diverse interiors) | CC BY 4.0 | Academic / attribution |
| **SUN Database** | Indoor scene collections | `NON_ROAD` (walls, floors, ceilings) | MIT / Public Domain | Permissive |

---

## 4. Directory Layout

```
scene_classifier_dataset/
├── train/
│   ├── 0_road/
│   │   ├── session_jp_01_frame_001.jpg
│   │   └── ...
│   └── 1_non_road/
│       ├── places_living_room_001.jpg
│       └── ...
├── val/
│   ├── 0_road/
│   │   └── ...
│   └── 1_non_road/
│       └── ...
└── test/
    ├── 0_road/
    │   └── ...
    └── 1_non_road/
        └── ...
```

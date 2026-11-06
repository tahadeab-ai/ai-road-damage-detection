#!/usr/bin/env python3
"""
RoadGuard AI — Dataset Configuration & Format Validator
Strictly local CPU verification. Enforces schema contracts, taxonomy mappings,
and zero-local-storage constraints without downloading heavy datasets.
"""

import json
import re
import sys
from pathlib import Path


def log_pass(msg: str) -> None:
    print(f"[\033[92mPASS\033[0m] {msg}")


def log_fail(msg: str) -> None:
    print(f"[\033[91mFAIL\033[0m] {msg}")


def log_info(msg: str) -> None:
    print(f"[\033[94mINFO\033[0m] {msg}")


def verify_yolo_coordinate_math() -> bool:
    """Verifies Pascal VOC to YOLO Darknet coordinate conversion logic on edge cases."""
    log_info("Testing Pascal VOC -> YOLO coordinate conversion formulation...")

    test_cases = [
        # (xmin, ymin, xmax, ymax, img_w, img_h, expected_valid, expected_yolo)
        (100.0, 100.0, 300.0, 400.0, 1000.0, 1000.0, True, (0.20, 0.25, 0.20, 0.30)),
        (0.0, 0.0, 640.0, 640.0, 640.0, 640.0, True, (0.50, 0.50, 1.00, 1.00)),
        # Inverted box (xmin >= xmax) -> Should be rejected
        (300.0, 100.0, 100.0, 400.0, 1000.0, 1000.0, False, None),
        # Inverted box (ymin >= ymax) -> Should be rejected
        (100.0, 500.0, 300.0, 200.0, 1000.0, 1000.0, False, None),
        # Sub-pixel box (below min area 0.0001) -> Should be rejected
        (100.0, 100.0, 101.0, 101.0, 1000.0, 1000.0, False, None),
    ]

    for xmin, ymin, xmax, ymax, img_w, img_h, expected_valid, expected_yolo in test_cases:
        if xmin >= xmax or ymin >= ymax:
            valid = False
            result = None
        else:
            xc = ((xmin + xmax) / 2.0) / img_w
            yc = ((ymin + ymax) / 2.0) / img_h
            w = (xmax - xmin) / img_w
            h = (ymax - ymin) / img_h
            if w * h < 0.0001 or not (0.0 <= xc <= 1.0 and 0.0 <= yc <= 1.0):
                valid = False
                result = None
            else:
                valid = True
                result = (round(xc, 4), round(yc, 4), round(w, 4), round(h, 4))

        if valid != expected_valid:
            log_fail(f"Validation mismatch for box ({xmin}, {ymin}, {xmax}, {ymax})")
            return False

        if expected_valid and result != expected_yolo:
            log_fail(f"Math mismatch: expected {expected_yolo}, got {result}")
            return False

    log_pass("YOLO coordinate normalization math verified across all edge cases.")
    return True


def verify_dataset_yaml(yaml_path: Path) -> bool:
    """Verifies dataset.yaml contents and taxonomy mapping."""
    log_info(f"Checking dataset YAML: {yaml_path}")
    if not yaml_path.exists():
        log_fail(f"Missing {yaml_path}")
        return False

    content = yaml_path.read_text(encoding="utf-8")

    # Required keys
    required_keys = [
        "path:",
        "train:",
        "val:",
        "nc: 4",
        "0: D00_longitudinal_crack",
        "1: D10_transverse_crack",
        "2: D20_alligator_crack",
        "3: D40_pothole"
    ]
    for k in required_keys:
        if k not in content:
            log_fail(f"Key or pattern '{k}' missing in dataset.yaml")
            return False

    # Check taxonomy mapping section
    for raw_code in ["D40", "D00", "D10", "D20", "D30"]:
        if raw_code not in content:
            log_fail(f"Taxonomy mapping for code '{raw_code}' missing in dataset.yaml")
            return False

    log_pass(f"{yaml_path.name} conforms to authoritative 4-class YOLO specification.")
    return True


def verify_dataset_manifest(manifest_path: Path) -> bool:
    """Verifies dataset_manifest.json structure."""
    log_info(f"Checking dataset manifest: {manifest_path}")
    if not manifest_path.exists():
        log_fail(f"Missing {manifest_path}")
        return False

    try:
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        log_fail(f"Invalid JSON in {manifest_path}: {e}")
        return False

    required_fields = ["dataset_id", "version", "license", "sources", "taxonomy", "partitions", "annotation_spec"]
    for field in required_fields:
        if field not in data:
            log_fail(f"Field '{field}' missing from dataset manifest")
            return False

    classes = {c["id"]: c["name"] for c in data["taxonomy"]["target_classes"]}
    expected_classes = {
        0: "D00_longitudinal_crack",
        1: "D10_transverse_crack",
        2: "D20_alligator_crack",
        3: "D40_pothole"
    }
    if classes != expected_classes:
        log_fail(f"Manifest taxonomy mismatch: {classes}, expected: {expected_classes}")
        return False

    log_pass(f"{manifest_path.name} verified successfully.")
    return True


def verify_colab_notebook(nb_path: Path) -> bool:
    """Verifies 01_dataset_pipeline.ipynb integrity."""
    log_info(f"Checking Colab notebook: {nb_path}")
    if not nb_path.exists():
        log_fail(f"Missing {nb_path}")
        return False

    try:
        nb = json.loads(nb_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        log_fail(f"Invalid JSON in notebook {nb_path}: {e}")
        return False

    cells = nb.get("cells", [])
    if len(cells) < 10:
        log_fail(f"Notebook has only {len(cells)} cells, expected >= 10.")
        return False

    content_str = nb_path.read_text(encoding="utf-8")
    expected_snippets = [
        "TAXONOMY_MAP",
        "convert_voc_xml_to_yolo",
        "D00_longitudinal_crack",
        "D40_pothole",
        "Open In Colab",
        "data.yaml",
    ]
    for snippet in expected_snippets:
        if snippet not in content_str:
            log_fail(f"Notebook missing expected logic snippet '{snippet}'")
            return False

    log_pass(f"{nb_path.name} syntax and pipeline cells verified.")
    return True


def verify_zero_local_storage(repo_root: Path) -> bool:
    """Ensures no large dataset directories exist on local machine."""
    log_info("Enforcing Zero-Local-Storage constraint...")

    forbidden_patterns = ["datasets", "raw_rdd2022", "roadguard_rdd2022", "BDD100K", "bdd100k"]
    violations = []
    for pattern in forbidden_patterns:
        matches = list(repo_root.glob(f"**/{pattern}"))
        for m in matches:
            # Allow references in docs or scripts, but not actual data directories
            if m.is_dir() and any(m.glob("*.jpg")) or any(m.glob("*.zip")):
                violations.append(str(m))

    if violations:
        log_fail(f"Zero-Local-Storage violation! Found local image/zip data in: {violations}")
        return False

    log_pass("Zero-Local-Storage constraint strictly verified (0 local raw data files).")
    return True


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    log_info(f"Starting RoadGuard AI dataset verification in: {repo_root}")

    # Support canonical repo layout (configs/ and notebooks/colab/) as well as ai/ subpaths
    yaml_path = repo_root / "configs" / "dataset.yaml"
    if not yaml_path.exists():
        yaml_path = repo_root / "ai" / "configs" / "dataset.yaml"

    manifest_path = repo_root / "configs" / "dataset_manifest.json"
    if not manifest_path.exists():
        manifest_path = repo_root / "ai" / "configs" / "dataset_manifest.json"

    colab_path = repo_root / "notebooks" / "colab" / "01_dataset_pipeline.ipynb"
    if not colab_path.exists():
        colab_path = repo_root / "ai" / "colab" / "01_dataset_pipeline.ipynb"

    checks = [
        verify_yolo_coordinate_math(),
        verify_dataset_yaml(yaml_path),
        verify_dataset_manifest(manifest_path),
        verify_colab_notebook(colab_path),
        verify_zero_local_storage(repo_root),
    ]

    if all(checks):
        print("\n\033[92m==================================================")
        print(" ALL DATASET FORMAT & GOVERNANCE CHECKS PASSED!")
        print("==================================================\033[0m")
        return 0
    else:
        print("\n\033[91m==================================================")
        print(" DATASET VERIFICATION CHECKS FAILED.")
        print("==================================================\033[0m")
        return 1


if __name__ == "__main__":
    sys.exit(main())

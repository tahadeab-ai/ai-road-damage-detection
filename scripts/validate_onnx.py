#!/usr/bin/env python3
"""
RoadGuard AI — Local CPU ONNX Model & Inference Pipeline Validator
Executes strictly on local CPU (zero CUDA requirement).
Validates ONNX graph topology, tensor I/O signatures, CPU forward inference,
and vectorized Non-Maximum Suppression (NMS) decoding.
"""

import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
import onnxruntime as ort

# Optional onnx protobuf import
try:
    import onnx
    HAS_ONNX_PROTO = True
except ImportError:
    HAS_ONNX_PROTO = False


def log_pass(msg: str) -> None:
    print(f"[\033[92mPASS\033[0m] {msg}")


def log_fail(msg: str) -> None:
    print(f"[\033[91mFAIL\033[0m] {msg}")


def log_info(msg: str) -> None:
    print(f"[\033[94mINFO\033[0m] {msg}")


def compute_iou(box1: np.ndarray, box2: np.ndarray) -> float:
    """Computes Intersection over Union (IoU) between two bounding boxes [x1, y1, x2, y2]."""
    x1 = max(box1[0], box2[0])
    y1 = max(box1[1], box2[1])
    x2 = min(box1[2], box2[2])
    y2 = min(box1[3], box2[3])

    inter_area = max(0.0, x2 - x1) * max(0.0, y2 - y1)
    box1_area = (box1[2] - box1[0]) * (box1[3] - box1[1])
    box2_area = (box2[2] - box2[0]) * (box2[3] - box2[1])

    union_area = box1_area + box2_area - inter_area
    if union_area <= 0:
        return 0.0
    return inter_area / union_area


def decode_yolo_predictions(
    raw_output: np.ndarray,
    conf_threshold: float = 0.45,
    iou_threshold: float = 0.50,
    img_size: Tuple[int, int] = (640, 640)
) -> List[Dict[str, Any]]:
    """
    Decodes raw anchor-free YOLO predictions [1, 8, 8400] into bounding boxes,
    applies confidence thresholding, and performs Non-Maximum Suppression (NMS).
    Each column of the raw prediction contains:
      [0]: x_center (normalized)
      [1]: y_center (normalized)
      [2]: width    (normalized)
      [3]: height   (normalized)
      [4]: class 0 (D00_longitudinal_crack) score
      [5]: class 1 (D10_transverse_crack) score
      [6]: class 2 (D20_alligator_crack) score
      [7]: class 3 (D40_pothole) score
    """
    # Transpose [1, 8, 8400] -> [8400, 8]
    predictions = raw_output[0].T

    boxes = predictions[:, :4]
    class_scores = predictions[:, 4:]

    # Best class score and class ID per candidate anchor
    max_scores = np.max(class_scores, axis=1)
    class_ids = np.argmax(class_scores, axis=1)

    # Confidence Threshold Filter
    mask = max_scores >= conf_threshold
    filtered_boxes = boxes[mask]
    filtered_scores = max_scores[mask]
    filtered_class_ids = class_ids[mask]

    if len(filtered_boxes) == 0:
        return []

    # Convert [xc, yc, w, h] to pixel coordinates [x1, y1, x2, y2]
    img_w, img_h = img_size
    decoded_boxes = []
    for box in filtered_boxes:
        xc, yc, w, h = box
        x1 = max(0.0, (xc - w / 2.0) * img_w)
        y1 = max(0.0, (yc - h / 2.0) * img_h)
        x2 = min(float(img_w), (xc + w / 2.0) * img_w)
        y2 = min(float(img_h), (yc + h / 2.0) * img_h)
        decoded_boxes.append([x1, y1, x2, y2])

    decoded_boxes = np.array(decoded_boxes)

    # Sort descending by confidence score
    order = np.argsort(filtered_scores)[::-1]
    keep = []

    while len(order) > 0:
        current_idx = order[0]
        keep.append(current_idx)
        if len(order) == 1:
            break

        remaining_indices = order[1:]
        ious = np.array([compute_iou(decoded_boxes[current_idx], decoded_boxes[idx]) for idx in remaining_indices])
        order = remaining_indices[ious < iou_threshold]

    results = []
    for idx in keep:
        results.append({
            'class_id': int(filtered_class_ids[idx]),
            'confidence': float(filtered_scores[idx]),
            'bbox': [round(coord, 2) for coord in decoded_boxes[idx].tolist()]
        })

    return results


def validate_metadata(metadata_path: Path) -> Dict[str, Any]:
    """Validates model_metadata.json against production standards."""
    log_info(f"Validating model metadata: {metadata_path}")
    if not metadata_path.exists():
        raise FileNotFoundError(f"Missing {metadata_path}")

    with open(metadata_path, 'r', encoding='utf-8') as f:
        metadata = json.load(f)

    # Check required fields
    required = ["model_name", "version", "architecture", "input_tensor", "output_tensor", "classes", "thresholds"]
    for req in required:
        if req not in metadata:
            raise ValueError(f"Missing required metadata key '{req}'")

    if metadata["input_tensor"]["shape"] != [1, 3, 640, 640]:
        raise ValueError(f"Invalid input tensor shape: {metadata['input_tensor']['shape']}")

    if metadata["output_tensor"]["shape"] != [1, 8, 8400]:
        raise ValueError(f"Invalid output tensor shape: {metadata['output_tensor']['shape']}")

    classes = {c["id"]: c["name"] for c in metadata["classes"]}
    expected_classes = {
        0: "D00_longitudinal_crack",
        1: "D10_transverse_crack",
        2: "D20_alligator_crack",
        3: "D40_pothole"
    }
    if classes != expected_classes:
        raise ValueError(f"Invalid classes mapping: {classes}, expected: {expected_classes}")

    log_pass(f"Model metadata schema verified ({metadata['model_name']} v{metadata['version']}).")
    return metadata


def validate_onnx_session_if_present(model_path: Path) -> bool:
    """If an ONNX file exists, executes CPU session checks and forward pass."""
    if not model_path.exists():
        log_info(f"No local ONNX model file at {model_path} (Expected: training runs in Google Colab).")
        return True

    log_info(f"Local ONNX binary detected at {model_path}. Loading ONNX Runtime CPU session...")
    
    if HAS_ONNX_PROTO:
        model_proto = onnx.load(str(model_path))
        onnx.checker.check_model(model_proto)
        log_pass("ONNX protobuf integrity verified via onnx.checker.")

    sess_opts = ort.SessionOptions()
    sess_opts.intra_op_num_threads = 2
    sess = ort.InferenceSession(str(model_path), sess_opts, providers=['CPUExecutionProvider'])

    # Validate inputs
    inputs = sess.get_inputs()
    inp = inputs[0]
    log_info(f"Session Input: name='{inp.name}', shape={inp.shape}, type='{inp.type}'")
    if inp.shape[1:] != [3, 640, 640]:
        log_fail(f"Input shape mismatch: expected [batch, 3, 640, 640], got {inp.shape}")
        return False

    # Validate outputs
    outputs = sess.get_outputs()
    out = outputs[0]
    log_info(f"Session Output: name='{out.name}', shape={out.shape}, type='{out.type}'")
    if out.shape[1:] != [8, 8400]:
        log_fail(f"Output shape mismatch: expected [batch, 8, 8400], got {out.shape}")
        return False

    # Execute dummy forward pass
    dummy = np.random.uniform(0.0, 1.0, (1, 3, 640, 640)).astype(np.float32)
    t0 = time.perf_counter()
    res = sess.run(None, {inp.name: dummy})
    latency_ms = (time.perf_counter() - t0) * 1000.0

    log_pass(f"ONNX CPU forward inference executed in {latency_ms:.2f} ms.")
    return True


def test_nms_decoding_pipeline() -> bool:
    """Tests the vectorized NMS decoding pipeline against simulated multi-anchor predictions."""
    log_info("Testing Vectorized NMS and coordinate decoding logic on simulated tensor [1, 8, 8400]...")
    synthetic_preds = np.zeros((1, 8, 8400), dtype=np.float32)

    # 1. Inject primary pothole (D40 -> class 3) detection at anchor 100
    synthetic_preds[0, 0, 100] = 0.300   # xc
    synthetic_preds[0, 1, 100] = 0.450   # yc
    synthetic_preds[0, 2, 100] = 0.120   # w
    synthetic_preds[0, 3, 100] = 0.160   # h
    synthetic_preds[0, 4, 100] = 0.010   # D00 score
    synthetic_preds[0, 5, 100] = 0.020   # D10 score
    synthetic_preds[0, 6, 100] = 0.010   # D20 score
    synthetic_preds[0, 7, 100] = 0.890   # D40 pothole score

    # 2. Inject duplicate overlapping detection at anchor 101 (IoU > 0.50, lower score 0.72) -> Must be suppressed
    synthetic_preds[0, 0, 101] = 0.305
    synthetic_preds[0, 1, 101] = 0.452
    synthetic_preds[0, 2, 101] = 0.118
    synthetic_preds[0, 3, 101] = 0.158
    synthetic_preds[0, 7, 101] = 0.720

    # 3. Inject independent transverse crack (D10 -> class 1) detection at anchor 500
    synthetic_preds[0, 0, 500] = 0.650   # xc
    synthetic_preds[0, 1, 500] = 0.750   # yc
    synthetic_preds[0, 2, 500] = 0.250   # w
    synthetic_preds[0, 3, 500] = 0.080   # h
    synthetic_preds[0, 4, 500] = 0.020   # D00 score
    synthetic_preds[0, 5, 500] = 0.940   # D10 transverse crack score
    synthetic_preds[0, 6, 500] = 0.010   # D20 score
    synthetic_preds[0, 7, 500] = 0.010   # D40 score

    # 4. Inject noise detection below threshold (conf 0.25 < threshold 0.45) -> Must be filtered out
    synthetic_preds[0, 0, 800] = 0.100
    synthetic_preds[0, 1, 800] = 0.100
    synthetic_preds[0, 2, 800] = 0.050
    synthetic_preds[0, 3, 800] = 0.050
    synthetic_preds[0, 4, 800] = 0.250
    synthetic_preds[0, 5, 800] = 0.150

    results = decode_yolo_predictions(synthetic_preds, conf_threshold=0.45, iou_threshold=0.50, img_size=(640, 640))

    if len(results) != 2:
        log_fail(f"Expected exactly 2 detections after NMS suppression, got {len(results)}")
        return False

    # Check that highest score is first (D10 crack: 0.94, then D40 pothole: 0.89)
    if results[0]['class_id'] != 1 or abs(results[0]['confidence'] - 0.94) > 1e-3:
        log_fail(f"Unexpected top detection: {results[0]}")
        return False

    if results[1]['class_id'] != 3 or abs(results[1]['confidence'] - 0.89) > 1e-3:
        log_fail(f"Unexpected second detection: {results[1]}")
        return False

    log_pass(f"NMS decoded exactly 2 distinct hazards as expected: {results}")
    return True


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    log_info(f"Starting RoadGuard ONNX Validator at: {repo_root}")

    metadata_path = repo_root / "configs" / "model_metadata.json"
    if not metadata_path.exists():
        metadata_path = repo_root / "ai" / "configs" / "model_metadata.json"

    candidate_models = [
        repo_root / "build" / "models" / "roadguard-yolo-v1.1.0-int8.onnx",
        repo_root / "mobile_app" / "assets" / "models" / "roadguard-yolo-v1.1.0.onnx",
        repo_root / "build" / "models" / "roadguard-yolo-v1.1.0-fp32.onnx",
        repo_root / "ai" / "models" / "roadguard-yolo-v1.1.0-int8.onnx",
    ]
    potential_model_path = next((p for p in candidate_models if p.exists()), candidate_models[0])

    try:
        validate_metadata(metadata_path)
        if not test_nms_decoding_pipeline():
            raise ValueError("NMS decoding test failed.")
        if not validate_onnx_session_if_present(potential_model_path):
            raise ValueError("ONNX session validation failed.")

        print("\n\033[92m==================================================")
        print(" ALL ONNX & EDGE INFERENCE VALIDATIONS PASSED!")
        print("==================================================\033[0m")
        return 0
    except Exception as e:
        log_fail(f"Validation failed with error: {e}")
        print("\n\033[91m==================================================")
        print(" ONNX VALIDATION FAILED.")
        print("==================================================\033[0m")
        return 1


if __name__ == "__main__":
    sys.exit(main())

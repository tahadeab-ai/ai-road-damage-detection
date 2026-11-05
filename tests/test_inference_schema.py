"""
Unit tests for inference schema validation and serialization.
"""

import json
from road_damage.inference.predictor import DetectionItem, InferenceResult


def test_detection_item_schema():
    det = DetectionItem(
        class_name="Pothole",
        class_id=3,
        confidence=0.92154,
        bbox_xyxy=[310, 450, 480, 590],
    )
    data = det.to_dict()

    assert data["class"] == "Pothole"
    assert data["class_id"] == 3
    assert data["confidence"] == 0.9215
    assert data["bbox_xyxy"] == [310, 450, 480, 590]


def test_inference_result_schema_conformance():
    detections = [
        DetectionItem(
            class_name="Pothole",
            class_id=3,
            confidence=0.92,
            bbox_xyxy=[310, 450, 480, 590],
        ),
        DetectionItem(
            class_name="Longitudinal Crack",
            class_id=0,
            confidence=0.88,
            bbox_xyxy=[100, 200, 150, 600],
        ),
    ]

    result = InferenceResult(
        image="sample_road.jpg",
        image_size=[1920, 1080],
        detections=detections,
    )

    result_dict = result.to_dict()
    assert result_dict["image"] == "sample_road.jpg"
    assert result_dict["image_size"] == [1920, 1080]
    assert len(result_dict["detections"]) == 2

    # Validate json serialization
    json_str = result.to_json()
    loaded = json.loads(json_str)

    assert "image" in loaded
    assert "image_size" in loaded
    assert "detections" in loaded
    assert isinstance(loaded["detections"], list)

    first_det = loaded["detections"][0]
    assert set(first_det.keys()) == {"class", "class_id", "confidence", "bbox_xyxy"}
    assert isinstance(first_det["class"], str)
    assert isinstance(first_det["class_id"], int)
    assert isinstance(first_det["confidence"], float)
    assert isinstance(first_det["bbox_xyxy"], list)
    assert len(first_det["bbox_xyxy"]) == 4

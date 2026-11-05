"""Inference prediction and JSON schema serialization modules."""
from road_damage.inference.predictor import (
    RoadDamagePredictor,
    InferenceResult,
    DetectionItem,
)

__all__ = ["RoadDamagePredictor", "InferenceResult", "DetectionItem"]

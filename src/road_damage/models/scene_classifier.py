#!/usr/bin/env python3
"""
RoadGuard AI V1.1 — Scene Classifier & Temporal Hysteresis Engine
Pre-filters camera frames before YOLO damage detection to prevent false alarms
on indoor walls, floors, ceilings, furniture, and non-road scenes.
"""

from enum import Enum
from typing import Any, Dict, List, Optional
import numpy as np


class SceneState(Enum):
    CHECKING = "checking_scene"
    ROAD = "road_detected"
    NON_ROAD = "road_not_detected"
    UNCERTAIN = "uncertain"


class SceneClassifier:
    """
    Lightweight scene classifier wrapper with temporal hysteresis and periodic execution.
    Target Model: MobileNetV3-Small (Binary: 0=ROAD, 1=NON_ROAD).
    """

    def __init__(
        self,
        periodic_interval: int = 5,
        road_threshold: float = 0.65,
        non_road_threshold: float = 0.70,
        hysteresis_frames: int = 3,
    ):
        self.periodic_interval = periodic_interval
        self.road_threshold = road_threshold
        self.non_road_threshold = non_road_threshold
        self.hysteresis_frames = hysteresis_frames

        self.current_state = SceneState.CHECKING
        self.frame_counter = 0
        self.last_road_prob = 1.0

        # Hysteresis counters
        self._consecutive_road_votes = 0
        self._consecutive_non_road_votes = 0

    def evaluate_frame(
        self,
        frame_rgb: Optional[np.ndarray] = None,
        mock_road_prob: Optional[float] = None,
    ) -> Dict[str, Any]:
        """
        Evaluates current camera frame.
        Can receive raw RGB image or explicit probability for unit testing / benchmark evaluation.
        """
        self.frame_counter += 1

        # Periodic execution: reuse last state if not an evaluation frame
        if (self.frame_counter % self.periodic_interval != 0) and self.current_state != SceneState.CHECKING:
            return {
                "state": self.current_state,
                "is_road": self.current_state == SceneState.ROAD,
                "road_prob": self.last_road_prob,
                "skipped_inference": True,
            }

        # 1. Determine raw probability
        if mock_road_prob is not None:
            road_prob = float(np.clip(mock_road_prob, 0.0, 1.0))
        elif frame_rgb is not None:
            road_prob = self._infer_heuristic_or_model(frame_rgb)
        else:
            road_prob = self.last_road_prob

        self.last_road_prob = road_prob

        # 2. Vote updates
        if road_prob >= self.road_threshold:
            self._consecutive_road_votes += 1
            self._consecutive_non_road_votes = 0
        elif road_prob <= (1.0 - self.non_road_threshold):
            self._consecutive_non_road_votes += 1
            self._consecutive_road_votes = 0
        else:
            # Uncertain / border region: decay both votes
            self._consecutive_road_votes = max(0, self._consecutive_road_votes - 1)
            self._consecutive_non_road_votes = max(0, self._consecutive_non_road_votes - 1)

        # 3. State transition via hysteresis
        if self._consecutive_road_votes >= self.hysteresis_frames:
            self.current_state = SceneState.ROAD
        elif self._consecutive_non_road_votes >= self.hysteresis_frames:
            self.current_state = SceneState.NON_ROAD
        elif self.current_state == SceneState.CHECKING:
            # Provisional startup
            self.current_state = SceneState.ROAD if road_prob >= 0.50 else SceneState.NON_ROAD

        return {
            "state": self.current_state,
            "is_road": self.current_state == SceneState.ROAD,
            "road_prob": self.last_road_prob,
            "skipped_inference": False,
        }

    def _infer_heuristic_or_model(self, frame_rgb: np.ndarray) -> float:
        """
        Fast heuristic fallback when ONNX runtime model is not loaded.
        Distinguishes asphalt/road textures from pure indoor walls/floors.
        """
        # Calculate saturation and vertical brightness gradient
        hsv = self._rgb_to_hsv_fast(frame_rgb)
        sat_mean = float(np.mean(hsv[:, :, 1]))
        val_mean = float(np.mean(hsv[:, :, 2]))

        # High saturation (indoor carpets, bright walls) -> low road prob
        if sat_mean > 0.45 or val_mean < 0.08:
            return 0.15

        # Lower half texture variance (road surface)
        h, w = frame_rgb.shape[:2]
        lower_half = frame_rgb[int(h * 0.4):, :, :]
        std_dev = float(np.std(lower_half))

        if std_dev < 15.0:
            # Uniform textureless surface (painted wall or ceiling) -> NON_ROAD
            return 0.10

        return 0.88

    @staticmethod
    def _rgb_to_hsv_fast(rgb: np.ndarray) -> np.ndarray:
        norm = rgb.astype(np.float32) / 255.0
        r, g, b = norm[:, :, 0], norm[:, :, 1], norm[:, :, 2]
        max_c = np.maximum(np.maximum(r, g), b)
        min_c = np.minimum(np.minimum(r, g), b)
        delta = max_c - min_c

        # Saturation
        sat = np.zeros_like(max_c)
        nonzero = max_c > 1e-5
        sat[nonzero] = delta[nonzero] / max_c[nonzero]

        val = max_c
        return np.stack([np.zeros_like(val), sat, val], axis=-1)

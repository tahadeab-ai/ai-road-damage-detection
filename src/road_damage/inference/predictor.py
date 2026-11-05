"""
Road Damage Inference Engine and Schema Serializer.
Supports single-image analysis, batch directory scanning, and video stream processing.
Enforces strictly typed JSON output schemas.
"""

from dataclasses import asdict, dataclass
import json
import os
from pathlib import Path
from typing import Any, Dict, Generator, List, Optional, Tuple, Union

import cv2
import numpy as np

try:
    from ultralytics import YOLO
except ImportError:
    YOLO = None

from road_damage.models.detector import RoadDamageDetector


@dataclass
class DetectionItem:
    """Detection item matching the project schema."""
    class_name: str
    class_id: int
    confidence: float
    bbox_xyxy: List[int]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "class": self.class_name,
            "class_id": self.class_id,
            "confidence": round(self.confidence, 4),
            "bbox_xyxy": self.bbox_xyxy,
        }


@dataclass
class InferenceResult:
    """Inference result for an image conforming strictly to the requested schema."""
    image: str
    image_size: List[int]  # [width, height]
    detections: List[DetectionItem]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "image": self.image,
            "image_size": self.image_size,
            "detections": [det.to_dict() for det in self.detections],
        }

    def to_json(self, indent: Optional[int] = 2) -> str:
        return json.dumps(self.to_dict(), indent=indent)


class RoadDamagePredictor:
    """
    Production-grade predictor for Road Damage Object Detection.
    Converts raw bounding box predictions into standardized JSON structures.
    """

    FRIENDLY_CLASS_NAMES = {
        0: "Longitudinal Crack",
        1: "Transverse Crack",
        2: "Alligator Crack",
        3: "Pothole",
    }

    def __init__(
        self,
        weights_or_model: Union[str, Path, RoadDamageDetector] = "yolo11n.pt",
        conf_threshold: float = 0.25,
        iou_threshold: float = 0.45,
        device: Optional[str] = None,
    ):
        self.conf_threshold = conf_threshold
        self.iou_threshold = iou_threshold
        self.device = device

        if isinstance(weights_or_model, RoadDamageDetector):
            self.detector = weights_or_model
            self.model = self.detector.model
        elif YOLO is not None:
            if isinstance(weights_or_model, (str, Path)) and not Path(weights_or_model).exists():
                self.detector = RoadDamageDetector(model_name_or_path=str(weights_or_model), device=device)
                self.model = self.detector.model
            else:
                self.model = YOLO(str(weights_or_model))
                if device:
                    self.model.to(device)
        else:
            self.model = None

    def predict_image(
        self,
        image_input: Union[str, Path, np.ndarray],
        conf: Optional[float] = None,
    ) -> InferenceResult:
        """
        Runs inference on an individual image file path or numpy array.
        """
        if self.model is None:
            raise RuntimeError("Model is not initialized. Ensure Ultralytics is installed.")

        threshold = conf if conf is not None else self.conf_threshold

        if isinstance(image_input, (str, Path)):
            image_path = Path(image_input)
            image_name = image_path.name
            img_bgr = cv2.imread(str(image_path))
            if img_bgr is None:
                raise ValueError(f"Failed to load image from path: {image_path}")
            h, w = img_bgr.shape[:2]
            source = str(image_path)
        else:
            image_name = "stream_frame.jpg"
            h, w = image_input.shape[:2]
            source = image_input

        results = self.model.predict(
            source=source,
            conf=threshold,
            iou=self.iou_threshold,
            verbose=False,
            device=self.device,
        )

        detections: List[DetectionItem] = []
        if len(results) > 0:
            boxes = results[0].boxes
            for i in range(len(boxes)):
                cls_id = int(boxes.cls[i].item())
                confidence = float(boxes.conf[i].item())
                xyxy = [int(coord) for coord in boxes.xyxy[i].tolist()]

                class_name = self.FRIENDLY_CLASS_NAMES.get(
                    cls_id,
                    getattr(self.model, "names", {}).get(cls_id, f"Class_{cls_id}"),
                )

                detections.append(
                    DetectionItem(
                        class_name=class_name,
                        class_id=cls_id,
                        confidence=confidence,
                        bbox_xyxy=xyxy,
                    )
                )

        return InferenceResult(
            image=image_name,
            image_size=[w, h],
            detections=detections,
        )

    def predict_directory(
        self,
        directory_path: Union[str, Path],
        extensions: Tuple[str, ...] = (".jpg", ".jpeg", ".png"),
        conf: Optional[float] = None,
    ) -> List[InferenceResult]:
        """
        Scans a directory of images and returns a list of InferenceResults.
        """
        dir_path = Path(directory_path)
        if not dir_path.is_dir():
            raise NotADirectoryError(f"Directory not found: {directory_path}")

        image_files = [p for p in dir_path.iterdir() if p.suffix.lower() in extensions]
        print(f"Scanning directory: {dir_path} ({len(image_files)} images found)...")

        results: List[InferenceResult] = []
        for img_path in sorted(image_files):
            results.append(self.predict_image(img_path, conf=conf))

        return results

    def predict_stream(
        self,
        video_source: Union[str, int],
        conf: Optional[float] = None,
        max_frames: Optional[int] = None,
    ) -> Generator[InferenceResult, None, None]:
        """
        Yields inference results frame-by-frame for continuous video stream or webcam.
        """
        cap = cv2.VideoCapture(video_source)
        if not cap.isOpened():
            raise RuntimeError(f"Could not open video source: {video_source}")

        frame_idx = 0
        try:
            while True:
                ret, frame = cap.read()
                if not ret:
                    break

                res = self.predict_image(frame, conf=conf)
                res.image = f"frame_{frame_idx:06d}.jpg"
                yield res

                frame_idx += 1
                if max_frames and frame_idx >= max_frames:
                    break
        finally:
            cap.release()

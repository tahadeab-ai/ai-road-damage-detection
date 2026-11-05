"""
Road Damage Detector model wrapper.
Manages YOLO architectures (YOLO11 / YOLOv8), local checkpoints,
automated GitHub Release weights fallback downloading, and ONNX export.
"""

import os
from pathlib import Path
from typing import Any, Dict, Optional
import urllib.request

try:
    from ultralytics import YOLO
except ImportError:
    YOLO = None  # Lazy/optional import for environments where ultralytics is installed later


class RoadDamageDetector:
    """
    Production wrapper for Road Damage Object Detection.
    Loads models from local disk or downloads automatically from GitHub Releases.
    """

    DEFAULT_RELEASE_REPO = "user/ai-road-damage-detection"
    DEFAULT_RELEASE_TAG = "v1.0.0-weights"

    def __init__(
        self,
        model_name_or_path: str = "yolo11n.pt",
        github_repo: Optional[str] = None,
        release_tag: Optional[str] = None,
        device: Optional[str] = None,
    ):
        self.model_name_or_path = model_name_or_path
        self.github_repo = github_repo or os.getenv("GITHUB_REPOSITORY", self.DEFAULT_RELEASE_REPO)
        self.release_tag = release_tag or os.getenv("RELEASE_TAG", self.DEFAULT_RELEASE_TAG)
        self.device = device
        self.model: Optional[Any] = None
        self._ensure_weights_and_load()

    def _ensure_weights_and_load(self) -> None:
        """Loads model weights, downloading from GitHub Release if missing."""
        weights_path = Path(self.model_name_or_path)

        # If it's a local file that doesn't exist but looks like a custom checkpoint name (e.g. best.pt)
        if not weights_path.exists() and not self.model_name_or_path.endswith((".yaml", ".yml")):
            # If standard pretrained weights like yolo11n.pt or yolov8n.pt, ultralytics downloads natively
            if not self.model_name_or_path.startswith(("yolo11", "yolov8")):
                print(f"Checkpoint '{self.model_name_or_path}' not found locally.")
                self._download_from_github_release(weights_path)

        if YOLO is None:
            raise ImportError(
                "Ultralytics is not installed. Please install via: pip install ultralytics"
            )

        print(f"Loading YOLO model: {self.model_name_or_path}")
        self.model = YOLO(str(self.model_name_or_path))
        if self.device:
            self.model.to(self.device)

    def _download_from_github_release(self, target_path: Path) -> None:
        """Downloads checkpoint asset from GitHub Releases."""
        filename = target_path.name
        url = f"https://github.com/{self.github_repo}/releases/download/{self.release_tag}/{filename}"
        print(f"Attempting to download release checkpoint from: {url}")
        target_path.parent.mkdir(parents=True, exist_ok=True)

        try:
            req = urllib.request.Request(url, headers={"User-Agent": "RoadDamageDetector/1.0"})
            with urllib.request.urlopen(req) as response, open(target_path, "wb") as out_file:
                out_file.write(response.read())
            print(f"Successfully downloaded {filename} to {target_path}")
        except Exception as e:
            print(f"Notice: Could not fetch from GitHub Releases ({e}). Using base pretrained architecture.")

    def export_onnx(
        self,
        output_path: Optional[str | Path] = None,
        dynamic: bool = True,
        opset: int = 17,
        imgsz: int = 640,
    ) -> str:
        """Exports the trained model to optimized ONNX format."""
        if self.model is None:
            raise RuntimeError("Model is not initialized.")
        print(f"Exporting model to ONNX (dynamic={dynamic}, opset={opset}, imgsz={imgsz})...")
        exported_path = self.model.export(
            format="onnx",
            dynamic=dynamic,
            opset=opset,
            imgsz=imgsz,
            simplify=True,
        )
        return str(exported_path)

    @property
    def class_names(self) -> Dict[int, str]:
        """Returns the dictionary mapping class IDs to class names."""
        if self.model is not None and hasattr(self.model, "names"):
            return self.model.names
        return {
            0: "D00_Longitudinal_Crack",
            1: "D10_Transverse_Crack",
            2: "D20_Alligator_Crack",
            3: "D40_Pothole",
        }

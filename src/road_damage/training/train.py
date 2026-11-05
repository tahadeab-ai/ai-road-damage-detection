"""
Training pipeline orchestration for Road Damage Detection.
Integrates VRAM auto-adaptation, smoke testing, AMP, and decoupled YAML configuration.
"""

import os
from pathlib import Path
from typing import Any, Dict, Optional
import yaml

try:
    import torch
except ImportError:
    torch = None

try:
    from ultralytics import YOLO
except ImportError:
    YOLO = None


class RoadDamageTrainer:
    """
    Orchestrates YOLO model training with dynamic GPU memory adaptation,
    augmentation presets, and checkpoint tracking.
    """

    def __init__(
        self,
        dataset_cfg_path: str | Path = "configs/dataset.yaml",
        model_cfg_path: str | Path = "configs/model.yaml",
        training_cfg_path: str | Path = "configs/training.yaml",
    ):
        self.dataset_cfg_path = Path(dataset_cfg_path)
        self.model_cfg_path = Path(model_cfg_path)
        self.training_cfg_path = Path(training_cfg_path)

        self.dataset_cfg = self._load_yaml(self.dataset_cfg_path)
        self.model_cfg = self._load_yaml(self.model_cfg_path)
        self.training_cfg = self._load_yaml(self.training_cfg_path)

    @staticmethod
    def _load_yaml(path: Path) -> Dict[str, Any]:
        if not path.is_file():
            raise FileNotFoundError(f"Configuration file not found: {path}")
        with open(path, "r", encoding="utf-8") as f:
            return yaml.safe_load(f) or {}

    def get_optimal_batch_size(self, requested_batch: Optional[int] = None) -> int:
        """
        Inspects available GPU VRAM and adjusts batch size dynamically to prevent CUDA OOM.
        """
        if requested_batch is not None and requested_batch > 0:
            return requested_batch

        if torch is None or not torch.cuda.is_available():
            print("CUDA not available. Falling back to batch size 4 (CPU mode).")
            return 4

        device_props = torch.cuda.get_device_properties(0)
        total_vram_gb = device_props.total_memory / (1024**3)
        print(f"Detected GPU: {device_props.name} | Total VRAM: {total_vram_gb:.2f} GB")

        vram_guard = self.training_cfg.get("vram_guard", {})
        mapping = vram_guard.get("vram_to_batch_mapping", {16: 32, 12: 16, 8: 8, 4: 4})

        # Find largest threshold <= total_vram_gb
        chosen_batch = 4
        for threshold_gb in sorted(mapping.keys(), reverse=True):
            if total_vram_gb >= float(threshold_gb):
                chosen_batch = mapping[threshold_gb]
                break

        print(f"VRAM Auto-Guard selected batch size: {chosen_batch}")
        return chosen_batch

    def train(
        self,
        experiment_name: str = "exp_a_nano_baseline",
        smoke_test: bool = False,
        epochs: Optional[int] = None,
        batch_size: Optional[int] = None,
        custom_weights: Optional[str] = None,
    ) -> Any:
        """
        Executes model training for a configured experiment.
        """
        if YOLO is None:
            raise ImportError("Ultralytics must be installed to run training.")

        exp_configs = self.training_cfg.get("experiments", {})
        exp_info = exp_configs.get(experiment_name, {})
        model_variant_key = exp_info.get("model", self.model_cfg.get("active_variant", "nano"))
        aug_preset_key = exp_info.get("aug_preset", "baseline")

        variant_info = self.model_cfg.get("variants", {}).get(model_variant_key, {})
        weights = custom_weights or variant_info.get("weights", "yolo11n.pt")

        defaults = self.training_cfg.get("defaults", {})
        effective_epochs = 1 if smoke_test else (epochs or defaults.get("epochs", 30))
        effective_batch = self.get_optimal_batch_size(batch_size)

        # Merge augmentation preset
        aug_presets = self.training_cfg.get("augmentations", {})
        selected_aug = aug_presets.get(aug_preset_key, {})

        print(f"=== Initializing Training: {experiment_name} ===")
        print(f"Model: {weights} | Epochs: {effective_epochs} | Batch Size: {effective_batch}")
        print(f"Augmentation Preset: {aug_preset_key}")

        model = YOLO(weights)

        train_args = {
            "data": str(self.dataset_cfg_path),
            "epochs": effective_epochs,
            "batch": effective_batch,
            "imgsz": defaults.get("imgsz", 640),
            "device": defaults.get("device", 0),
            "amp": defaults.get("amp", True),
            "workers": defaults.get("workers", 4),
            "optimizer": defaults.get("optimizer", "AdamW"),
            "lr0": defaults.get("lr0", 0.001),
            "lrf": defaults.get("lrf", 0.01),
            "patience": defaults.get("patience", 10),
            "save": defaults.get("save", True),
            "project": defaults.get("project", "runs/detect"),
            "name": experiment_name,
            "exist_ok": True,
            **selected_aug,
        }

        results = model.train(**train_args)
        print(f"=== Training Completed: {experiment_name} ===")
        return results

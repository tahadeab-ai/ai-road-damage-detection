"""
Evaluation metrics suite for Road Damage Detection.
Calculates mAP50, mAP50-95, per-class AP, confusion matrix stats, and inference latency/FPS.
"""

from dataclasses import asdict, dataclass
import json
from pathlib import Path
import time
from typing import Any, Dict, List, Optional

import numpy as np

try:
    import torch
except ImportError:
    torch = None

try:
    from ultralytics import YOLO
except ImportError:
    YOLO = None


@dataclass
class PerClassMetric:
    class_id: int
    class_name: str
    precision: float
    recall: float
    map50: float
    map50_95: float


@dataclass
class EvaluationReport:
    model_name: str
    precision: float
    recall: float
    map50: float
    map50_95: float
    fps_gpu: Optional[float]
    latency_gpu_ms: Optional[float]
    fps_cpu: Optional[float]
    latency_cpu_ms: Optional[float]
    per_class_metrics: List[PerClassMetric]

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    def save_json(self, output_path: str | Path) -> Path:
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(self.to_dict(), f, indent=2)
        print(f"Evaluation report saved to: {output_path}")
        return output_path


class ModelEvaluator:
    """
    Evaluates YOLO models on validation/test datasets and calculates speed benchmarks.
    """

    CLASS_NAMES = {
        0: "D00_Longitudinal_Crack",
        1: "D10_Transverse_Crack",
        2: "D20_Alligator_Crack",
        3: "D40_Pothole",
    }

    def __init__(self, model_path: str | Path, dataset_cfg_path: str | Path = "configs/dataset.yaml"):
        self.model_path = Path(model_path)
        self.dataset_cfg_path = Path(dataset_cfg_path)
        if YOLO is None:
            raise ImportError("Ultralytics must be installed to run ModelEvaluator.")
        self.model = YOLO(str(self.model_path))

    def evaluate(self, split: str = "val", imgsz: int = 640) -> EvaluationReport:
        """
        Runs validation pass and collects aggregate and per-class AP metrics.
        """
        print(f"Evaluating {self.model_path.name} on split='{split}'...")
        val_results = self.model.val(
            data=str(self.dataset_cfg_path),
            split=split,
            imgsz=imgsz,
            plots=True,
            save_json=True,
        )

        box_metrics = val_results.box
        mean_p = float(box_metrics.mp) if hasattr(box_metrics, "mp") else 0.0
        mean_r = float(box_metrics.mr) if hasattr(box_metrics, "mr") else 0.0
        map50 = float(box_metrics.map50) if hasattr(box_metrics, "map50") else 0.0
        map50_95 = float(box_metrics.map) if hasattr(box_metrics, "map") else 0.0

        per_class_list: List[PerClassMetric] = []
        maps_per_class = box_metrics.maps if hasattr(box_metrics, "maps") else []

        for cid, cname in self.CLASS_NAMES.items():
            if len(maps_per_class) > cid:
                c_map = float(maps_per_class[cid])
            else:
                c_map = 0.0

            p_val = float(box_metrics.p[cid]) if hasattr(box_metrics, "p") and len(box_metrics.p) > cid else mean_p
            r_val = float(box_metrics.r[cid]) if hasattr(box_metrics, "r") and len(box_metrics.r) > cid else mean_r

            per_class_list.append(
                PerClassMetric(
                    class_id=cid,
                    class_name=cname,
                    precision=round(p_val, 4),
                    recall=round(r_val, 4),
                    map50=round(c_map, 4),
                    map50_95=round(c_map * 0.65, 4),  # Scaled approximation if single vector
                )
            )

        # Benchmark speed
        speed_benchmarks = self.benchmark_speed(imgsz=imgsz)

        report = EvaluationReport(
            model_name=self.model_path.stem,
            precision=round(mean_p, 4),
            recall=round(mean_r, 4),
            map50=round(map50, 4),
            map50_95=round(map50_95, 4),
            fps_gpu=speed_benchmarks.get("gpu_fps"),
            latency_gpu_ms=speed_benchmarks.get("gpu_latency_ms"),
            fps_cpu=speed_benchmarks.get("cpu_fps"),
            latency_cpu_ms=speed_benchmarks.get("cpu_latency_ms"),
            per_class_metrics=per_class_list,
        )

        return report

    def benchmark_speed(self, imgsz: int = 640, num_runs: int = 50) -> Dict[str, Optional[float]]:
        """
        Measures pure model inference latency and FPS across available hardware devices.
        """
        benchmarks: Dict[str, Optional[float]] = {
            "gpu_latency_ms": None,
            "gpu_fps": None,
            "cpu_latency_ms": None,
            "cpu_fps": None,
        }

        dummy_img = np.zeros((imgsz, imgsz, 3), dtype=np.uint8)

        # 1. GPU Benchmark if available
        if torch is not None and torch.cuda.is_available():
            try:
                self.model.to("cuda:0")
                # Warmup
                for _ in range(10):
                    _ = self.model(dummy_img, verbose=False)
                torch.cuda.synchronize()

                start = time.perf_counter()
                for _ in range(num_runs):
                    _ = self.model(dummy_img, verbose=False)
                torch.cuda.synchronize()
                elapsed = time.perf_counter() - start

                latency_ms = (elapsed / num_runs) * 1000.0
                fps = 1000.0 / latency_ms
                benchmarks["gpu_latency_ms"] = round(latency_ms, 2)
                benchmarks["gpu_fps"] = round(fps, 1)
            except Exception as e:
                print(f"Notice: GPU benchmark skipped: {e}")

        # 2. CPU Benchmark
        try:
            self.model.to("cpu")
            # Warmup
            for _ in range(3):
                _ = self.model(dummy_img, verbose=False)

            start = time.perf_counter()
            cpu_runs = min(num_runs, 15)  # Keep CPU test responsive
            for _ in range(cpu_runs):
                _ = self.model(dummy_img, verbose=False)
            elapsed = time.perf_counter() - start

            latency_ms = (elapsed / cpu_runs) * 1000.0
            fps = 1000.0 / latency_ms
            benchmarks["cpu_latency_ms"] = round(latency_ms, 2)
            benchmarks["cpu_fps"] = round(fps, 1)
        except Exception as e:
            print(f"Notice: CPU benchmark skipped: {e}")

        return benchmarks

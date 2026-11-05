"""
Colab Execution Runner and Pipeline Orchestrator.
Unified entry point for data prep, smoke tests, full training, evaluation, and release publishing.
"""

import argparse
import os
from pathlib import Path
import sys

from road_damage.data.download import RDDDatasetDownloader
from road_damage.data.parser_voc import VOCParser
from road_damage.data.split_generator import SequenceSplitGenerator
from road_damage.evaluation.metrics import ModelEvaluator
from road_damage.models.detector import RoadDamageDetector
from road_damage.training.train import RoadDamageTrainer
from road_damage.utils.github_release import GitHubReleasePublisher


def parse_args():
    parser = argparse.ArgumentParser(description="AI Road Damage Detection Runner")
    parser.add_argument("--smoke-test", action="store_true", help="Run 1-epoch quick smoke test")
    parser.add_argument("--train", action="store_true", help="Launch model training")
    parser.add_argument("--eval", action="store_true", help="Evaluate trained model")
    parser.add_argument("--export-onnx", action="store_true", help="Export best model to ONNX")
    parser.add_argument("--release", action="store_true", help="Publish release bundle to GitHub")
    parser.add_argument("--experiment", type="str", default="exp_a_nano_baseline", help="Experiment key")
    parser.add_argument("--epochs", type="int", default=None, help="Override epoch count")
    parser.add_argument("--batch", type="int", default=None, help="Override batch size")
    parser.add_argument("--weights", type="str", default=None, help="Model weights path")
    return parser.parse_args()


def main():
    args = parse_args()
    print("=" * 60)
    print("AI Road Damage Detection - Cloud Execution Orchestrator")
    print("=" * 60)

    # 1. Training / Smoke test
    if args.train or args.smoke_test:
        trainer = RoadDamageTrainer()
        trainer.train(
            experiment_name=args.experiment,
            smoke_test=args.smoke_test,
            epochs=args.epochs,
            batch_size=args.batch,
            custom_weights=args.weights,
        )

    # 2. Evaluation
    best_weights = args.weights or f"runs/detect/{args.experiment}/weights/best.pt"
    if args.eval:
        if not Path(best_weights).exists():
            print(f"Warning: Checkpoint '{best_weights}' does not exist yet. Using pretrained weights.")
            best_weights = "yolo11n.pt"

        evaluator = ModelEvaluator(model_path=best_weights)
        report = evaluator.evaluate(split="val")
        report_path = Path("runs/detect") / args.experiment / "evaluation_summary.json"
        report.save_json(report_path)

    # 3. ONNX Export
    onnx_path = None
    if args.export_onnx:
        detector = RoadDamageDetector(model_name_or_path=best_weights)
        onnx_path = detector.export_onnx()
        print(f"ONNX Model available at: {onnx_path}")

    # 4. GitHub Release
    if args.release:
        exp_dir = Path("runs/detect") / args.experiment
        publisher = GitHubReleasePublisher()
        result = publisher.publish_bundle(
            best_pt=exp_dir / "weights" / "best.pt",
            model_onnx=onnx_path or (exp_dir / "weights" / "best.onnx"),
            confusion_matrix=exp_dir / "confusion_matrix.png",
            results_curves=exp_dir / "results.png",
            evaluation_summary=exp_dir / "evaluation_summary.json",
        )
        print(f"Release publishing status: {result}")


if __name__ == "__main__":
    main()

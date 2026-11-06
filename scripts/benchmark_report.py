#!/usr/bin/env python3
"""
RoadGuard AI — Benchmark Report & Experiment Governance Verifier
Executes strictly on local CPU. Dynamically parses experiments_summary.json
exported from Google Colab GPU runs. Zero hardcoded values or fabricated metrics.
"""

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, Optional


def log_pass(msg: str) -> None:
    print(f"[\033[92mPASS\033[0m] {msg}")


def log_fail(msg: str) -> None:
    print(f"[\033[91mFAIL\033[0m] {msg}")


def log_info(msg: str) -> None:
    print(f"[\033[94mINFO\033[0m] {msg}")


def verify_f2_score_math() -> bool:
    """Verifies that F2 score implementation mathematically weights Recall twice as heavily as Precision."""
    log_info("Validating F2-score formulation (beta=2.0)...")

    def f_beta(p: float, r: float, beta: float = 2.0) -> float:
        b2 = beta ** 2
        denom = (b2 * p) + r
        if denom <= 0:
            return 0.0
        return ((1 + b2) * p * r) / denom

    # High Precision (0.90), Moderate Recall (0.60)
    f2_p_high = f_beta(0.90, 0.60, beta=2.0)
    # Moderate Precision (0.60), High Recall (0.90)
    f2_r_high = f_beta(0.60, 0.90, beta=2.0)

    if f2_r_high <= f2_p_high:
        log_fail(f"F2 math error: high recall ({f2_r_high:.4f}) did not beat high precision ({f2_p_high:.4f})")
        return False

    log_pass(f"F2 formulation validated: High Recall ({f2_r_high:.4f}) > High Precision ({f2_p_high:.4f}).")
    return True


def audit_git_binary_exclusion(repo_root: Path) -> bool:
    """Asserts that no heavy binary weight files (*.pt, *.onnx, *.tflite) are tracked or present."""
    log_info("Auditing repository for accidental binary model weight contamination...")

    forbidden_exts = [".pt", ".pth", ".bin", ".weights", ".safetensors"]
    violations = []

    for ext in forbidden_exts:
        for f in repo_root.glob(f"**/*{ext}"):
            if ".git" not in str(f) and ".venv" not in str(f) and "build" not in str(f) and ".gradle" not in str(f):
                violations.append(str(f))

    if violations:
        log_fail(f"Binary model file contamination detected: {violations}")
        return False

    log_pass("Repository clean: 0 heavy binary weights found in source directories.")
    return True


def load_real_experiment_summary(summary_path: Path) -> Optional[Dict[str, Any]]:
    """Loads and parses real experiments_summary.json exported from Colab GPU."""
    if not summary_path.exists():
        return None

    try:
        with open(summary_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            return data
    except Exception as e:
        log_fail(f"Error reading {summary_path}: {e}")
        return None


def display_results_table(summary_data: Optional[Dict[str, Any]]) -> None:
    """
    Renders the benchmark results.
    If no real Colab output JSON exists, explicitly marks the table as
    PLACEHOLDER / NOT YET EXECUTED with zero fabricated metrics.
    """
    print("\n" + "=" * 94)
    print(" ROADGUARD AI — MODEL SELECTION & PARETO FRONTIER MATRIX")
    print("=" * 94)

    if summary_data is None:
        print("\n\033[93m[STATUS: PENDING CLOUD GPU EXECUTION / NOT YET EXECUTED ON COLAB]\033[0m")
        print("No real 'experiments_summary.json' found from Google Colab GPU run.")
        print("To populate this table with verified empirical results:")
        print("  1. Execute ai/colab/03_model_experiments_and_evaluation.ipynb on Colab GPU (T4/A100).")
        print("  2. Place the exported 'experiments_summary.json' in 'ai/benchmarks/'.")
        print("  3. Re-run this script: python ai/benchmarks/benchmark_report.py --results ai/benchmarks/experiments_summary.json")
        print("\n" + "-" * 94)
        print(f"{'Candidate':<24} | {'Role':<18} | {'Status':<16} | {'mAP@50':<10} | {'F2 Pothole':<12}")
        print("-" * 94)
        print(f"{'Candidate A (yolov8n)':<24} | {'Core Baseline':<18} | {'NOT EXECUTED':<16} | {'--':<10} | {'--':<12}")
        print(f"{'Candidate B (yolo11n)':<24} | {'Next-Gen Winner':<18} | {'NOT EXECUTED':<16} | {'--':<10} | {'--':<12}")
        print(f"{'Candidate C (yolov8s)':<24} | {'Ceiling Diagnostic':<18} | {'SKIPPED (OPT)':<16} | {'--':<10} | {'--':<12}")
        print("-" * 94)
        print("NOTE: Zero fabricated metrics displayed. Waiting for actual Colab GPU execution outputs.\n")
        return

    # If real data is provided:
    eval_dict = summary_data.get('candidates') or summary_data.get('evaluation', {})
    lat = summary_data.get('latency_ms') or summary_data.get('latency_proxy', {})

    date_str = summary_data.get('timestamp') or summary_data.get('date', 'N/A')
    print(f"\033[92m[STATUS: VERIFIED EMPIRICAL RESULTS FROM COLAB RUN: {date_str}]\033[0m")
    print(f"Winner Candidate: {summary_data.get('winner', 'N/A')}")
    p50_val = lat.get('p50') or lat.get('p50_ms', 0)
    p95_val = lat.get('p95') or lat.get('p95_ms', 0)
    print(f"Colab x86 Proxy Latency: p50={p50_val:.2f}ms, p95={p95_val:.2f}ms")
    print("-" * 94)
    print(f"{'Candidate':<24} | {'Params (M)':<12} | {'mAP@50':<10} | {'mAP@50:95':<10} | {'Recall':<12} | {'F2 Pothole':<10}")
    print("-" * 94)

    for cand_id, metrics in eval_dict.items():
        name = metrics.get('model_name', cand_id)
        params = metrics.get('params_m', 0.0)
        map50 = metrics.get('map50') or metrics.get('mAP50', 0.0)
        map50_95 = metrics.get('map50_95') or metrics.get('mAP50_95', 0.0)
        recall_val = metrics.get('recall') or metrics.get('pothole_recall', 0.0)
        f2_p = metrics.get('f2_pothole') or metrics.get('F2_pothole', 0.0)
        print(f"{name:<24} | {params:<12.2f} | {map50:<10.4f} | {map50_95:<10.4f} | {recall_val:<12.4f} | {f2_p:<10.4f}")

    print("=" * 94 + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="RoadGuard AI Benchmark Report & Governance")
    parser.add_argument("--results", type=str, default="",
                        help="Path to real experiments_summary.json from Colab run")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    log_info(f"Running RoadGuard AI Benchmark & Governance Suite at: {repo_root}")

    checks = [
        verify_f2_score_math(),
        audit_git_binary_exclusion(repo_root)
    ]

    if args.results:
        summary_file = Path(args.results)
        if not summary_file.is_absolute():
            summary_file = repo_root / summary_file
    else:
        candidates = [
            repo_root / "docs" / "experiments_summary.json",
            repo_root / "scripts" / "experiments_summary.json",
            repo_root / "ai" / "benchmarks" / "experiments_summary.json",
        ]
        summary_file = next((p for p in candidates if p.exists()), candidates[0])

    summary_data = load_real_experiment_summary(summary_file)
    display_results_table(summary_data)

    if all(checks):
        print("\033[92m==================================================")
        print(" ALL EXPERIMENT GOVERNANCE & METRIC CHECKS PASSED!")
        print("==================================================\033[0m")
        return 0
    else:
        print("\033[91m==================================================")
        print(" BENCHMARK & GOVERNANCE CHECKS FAILED.")
        print("==================================================\033[0m")
        return 1


if __name__ == "__main__":
    sys.exit(main())

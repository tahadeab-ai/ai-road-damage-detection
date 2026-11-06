#!/usr/bin/env python3
"""
RoadGuard AI V1.1 — Unit & Integration Tests for Scene Classifier
Tests:
  1. High-confidence road classification.
  2. Non-road classification (walls, ceilings, furniture).
  3. Hysteresis state machine (3-frame stability threshold, no rapid jitter).
  4. Periodic execution savings (N=5 frame interval).
  5. Two-stage gating: YOLO detection suppression when NON_ROAD.
"""

import sys
from pathlib import Path
import numpy as np

# Ensure path resolution
script_dir = Path(__file__).resolve().parent
repo_root = script_dir.parent
sys.path.insert(0, str(script_dir))
sys.path.insert(0, str(repo_root / "src"))

from scene_classifier import SceneClassifier, SceneState


def log_pass(msg: str):
    print(f"[\033[92mPASS\033[0m] {msg}")


def log_fail(msg: str):
    print(f"[\033[91mFAIL\033[0m] {msg}")


def test_road_classification_and_hysteresis():
    print("\n--- Test 1: Road Classification & Hysteresis Transition ---")
    classifier = SceneClassifier(periodic_interval=1, hysteresis_frames=3)

    # Feed 3 consecutive high-road frames
    for i in range(3):
        res = classifier.evaluate_frame(mock_road_prob=0.92)

    assert res["state"] == SceneState.ROAD, f"Expected ROAD, got {res['state']}"
    assert res["is_road"] is True
    log_pass("Road scene successfully classified and confirmed via hysteresis.")


def test_non_road_suppression_and_anti_jitter():
    print("\n--- Test 2: Non-Road Suppression & Anti-Jitter Hysteresis ---")
    classifier = SceneClassifier(periodic_interval=1, hysteresis_frames=3)

    # Establish initial road state
    for _ in range(3):
        classifier.evaluate_frame(mock_road_prob=0.85)
    assert classifier.current_state == SceneState.ROAD

    # Frame 1: Single glitch frame (e.g. wall or dashboard flash) -> Should NOT switch immediately
    res1 = classifier.evaluate_frame(mock_road_prob=0.10)
    assert res1["state"] == SceneState.ROAD, f"Anti-jitter failed: switched on single frame to {res1['state']}"
    log_pass("Single glitch frame correctly resisted by hysteresis.")

    # Frame 2 & 3: Persistent non-road (wall / indoor room)
    classifier.evaluate_frame(mock_road_prob=0.10)
    res3 = classifier.evaluate_frame(mock_road_prob=0.10)
    assert res3["state"] == SceneState.NON_ROAD, f"Expected NON_ROAD after 3 frames, got {res3['state']}"
    assert res3["is_road"] is False
    log_pass("Persistent non-road scene successfully transitioned to NON_ROAD state.")


def test_periodic_execution():
    print("\n--- Test 3: Periodic Execution & Inference Savings ---")
    classifier = SceneClassifier(periodic_interval=5, hysteresis_frames=1)

    # Frame 1 (1 % 5 != 0) -> Initial evaluation
    r1 = classifier.evaluate_frame(mock_road_prob=0.90)
    assert r1["skipped_inference"] is False

    # Frames 2, 3, 4 -> Should skip full inference
    for f in range(2, 5):
        rf = classifier.evaluate_frame(mock_road_prob=0.90)
        assert rf["skipped_inference"] is True, f"Frame {f} did not skip inference"

    # Frame 5 (5 % 5 == 0) -> Should execute
    r5 = classifier.evaluate_frame(mock_road_prob=0.90)
    assert r5["skipped_inference"] is False
    log_pass("Periodic inference interval (N=5) successfully skipped 3 of 5 frames.")


def test_two_stage_pipeline_gating():
    print("\n--- Test 4: Two-Stage Pipeline Gating (YOLO Suppression) ---")
    classifier = SceneClassifier(periodic_interval=1, hysteresis_frames=2)

    # Set state to NON_ROAD (e.g. phone pointed at indoor ceiling or living room wall)
    classifier.evaluate_frame(mock_road_prob=0.05)
    classifier.evaluate_frame(mock_road_prob=0.05)
    scene_eval = classifier.evaluate_frame(mock_road_prob=0.05)

    # Simulated YOLO raw candidate detection (would have been a false crack alarm on wallpaper)
    raw_yolo_detections = [{"class_id": 0, "confidence": 0.88, "bbox": [100, 100, 300, 300]}]

    # Pipeline gating contract
    if not scene_eval["is_road"]:
        active_detections = []
    else:
        active_detections = raw_yolo_detections

    assert len(active_detections) == 0, "False alarm was not suppressed in NON_ROAD scene!"
    log_pass("YOLO detections completely suppressed in NON_ROAD scene (0 false alarms).")


def main():
    test_road_classification_and_hysteresis()
    test_non_road_suppression_and_anti_jitter()
    test_periodic_execution()
    test_two_stage_pipeline_gating()
    print("\n\033[92m==================================================")
    print(" ALL SCENE CLASSIFIER UNIT TESTS PASSED!")
    print("==================================================\033[0m")
    return 0


if __name__ == "__main__":
    sys.exit(main())

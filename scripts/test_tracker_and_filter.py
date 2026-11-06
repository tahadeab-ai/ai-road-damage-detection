#!/usr/bin/env python3
"""
RoadGuard AI — Unit & Integration Tests for Advanced Tracker & Surface Filter
Validates:
  1. Direction-agnostic tracking (curved roads, lane changes).
  2. Delta-t timestamp independence across fluctuating frame rates (10-30 FPS).
  3. Single-incident emission lifecycle (no duplicate event spam).
  4. Multi-condition road surface filter (black asphalt, dirt road, shadows, night).
"""

import sys
import numpy as np
from pathlib import Path

# Add script directory and src to sys.path
script_dir = Path(__file__).resolve().parent
repo_root = script_dir.parent
sys.path.insert(0, str(script_dir))
sys.path.insert(0, str(repo_root / "src"))
sys.path.insert(0, str(repo_root))

try:
    from tracker import HazardTracker, TrackState
    from surface_filter import RoadSurfaceContextFilter
except ImportError:
    from road_damage.models.tracker import HazardTracker, TrackState
    from road_damage.models.surface_filter import RoadSurfaceContextFilter


def log_pass(msg: str):
    print(f"[\033[92mPASS\033[0m] {msg}")


def log_fail(msg: str):
    print(f"[\033[91mFAIL\033[0m] {msg}")


def test_tracker_direction_agnostic_curved_road():
    """Validates that tracker associates hazards moving diagonally on curved road or lane change."""
    print("\n--- Testing Direction-Agnostic Tracking on Curved Path ---")
    tracker = HazardTracker()

    # Simulate vehicle entering a rightward curve: hazard moves diagonally [left-to-right + forward]
    # Frame 1 at t=0.0s
    det1 = [{'class_id': 0, 'confidence': 0.85, 'bbox': [0.20, 0.40, 0.30, 0.50]}]
    alerts1, logged1 = tracker.process_frame(det1, timestamp=0.0)
    assert len(tracker.tracks) == 1, "Track should be created"
    assert len(logged1) == 0, "No incident logged on frame 1 (tentative)"

    # Frame 2 at t=0.1s (diagonal displacement)
    det2 = [{'class_id': 0, 'confidence': 0.88, 'bbox': [0.23, 0.45, 0.33, 0.55]}]
    alerts2, logged2 = tracker.process_frame(det2, timestamp=0.1)
    assert len(tracker.tracks) == 1, "Same track should be maintained"
    assert len(logged2) == 0, "No incident logged on frame 2 (tentative, 2 hits)"

    # Frame 3 at t=0.2s (continues diagonal path)
    det3 = [{'class_id': 0, 'confidence': 0.90, 'bbox': [0.26, 0.50, 0.36, 0.60]}]
    alerts3, logged3 = tracker.process_frame(det3, timestamp=0.2)
    assert len(tracker.tracks) == 1, "Track should persist with Track ID 1"
    assert len(logged3) == 1, "Incident must be logged on 3rd hit upon confirmation"
    assert logged3[0]['track_id'] == 1
    assert alerts3[0]['state'] == 'confirmed' or alerts3[0]['state'] == 'logged'

    # Frame 4 at t=0.3s -> must NOT re-log duplicate incident
    det4 = [{'class_id': 0, 'confidence': 0.91, 'bbox': [0.29, 0.55, 0.39, 0.65]}]
    alerts4, logged4 = tracker.process_frame(det4, timestamp=0.3)
    assert len(logged4) == 0, "CRITICAL: Must NOT re-emit incident for existing track (Duplicate Prevention)"
    assert len(alerts4) == 1, "HUD alert remains active"

    log_pass("Direction-agnostic tracking & single-incident emission verified.")


def test_tracker_variable_fps_delta_t():
    """Validates tracker across fluctuating frame intervals (30 FPS down to 10 FPS)."""
    print("\n--- Testing Delta-t Awareness Across Variable Frame Rates ---")
    tracker = HazardTracker()

    t = 100.0
    # Simulate high FPS (33ms interval)
    tracker.process_frame([{'class_id': 1, 'confidence': 0.80, 'bbox': [0.50, 0.50, 0.70, 0.55]}], timestamp=t)
    t += 0.033
    tracker.process_frame([{'class_id': 1, 'confidence': 0.82, 'bbox': [0.50, 0.52, 0.70, 0.57]}], timestamp=t)
    t += 0.033
    alerts, logged = tracker.process_frame([{'class_id': 1, 'confidence': 0.83, 'bbox': [0.50, 0.54, 0.70, 0.59]}], timestamp=t)
    assert len(logged) == 1, "Confirmed at high FPS"

    # Sudden frame drop / camera delay: 200ms gap
    t += 0.200
    # Expected displacement is larger due to longer dt
    det_large_step = [{'class_id': 1, 'confidence': 0.85, 'bbox': [0.50, 0.66, 0.70, 0.71]}]
    alerts_delayed, _ = tracker.process_frame(det_large_step, timestamp=t)
    assert len(alerts_delayed) == 1, "Track preserved despite 200ms frame drop"
    assert alerts_delayed[0]['track_id'] == 1, "Track ID preserved across frame rate jitter"

    log_pass("Delta-t timestamp velocity smoothing verified across 33ms to 200ms frame intervals.")


def test_surface_filter_multi_condition_robustness():
    """Validates road surface filter across multi-condition synthetic environments."""
    print("\n--- Testing Multi-Condition Road Surface Context Filter ---")
    filter_engine = RoadSurfaceContextFilter()
    frame_h, frame_w = 720, 1280

    # Condition 1: Black Fresh Asphalt with genuine pothole
    black_asphalt = np.full((frame_h, frame_w, 3), 40, dtype=np.uint8)
    pothole_det = {'class_id': 0, 'confidence': 0.78, 'bbox': [500, 450, 650, 580]}
    assert filter_engine.filter_detection(pothole_det, black_asphalt, (frame_h, frame_w)) is True, \
        "Genuine pothole on black asphalt must be retained"

    # Condition 2: Oxidized Light Grey Asphalt with genuine crack
    grey_asphalt = np.full((frame_h, frame_w, 3), 165, dtype=np.uint8)
    # Add fractured noise texture
    crack_crop = np.random.randint(50, 200, (80, 200, 3), dtype=np.uint8)
    grey_asphalt[400:480, 500:700] = crack_crop
    crack_det = {'class_id': 1, 'confidence': 0.52, 'bbox': [500, 400, 700, 480]}
    assert filter_engine.filter_detection(crack_det, grey_asphalt, (frame_h, frame_w)) is True, \
        "Genuine crack on grey weathered asphalt must be retained"

    # Condition 3: Unpaved Dirt / Gravel Road with brown tone
    dirt_road = np.full((frame_h, frame_w, 3), (45, 80, 115), dtype=np.uint8) # BGR brown
    dirt_pothole = {'class_id': 0, 'confidence': 0.70, 'bbox': [400, 500, 550, 620]}
    assert filter_engine.filter_detection(dirt_pothole, dirt_road, (frame_h, frame_w)) is True, \
        "Pothole on dirt/gravel road must be retained"

    # Condition 4: Night Conditions with vehicle headlight illumination cone
    night_frame = np.full((frame_h, frame_w, 3), 15, dtype=np.uint8)
    # Headlight illuminated patch
    night_frame[350:650, 300:980] = 110
    night_pothole = {'class_id': 0, 'confidence': 0.72, 'bbox': [450, 480, 600, 590]}
    assert filter_engine.filter_detection(night_pothole, night_frame, (frame_h, frame_w)) is True, \
        "Pothole in night headlight illumination must be retained"

    # Condition 5: Tree Canopy Smooth Shadow (False Positive Rejection)
    # Smooth shadow has zero high-frequency gradient variance
    shadow_frame = np.full((frame_h, frame_w, 3), 120, dtype=np.uint8)
    shadow_frame[400:500, 500:650] = 50 # Smooth dark shadow box with uniform interior
    false_crack_shadow = {'class_id': 1, 'confidence': 0.42, 'bbox': [500, 400, 650, 500]}
    assert filter_engine.filter_detection(false_crack_shadow, shadow_frame, (frame_h, frame_w)) is False, \
        "Smooth shadow artifact with low gradient variance should be filtered out"

    # Condition 6: Sky / Above Horizon Artifact (Rejection)
    sky_artifact = {'class_id': 0, 'confidence': 0.45, 'bbox': [400, 50, 600, 120]} # y2 = 120 / 720 = 0.16 < 0.30 horizon
    assert filter_engine.filter_detection(sky_artifact, shadow_frame, (frame_h, frame_w)) is False, \
        "Detections above the road perspective horizon must be rejected"

    # Condition 7: High-Confidence Safety Bypass Rule
    # Even if ambiguous, high-confidence detection (>= 0.65) is NEVER suppressed
    high_conf_crack = {'class_id': 1, 'confidence': 0.88, 'bbox': [500, 400, 650, 500]}
    assert filter_engine.filter_detection(high_conf_crack, shadow_frame, (frame_h, frame_w)) is True, \
        "High-confidence hazard (>= 0.65) must ALWAYS bypass suppression"

    log_pass("Multi-condition road surface filter verified across all environmental illumination scenarios.")


def main():
    test_tracker_direction_agnostic_curved_road()
    test_tracker_variable_fps_delta_t()
    test_surface_filter_multi_condition_robustness()

    print("\n\033[92m==================================================")
    print(" ALL TRACKER & SURFACE FILTER TESTS PASSED! ")
    print("==================================================\033[0m")
    return 0


if __name__ == "__main__":
    sys.exit(main())

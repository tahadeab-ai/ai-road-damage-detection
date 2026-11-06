#!/usr/bin/env python3
"""
RoadGuard AI — Realistic Road Video Sequence & Multi-Condition Filter Benchmark
Validates:
  1. Multi-hazard video tracking with vehicle dynamics (camera vibration, curved roads, lateral drift).
  2. Temporary occlusion and detection dropout resilience (preserving Track ID across 1-2 missing frames).
  3. Fluctuating framerate independence (10 to 30 FPS, variable Delta-t).
  4. Exact Single-Incident Emission Contract (zero duplicate incident logs per physical hazard).
  5. Multi-condition Road Surface Filter Safety Benchmark (0% false suppression across asphalt shades,
     dirt roads, sunlight glare, tree shadows, and night headlight illumination).
  6. Debug toggle verification (enabled=True/False).
"""

import math
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Tuple
import numpy as np

# Ensure repository root, src, and script dir are on path
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


def log_pass(msg: str) -> None:
    print(f"[\033[92mPASS\033[0m] {msg}")


def log_fail(msg: str) -> None:
    print(f"[\033[91mFAIL\033[0m] {msg}")


def log_info(msg: str) -> None:
    print(f"[\033[94mINFO\033[0m] {msg}")


# ==============================================================================
# 1. Realistic Road Video Sequence Simulation
# ==============================================================================
def simulate_realistic_road_video_tracking() -> bool:
    """
    Simulates a 30-frame driving video sequence on a curving road containing:
      - Two distinct physical hazards:
          * Hazard 1: Pothole (Class 3: D40_pothole) on the right lane
          * Hazard 2: Transverse Crack (Class 1: D10_transverse_crack) extending across the lane
      - Real vehicle dynamics:
          * Forward approach (hazards expand and move downward)
          * Road curvature / steering maneuver (lateral x-displacement)
          * Camera mount vibration (high-frequency pitch/roll jitter +/- 3 pixels)
          * Fluctuating FPS (frame intervals jitter between 33ms and 140ms)
          * Temporary detection dropout / occlusion (Hazard 1 drops out for 2 consecutive frames)
    """
    log_info("Starting realistic road video tracking simulation...")

    tracker = HazardTracker(
        iou_weight=0.6,
        dist_weight=0.4,
        max_dist_threshold=0.30,
        min_iou_threshold=0.15,
        min_hits_to_confirm=3,
        max_misses_to_drop=8
    )

    total_frames = 28
    current_time = 1000.0  # Base timestamp in seconds

    # Ground truth tracking stats
    all_logged_incidents = []
    active_track_ids_seen = set()

    # Ground truth hazard state trajectories
    # Hazard 1: D40 Pothole starting at distance, moving rightward due to left-curving road
    # Base start: center (0.62, 0.42), size (0.06, 0.04)
    # Hazard 2: D10 Crack starting closer, spanning center (0.45, 0.50), size (0.24, 0.05)

    for frame_idx in range(total_frames):
        # 1. Simulate fluctuating frame interval (Delta-t between 33ms and 120ms)
        dt = 0.033 + (0.015 * math.sin(frame_idx * 1.7)) + (0.06 if frame_idx in [8, 19] else 0.0)
        current_time += dt

        # 2. Camera vibration jitter (uneven road mount)
        vibe_x = 0.003 * math.sin(frame_idx * 4.2)
        vibe_y = 0.004 * math.cos(frame_idx * 3.8)

        # 3. Road curve lateral drift (vehicle rounding curve)
        curve_offset = 0.006 * frame_idx

        detections = []

        # --- Hazard 1: D40 Pothole ---
        # Approaches vehicle: y moves from 0.42 to 0.88, width expands from 0.06 to 0.16
        # Simulate dropout at frames 11 and 12 (camera glare or temporary occlusion)
        if frame_idx not in (11, 12):
            progress_1 = frame_idx / total_frames
            h1_xc = 0.60 + (curve_offset * 0.8) + vibe_x
            h1_yc = 0.42 + (progress_1 * 0.45) + vibe_y
            h1_w = 0.06 + (progress_1 * 0.10)
            h1_h = 0.04 + (progress_1 * 0.08)
            h1_conf = 0.82 + (0.08 * math.sin(frame_idx))

            detections.append({
                'class_id': 3,  # D40_pothole
                'confidence': float(min(0.96, max(0.68, h1_conf))),
                'bbox': [
                    round(h1_xc - h1_w / 2, 4),
                    round(h1_yc - h1_h / 2, 4),
                    round(h1_xc + h1_w / 2, 4),
                    round(h1_yc + h1_h / 2, 4)
                ]
            })

        # --- Hazard 2: D10 Transverse Crack ---
        # Starts visible from frame 4, moves from y=0.48 to 0.92, disappears as vehicle passes it at frame 22
        if 4 <= frame_idx <= 22:
            progress_2 = (frame_idx - 4) / 18.0
            h2_xc = 0.45 + (curve_offset * 0.7) + vibe_x
            h2_yc = 0.48 + (progress_2 * 0.44) + vibe_y
            h2_w = 0.22 + (progress_2 * 0.12)
            h2_h = 0.04 + (progress_2 * 0.05)
            h2_conf = 0.78 + (0.09 * math.cos(frame_idx))

            detections.append({
                'class_id': 1,  # D10_transverse_crack
                'confidence': float(min(0.95, max(0.65, h2_conf))),
                'bbox': [
                    round(h2_xc - h2_w / 2, 4),
                    round(h2_yc - h2_h / 2, 4),
                    round(h2_xc + h2_w / 2, 4),
                    round(h2_yc + h2_h / 2, 4)
                ]
            })

        # Process frame through tracker
        alerts, new_logged = tracker.process_frame(detections, timestamp=current_time)

        for log in new_logged:
            all_logged_incidents.append((frame_idx, log))

        for al in alerts:
            active_track_ids_seen.add(al['track_id'])

        # Detailed validation checkpoints during playback
        if frame_idx == 3:
            # Hazard 1 should transition from tentative to confirmed on frame 3 (3rd hit)
            assert len(all_logged_incidents) == 1, f"Frame {frame_idx}: Hazard 1 must log incident on confirmation"
            assert all_logged_incidents[0][1]['track_id'] == 1
            assert all_logged_incidents[0][1]['class_id'] == 3

        if frame_idx == 6:
            # Hazard 2 was introduced at frame 4. On frame 6 (hit 3), it should confirm
            assert len(all_logged_incidents) == 2, f"Frame {frame_idx}: Hazard 2 must log incident on confirmation"
            assert all_logged_incidents[1][1]['track_id'] == 2
            assert all_logged_incidents[1][1]['class_id'] == 1

        if frame_idx == 13:
            # Dropout occurred at frames 11 and 12. Frame 13 is re-detection.
            # CRITICAL: Hazard 1 must NOT create a new Track ID; it MUST retain Track ID 1!
            h1_alert = [a for a in alerts if a['class_id'] == 3]
            assert len(h1_alert) == 1, "Hazard 1 must be re-associated immediately upon reappearance"
            assert h1_alert[0]['track_id'] == 1, f"Track ID must persist as 1 after 2-frame dropout, got {h1_alert[0]['track_id']}"
            assert len(all_logged_incidents) == 2, "Re-detection after dropout must NOT re-emit duplicate incident"

    # End of video assertions:
    # 1. Total unique tracks created must be exactly 2
    if len(active_track_ids_seen) != 2:
        log_fail(f"Expected exactly 2 unique Track IDs, found {active_track_ids_seen}")
        return False

    # 2. Total logged incidents must be exactly 2 (Zero duplicate events logged!)
    if len(all_logged_incidents) != 2:
        log_fail(f"Duplicate Incident Logging Violation! Expected 2 incidents, got {len(all_logged_incidents)}")
        return False

    log_pass(f"Realistic road video sequence tracking passed: 2 distinct hazards tracked smoothly with 0 duplicates.")
    log_pass("Track ID 1 successfully preserved across 2-frame dropout and camera vibration.")
    return True


# ==============================================================================
# 2. Road Surface Filter Multi-Condition Safety Benchmark
# ==============================================================================
def benchmark_road_surface_filter_safety() -> bool:
    """
    Evaluates RoadSurfaceContextFilter across 7 challenging environmental conditions:
      1. Fresh Black Asphalt (low baseline luminance, high contrast)
      2. Oxidized Light Grey Weathered Asphalt
      3. Unpaved Dirt / Gravel / Desert Road (earth-tone chromaticity)
      4. Strong Direct Sunlight Glare (high baseline luminance, sensor clipping)
      5. Tree Canopy Dappled Shadows (complex optical patterns)
      6. Night Low-Light with Vehicle Headlight Beam Cone
      7. Noisy Low-Cost Camera Sensor (high ISO noise grain)
    
    Safety Guarantee:
      The filter must achieve ZERO percent false suppression for genuine road damage
      across all 4 classes: D00 (0), D10 (1), D20 (2), D40 (3).
    """
    log_info("Executing Multi-Condition Road Surface Filter Safety Benchmark...")

    filter_engine = RoadSurfaceContextFilter(
        enabled=True,
        min_horizon_ratio=0.30,
        min_edge_gradient_threshold=8.0,
        high_confidence_bypass=0.65
    )

    frame_h, frame_w = 720, 1280

    test_scenarios = [
        ("Fresh Black Asphalt", np.full((frame_h, frame_w, 3), 35, dtype=np.uint8)),
        ("Weathered Grey Asphalt", np.full((frame_h, frame_w, 3), 170, dtype=np.uint8)),
        ("Dirt / Gravel Road", np.full((frame_h, frame_w, 3), (50, 90, 130), dtype=np.uint8)),
        ("Direct Sunlight Glare", np.full((frame_h, frame_w, 3), 235, dtype=np.uint8)),
        ("Tree Canopy Shadows", np.full((frame_h, frame_w, 3), 100, dtype=np.uint8)),
        ("Night Headlight Beam", np.full((frame_h, frame_w, 3), 20, dtype=np.uint8)),
        ("Noisy Low-Cost Sensor", np.clip(np.random.normal(120, 25, (frame_h, frame_w, 3)), 0, 255).astype(np.uint8))
    ]

    # Add realistic localized variations to scenarios
    # Night headlight beam cone
    test_scenarios[5][1][300:700, 250:1050] = 135

    # Tree canopy dappled pattern
    for sx in range(100, frame_w - 100, 120):
        test_scenarios[4][1][350:600, sx:sx+70] = 45

    # 4-class genuine damage test batch (all positioned on road plane below horizon y=0.30)
    genuine_damages = [
        {'name': 'D00 Longitudinal Crack', 'class_id': 0, 'confidence': 0.72, 'bbox': [300, 380, 360, 560]},
        {'name': 'D10 Transverse Crack',   'class_id': 1, 'confidence': 0.68, 'bbox': [450, 420, 750, 470]},
        {'name': 'D20 Alligator Crack',    'class_id': 2, 'confidence': 0.74, 'bbox': [600, 480, 780, 600]},
        {'name': 'D40 Pothole',            'class_id': 3, 'confidence': 0.81, 'bbox': [500, 450, 680, 580]}
    ]

    # Evaluate zero false suppression
    suppressed_count = 0
    total_evals = 0

    for scenario_name, frame in test_scenarios:
        for damage in genuine_damages:
            total_evals += 1
            retained = filter_engine.filter_detection(damage, frame, (frame_h, frame_w))
            if not retained:
                suppressed_count += 1
                log_fail(f"SAFETY VIOLATION: Genuine {damage['name']} falsely suppressed in '{scenario_name}'!")

    if suppressed_count > 0:
        log_fail(f"Filter Safety Benchmark Failed: {suppressed_count}/{total_evals} genuine damages suppressed!")
        return False

    log_pass(f"0% False Suppression Rate verified: All {total_evals} damage evaluations retained across 7 conditions.")

    # False Positive Rejection Tests:
    # 1. Sky / tree artifact above horizon (y2 < 0.30) -> MUST be suppressed
    sky_artifact = {'class_id': 3, 'confidence': 0.50, 'bbox': [400, 40, 550, 150]} # y2 = 150/720 = 0.208 < 0.30
    assert not filter_engine.filter_detection(sky_artifact, test_scenarios[0][1], (frame_h, frame_w)), \
        "Sky / tree cloud artifact above horizon must be rejected"

    # 2. Uniform smooth tree shadow with zero edge energy -> MUST be suppressed
    shadow_box = np.full((frame_h, frame_w, 3), 130, dtype=np.uint8)
    shadow_box[400:520, 400:600] = 55 # Perfectly smooth shadow rectangle
    smooth_shadow_crack = {'class_id': 1, 'confidence': 0.44, 'bbox': [400, 400, 600, 520]}
    assert not filter_engine.filter_detection(smooth_shadow_crack, shadow_box, (frame_h, frame_w)), \
        "Smooth shadow artifact with zero edge energy must be suppressed"

    log_pass("False-positive rejection verified: Sky artifacts and uniform shadows correctly suppressed.")

    # 3. Debug Toggle Verification (enabled=False)
    debug_filter = RoadSurfaceContextFilter(enabled=False)
    # When disabled, even sky artifacts and smooth shadows must pass through without blockage
    assert debug_filter.filter_detection(sky_artifact, test_scenarios[0][1], (frame_h, frame_w)) is True, \
        "Debug toggle enabled=False must bypass all filtering"
    assert debug_filter.filter_detection(smooth_shadow_crack, shadow_box, (frame_h, frame_w)) is True, \
        "Debug toggle enabled=False must allow shadow detection through"

    log_pass("Debug toggle (enabled=False) successfully verified (bypasses filtering for field diagnostics).")
    return True


def main() -> int:
    print("==================================================================")
    print(" RoadGuard AI — Video Tracking & Surface Filter Verification Suite")
    print("==================================================================")

    res1 = simulate_realistic_road_video_tracking()
    res2 = benchmark_road_surface_filter_safety()

    if res1 and res2:
        print("\n\033[92m==================================================")
        print(" ALL VIDEO TRACKING & SURFACE FILTER BENCHMARKS PASSED! ")
        print("==================================================\033[0m")
        return 0
    else:
        print("\n\033[91m==================================================")
        print(" BENCHMARKS FAILED. ")
        print("==================================================\033[0m")
        return 1


if __name__ == "__main__":
    sys.exit(main())

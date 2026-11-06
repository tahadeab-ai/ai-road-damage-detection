#!/usr/bin/env python3
"""
RoadGuard AI — Direction-Agnostic, Delta-t Aware Spatio-Temporal Hazard Tracker
Provides robust object tracking across dynamic vehicle maneuvers (curved roads, lane changes).
Maintains persistent Track IDs, applies timestamp-based velocity smoothing independent of FPS,
and enforces a 4-state lifecycle to eliminate duplicate incident logging.
"""

import time
from enum import Enum
from typing import Any, Dict, List, Optional, Tuple
import numpy as np


class TrackState(Enum):
    TENTATIVE = "tentative"    # New track candidate, requires K hits to confirm
    CONFIRMED = "confirmed"    # Active verified hazard, triggers HUD alert
    LOGGED = "logged"          # Incident recorded and queued for sync; suppressed from re-logging
    LOST = "lost"              # Target dropped after M consecutive misses


class TrackedHazard:
    """Represents an active, persistent hazard track across video frames."""

    def __init__(self, track_id: int, initial_bbox: List[float], class_id: int, confidence: float, timestamp: float):
        self.track_id = track_id
        self.class_id = class_id
        self.confidence = confidence
        self.bbox = list(initial_bbox)  # [x1, y1, x2, y2] in normalized or pixel coords
        self.centroid = self._calc_centroid(self.bbox)
        self.velocity = np.array([0.0, 0.0], dtype=np.float32)  # [vx, vy] per second
        self.last_timestamp = timestamp
        self.first_timestamp = timestamp

        self.hit_count = 1
        self.miss_count = 0
        self.state = TrackState.TENTATIVE
        self.has_logged_incident = False

    @staticmethod
    def _calc_centroid(bbox: List[float]) -> np.ndarray:
        return np.array([(bbox[0] + bbox[2]) / 2.0, (bbox[1] + bbox[3]) / 2.0], dtype=np.float32)

    def predict(self, current_timestamp: float) -> np.ndarray:
        """Predicts updated centroid using delta-t velocity extrapolation."""
        dt = max(0.001, current_timestamp - self.last_timestamp)
        predicted_centroid = self.centroid + (self.velocity * dt)
        return predicted_centroid

    def update(self, detection: Dict[str, Any], current_timestamp: float, alpha_pos: float = 0.7, alpha_vel: float = 0.3):
        """
        Updates track state using newly associated detection.
        Applies delta-t aware Exponential Moving Average smoothing.
        """
        dt = max(0.001, current_timestamp - self.last_timestamp)
        new_bbox = detection['bbox']
        new_centroid = self._calc_centroid(new_bbox)

        # Instantaneous velocity: delta_centroid / delta_t
        instant_velocity = (new_centroid - self.centroid) / dt
        self.velocity = (alpha_vel * instant_velocity) + ((1.0 - alpha_vel) * self.velocity)

        # Smoothed bounding box & centroid
        self.centroid = (alpha_pos * new_centroid) + ((1.0 - alpha_pos) * self.centroid)
        self.bbox = [
            (alpha_pos * new_bbox[i]) + ((1.0 - alpha_pos) * self.bbox[i])
            for i in range(4)
        ]

        # Update confidence (EMA)
        self.confidence = (alpha_pos * detection['confidence']) + ((1.0 - alpha_pos) * self.confidence)
        self.last_timestamp = current_timestamp
        self.hit_count += 1
        self.miss_count = 0

        # State transition: Tentative -> Confirmed
        if self.state == TrackState.TENTATIVE and self.hit_count >= 3:
            self.state = TrackState.CONFIRMED

    def mark_missed(self, max_misses: int = 10):
        """Increments miss counter; transitions to LOST if max_misses exceeded."""
        self.miss_count += 1
        if self.miss_count >= max_misses:
            self.state = TrackState.LOST


class HazardTracker:
    """
    Direction-agnostic, delta-t aware hazard tracking engine.
    Associates detections across frames using IoU + normalized centroid distance.
    Prevents duplicate incident reporting through stateful tracking.
    """

    def __init__(
        self,
        iou_weight: float = 0.6,
        dist_weight: float = 0.4,
        max_dist_threshold: float = 0.25,  # Normalized distance threshold (25% of frame)
        min_iou_threshold: float = 0.20,
        min_hits_to_confirm: int = 3,
        max_misses_to_drop: int = 8
    ):
        self.iou_weight = iou_weight
        self.dist_weight = dist_weight
        self.max_dist_threshold = max_dist_threshold
        self.min_iou_threshold = min_iou_threshold
        self.min_hits_to_confirm = min_hits_to_confirm
        self.max_misses_to_drop = max_misses_to_drop

        self.next_track_id = 1
        self.tracks: Dict[int, TrackedHazard] = {}

    @staticmethod
    def _compute_iou(b1: List[float], b2: List[float]) -> float:
        x1 = max(b1[0], b2[0])
        y1 = max(b1[1], b2[1])
        x2 = min(b1[2], b2[2])
        y2 = min(b1[3], b2[3])

        inter = max(0.0, x2 - x1) * max(0.0, y2 - y1)
        area1 = (b1[2] - b1[0]) * (b1[3] - b1[1])
        area2 = (b2[2] - b2[0]) * (b2[3] - b2[1])
        union = area1 + area2 - inter

        if union <= 0.0:
            return 0.0
        return inter / union

    def _association_cost(self, track: TrackedHazard, detection: Dict[str, Any], current_timestamp: float) -> float:
        """
        Computes composite association distance [0.0 = perfect match, 1.0 = completely disjoint].
        Combines bounding box IoU and centroid Euclidean distance.
        Completely agnostic of movement direction (supports turns, lane changes, curbs).
        """
        # Class mismatch penalty
        if track.class_id != detection['class_id']:
            return 1.0

        det_bbox = detection['bbox']
        iou = self._compute_iou(track.bbox, det_bbox)

        predicted_centroid = track.predict(current_timestamp)
        det_centroid = np.array([(det_bbox[0] + det_bbox[2]) / 2.0, (det_bbox[1] + det_bbox[3]) / 2.0])
        
        # Euclidean distance
        dist = float(np.linalg.norm(predicted_centroid - det_centroid))

        if dist > self.max_dist_threshold and iou < self.min_iou_threshold:
            return 1.0

        # Composite score: lower is better
        cost = (self.dist_weight * min(1.0, dist / self.max_dist_threshold)) + (self.iou_weight * (1.0 - iou))
        return float(cost)

    def process_frame(
        self,
        detections: List[Dict[str, Any]],
        timestamp: Optional[float] = None
    ) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
        """
        Processes a new batch of raw detections.
        Returns:
          1. Active confirmed tracks for UI HUD rendering.
          2. Newly logged incidents ready for offline queue storage (emitted EXACTLY ONCE per hazard).
        """
        if timestamp is None:
            timestamp = time.time()

        # Step 1: Compute pairwise association cost matrix
        track_ids = list(self.tracks.keys())
        cost_matrix = []

        for tid in track_ids:
            track = self.tracks[tid]
            row = [self._association_cost(track, det, timestamp) for det in detections]
            cost_matrix.append(row)

        assigned_tracks = set()
        assigned_dets = set()

        # Step 2: Greedy assignment (lowest cost first)
        if len(track_ids) > 0 and len(detections) > 0:
            costs = []
            for t_idx, tid in enumerate(track_ids):
                for d_idx, _ in enumerate(detections):
                    c = cost_matrix[t_idx][d_idx]
                    if c < 0.70:  # Association acceptance threshold
                        costs.append((c, t_idx, d_idx))

            costs.sort(key=lambda x: x[0])

            for c, t_idx, d_idx in costs:
                tid = track_ids[t_idx]
                if tid not in assigned_tracks and d_idx not in assigned_dets:
                    self.tracks[tid].update(detections[d_idx], timestamp)
                    assigned_tracks.add(tid)
                    assigned_dets.add(d_idx)

        # Step 3: Unmatched existing tracks -> Mark missed
        for tid in track_ids:
            if tid not in assigned_tracks:
                self.tracks[tid].mark_missed(self.max_misses_to_drop)

        # Step 4: Unmatched detections -> Initialize new tentative tracks
        for d_idx, det in enumerate(detections):
            if d_idx not in assigned_dets:
                new_track = TrackedHazard(
                    track_id=self.next_track_id,
                    initial_bbox=det['bbox'],
                    class_id=det['class_id'],
                    confidence=det['confidence'],
                    timestamp=timestamp
                )
                self.tracks[self.next_track_id] = new_track
                self.next_track_id += 1

        # Step 5: Lifecycle management & incident extraction
        active_hud_alerts = []
        new_incidents_to_log = []

        dead_track_ids = []
        for tid, track in self.tracks.items():
            if track.state == TrackState.LOST:
                dead_track_ids.append(tid)
                continue

            # Return confirmed/logged tracks for stable HUD rendering
            if track.state in (TrackState.CONFIRMED, TrackState.LOGGED):
                active_hud_alerts.append({
                    'track_id': track.track_id,
                    'class_id': track.class_id,
                    'confidence': round(track.confidence, 3),
                    'bbox': [round(x, 3) for x in track.bbox],
                    'hit_count': track.hit_count,
                    'state': track.state.value
                })

            # Emit log incident event EXACTLY ONCE upon initial confirmation
            if track.state == TrackState.CONFIRMED and not track.has_logged_incident:
                track.has_logged_incident = True
                track.state = TrackState.LOGGED
                new_incidents_to_log.append({
                    'incident_id': f"INC-{track.track_id}-{int(track.first_timestamp)}",
                    'track_id': track.track_id,
                    'class_id': track.class_id,
                    'confidence': round(track.confidence, 3),
                    'bbox': [round(x, 3) for x in track.bbox],
                    'timestamp': track.first_timestamp,
                    'duration_tracked_sec': round(timestamp - track.first_timestamp, 3)
                })

        # Remove dead tracks
        for tid in dead_track_ids:
            del self.tracks[tid]

        return active_hud_alerts, new_incidents_to_log

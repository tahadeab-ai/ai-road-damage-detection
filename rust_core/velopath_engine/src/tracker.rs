use crate::geometry::InversePerspectiveMapper;
use crate::types::{BoundingBox, DefectClass, GroundCoords, RawDetection, TrackedDefect};

const CONFIRMATION_HITS_THRESHOLD: u32 = 3;
const MAX_MISSED_FRAMES_GRACE: u32 = 10;

#[derive(Debug, Clone)]
pub struct TrackItem {
    pub id: u64,
    pub class: DefectClass,
    pub confidence: f32,
    pub bbox: BoundingBox,
    pub ground: GroundCoords,
    pub hit_count: u32,
    pub missed_frames: u32,
    pub confirmed: bool,
    pub committed_to_db: bool,
    // Simple 2D Kalman state for ground coordinates: [x, y, vx, vy]
    pub kf_state: [f32; 4],
}

impl TrackItem {
    pub fn new(id: u64, det: &RawDetection, ground: GroundCoords) -> Self {
        Self {
            id,
            class: det.class,
            confidence: det.confidence,
            bbox: det.bbox,
            ground,
            hit_count: 1,
            missed_frames: 0,
            confirmed: false,
            committed_to_db: false,
            kf_state: [ground.x_meters, ground.y_meters, 0.0, 0.0],
        }
    }

    pub fn predict(&mut self, dt: f32) {
        self.kf_state[0] += self.kf_state[2] * dt;
        self.kf_state[1] += self.kf_state[3] * dt;
        self.ground.x_meters = self.kf_state[0];
        self.ground.y_meters = self.kf_state[1];
    }

    pub fn update(&mut self, det: &RawDetection, ground: GroundCoords, dt: f32) {
        // Measurement update (alpha-beta filter)
        let alpha = 0.65;
        let beta = 0.40;

        let residual_x = ground.x_meters - self.kf_state[0];
        let residual_y = ground.y_meters - self.kf_state[1];

        self.kf_state[0] += alpha * residual_x;
        self.kf_state[1] += alpha * residual_y;

        if dt > 0.001 {
            self.kf_state[2] += (beta / dt) * residual_x;
            self.kf_state[3] += (beta / dt) * residual_y;
        }

        // EMA bounding box & confidence smoothing
        self.bbox.ymin = 0.7 * self.bbox.ymin + 0.3 * det.bbox.ymin;
        self.bbox.xmin = 0.7 * self.bbox.xmin + 0.3 * det.bbox.xmin;
        self.bbox.ymax = 0.7 * self.bbox.ymax + 0.3 * det.bbox.ymax;
        self.bbox.xmax = 0.7 * self.bbox.xmax + 0.3 * det.bbox.xmax;
        self.confidence = 0.7 * self.confidence + 0.3 * det.confidence;

        self.ground.x_meters = self.kf_state[0];
        self.ground.y_meters = self.kf_state[1];
        self.ground.area_sq_cm = 0.8 * self.ground.area_sq_cm + 0.2 * ground.area_sq_cm;

        self.hit_count += 1;
        self.missed_frames = 0;
        if self.hit_count >= CONFIRMATION_HITS_THRESHOLD {
            self.confirmed = true;
        }
    }
}

pub struct SpatioTemporalTracker {
    next_track_id: u64,
    tracks: Vec<TrackItem>,
    mapper: InversePerspectiveMapper,
}

impl SpatioTemporalTracker {
    pub fn new(mapper: InversePerspectiveMapper) -> Self {
        Self {
            next_track_id: 1,
            tracks: Vec::new(),
            mapper,
        }
    }

    /// Process raw frame detections and return active tracks plus tracks ready for DB commit
    pub fn update(
        &mut self,
        detections: &[RawDetection],
        dt: f32,
    ) -> (Vec<TrackedDefect>, Vec<TrackItem>) {
        // 1. Predict state for all existing tracks
        for track in &mut self.tracks {
            track.predict(dt);
        }

        // 2. Greedy bipartite matching based on ground distance and IoU
        let mut matched_tracks = vec![false; self.tracks.len()];
        let mut matched_dets = vec![false; detections.len()];

        for (d_idx, det) in detections.iter().enumerate() {
            let det_ground = self.mapper.compute_ground_coords(&det.bbox);
            let mut best_t_idx = None;
            let mut best_dist = f32::MAX;

            for (t_idx, track) in self.tracks.iter().enumerate() {
                if matched_tracks[t_idx] || track.class != det.class {
                    continue;
                }

                // Spatial Euclidean distance on road ground plane (meters)
                let dx = track.ground.x_meters - det_ground.x_meters;
                let dy = track.ground.y_meters - det_ground.y_meters;
                let ground_dist = (dx * dx + dy * dy).sqrt();

                let gate = InversePerspectiveMapper::association_gate_distance(track.ground.y_meters);
                let iou = track.bbox.iou(&det.bbox);

                if ground_dist <= gate || iou > 0.25 {
                    if ground_dist < best_dist {
                        best_dist = ground_dist;
                        best_t_idx = Some(t_idx);
                    }
                }
            }

            if let Some(t_idx) = best_t_idx {
                self.tracks[t_idx].update(det, det_ground, dt);
                matched_tracks[t_idx] = true;
                matched_dets[d_idx] = true;
            }
        }

        // 3. Mark unmatched tracks as missed
        for (t_idx, matched) in matched_tracks.iter().enumerate() {
            if !matched {
                self.tracks[t_idx].missed_frames += 1;
            }
        }

        // 4. Spawn new tracks for unmatched detections
        for (d_idx, matched) in matched_dets.iter().enumerate() {
            if !matched {
                let det = &detections[d_idx];
                let det_ground = self.mapper.compute_ground_coords(&det.bbox);
                let new_item = TrackItem::new(self.next_track_id, det, det_ground);
                self.next_track_id += 1;
                self.tracks.push(new_item);
            }
        }

        // 5. Frustum exit / retirement check:
        // A confirmed track is ready to commit to persistent storage when:
        // a) It reaches close to bumper (Y_m <= 1.2m), OR
        // b) It exits the view (missed_frames >= 2 and confirmed), and hasn't been committed yet.
        let mut tracks_to_commit = Vec::new();
        for track in &mut self.tracks {
            if track.confirmed && !track.committed_to_db {
                if track.ground.y_meters <= 1.2 || track.missed_frames >= 2 {
                    track.committed_to_db = true;
                    tracks_to_commit.push(track.clone());
                }
            }
        }

        // 6. Purge stale tracks exceeding grace buffer
        self.tracks.retain(|t| t.missed_frames < MAX_MISSED_FRAMES_GRACE);

        // 7. Format active visible tracks for UI rendering
        let active_defects = self
            .tracks
            .iter()
            .filter(|t| t.missed_frames == 0)
            .map(|t| {
                let severity = InversePerspectiveMapper::compute_severity_index(
                    t.class,
                    t.confidence,
                    t.ground.area_sq_cm,
                );
                TrackedDefect {
                    track_id: t.id,
                    class: t.class,
                    confidence: t.confidence,
                    bbox: t.bbox,
                    ground: t.ground,
                    severity_score: severity,
                    hit_count: t.hit_count,
                    confirmed: t.confirmed,
                }
            })
            .collect();

        (active_defects, tracks_to_commit)
    }
}

use crate::geometry::InversePerspectiveMapper;
use crate::inference::{class_aware_nms, DiagnosticInferenceBackend, InferenceBackend, ModelManifest};
use crate::occlusion::analyze_scene_health;
use crate::preprocessing::preprocess_frame_with_roi;
use crate::storage::SqliteStorage;
use crate::tracker::SpatioTemporalTracker;
use crate::types::{
    FpsMetrics, FrameProcessingResult, GpsTelemetry, RoadRoiConfig, SceneHealthStatus,
};
use std::sync::Mutex;
use std::time::Instant;

pub struct VeloPathEngine {
    roi_config: Mutex<RoadRoiConfig>,
    tracker: Mutex<SpatioTemporalTracker>,
    storage: Mutex<Option<SqliteStorage>>,
    inference_backend: Box<dyn InferenceBackend>,
    manifest: ModelManifest,
}

impl VeloPathEngine {
    pub fn new(db_path: Option<String>, roi: Option<RoadRoiConfig>) -> Result<Self, String> {
        let mapper = InversePerspectiveMapper::with_defaults();
        let tracker = SpatioTemporalTracker::new(mapper);

        let storage = if let Some(path) = db_path {
            let s = SqliteStorage::open(path).map_err(|e| e.to_string())?;
            Some(s)
        } else {
            let s = SqliteStorage::open_in_memory().map_err(|e| e.to_string())?;
            Some(s)
        };

        let manifest = ModelManifest::default();
        let inference_backend = Box::new(DiagnosticInferenceBackend::new(manifest.clone()));

        Ok(Self {
            roi_config: Mutex::new(roi.unwrap_or_default()),
            tracker: Mutex::new(tracker),
            storage: Mutex::new(storage),
            inference_backend,
            manifest,
        })
    }

    /// Process a live camera frame through the full zero-copy vision pipeline
    pub fn process_frame(
        &self,
        rgb_data: &[u8],
        width: u32,
        height: u32,
        telemetry: GpsTelemetry,
        dt_seconds: f32,
    ) -> FrameProcessingResult {
        let t_start = Instant::now();

        // 1. Scene Health & Spatial Occlusion Guard (< 0.2ms)
        let scene_status = analyze_scene_health(rgb_data, width, height);
        if !scene_status.is_passable() {
            let elapsed_ms = t_start.elapsed().as_secs_f32() * 1000.0;
            return FrameProcessingResult {
                timestamp_ms: telemetry.timestamp_ms,
                scene_status,
                active_defects: Vec::new(),
                metrics: FpsMetrics {
                    fps: 1.0 / dt_seconds.max(0.001),
                    preprocess_ms: elapsed_ms,
                    inference_ms: 0.0,
                    postprocess_ms: 0.0,
                    total_pipeline_ms: elapsed_ms,
                },
                committed_defect_uuid: None,
            };
        }

        // 2. Road ROI Cropping & SIMD Letterbox Resizing (< 2.0ms)
        let t_pre = Instant::now();
        let current_roi = *self.roi_config.lock().unwrap();
        let letterbox = match preprocess_frame_with_roi(rgb_data, width, height, &current_roi) {
            Ok(lb) => lb,
            Err(_) => {
                return FrameProcessingResult {
                    timestamp_ms: telemetry.timestamp_ms,
                    scene_status: SceneHealthStatus::CameraObstructed,
                    active_defects: Vec::new(),
                    metrics: FpsMetrics {
                        fps: 0.0,
                        preprocess_ms: 0.0,
                        inference_ms: 0.0,
                        postprocess_ms: 0.0,
                        total_pipeline_ms: 0.0,
                    },
                    committed_defect_uuid: None,
                };
            }
        };
        let preprocess_ms = t_pre.elapsed().as_secs_f32() * 1000.0;

        // 3. Hardware-Accelerated Multi-Tier Inference
        let t_inf = Instant::now();
        let raw_candidates = self
            .inference_backend
            .run_inference(&letterbox.float_data)
            .unwrap_or_default();
        let inference_ms = t_inf.elapsed().as_secs_f32() * 1000.0;

        // 4. Class-Aware Non-Maximum Suppression (< 0.3ms)
        let t_post = Instant::now();
        let nms_detections = class_aware_nms(raw_candidates, self.manifest.iou_threshold);

        // 5. Spatio-Temporal Tracker Update & Frustum Exit Commit
        let mut tracker_guard = self.tracker.lock().unwrap();
        let (active_defects, tracks_to_commit) = tracker_guard.update(&nms_detections, dt_seconds);

        // 6. Atomic Persistence to SQLite WAL
        let mut committed_uuid = None;
        if let Some(storage_guard) = self.storage.lock().unwrap().as_mut() {
            for track in &tracks_to_commit {
                if let Ok(Some(uuid)) = storage_guard.insert_defect(track, &telemetry, "in_memory") {
                    committed_uuid = Some(uuid);
                }
            }
        }
        let postprocess_ms = t_post.elapsed().as_secs_f32() * 1000.0;
        let total_ms = t_start.elapsed().as_secs_f32() * 1000.0;

        FrameProcessingResult {
            timestamp_ms: telemetry.timestamp_ms,
            scene_status: SceneHealthStatus::Optimal,
            active_defects,
            metrics: FpsMetrics {
                fps: (1.0 / dt_seconds.max(0.001)).min(120.0),
                preprocess_ms,
                inference_ms,
                postprocess_ms,
                total_pipeline_ms: total_ms,
            },
            committed_defect_uuid: committed_uuid,
        }
    }

    /// Set dynamic Road ROI cropping on the fly
    pub fn update_roi(&self, roi: RoadRoiConfig) {
        if let Ok(mut guard) = self.roi_config.lock() {
            *guard = roi;
        }
    }

    /// Query pending sync count for enterprise fleet worker
    pub fn get_pending_sync_count(&self) -> usize {
        if let Ok(guard) = self.storage.lock() {
            if let Some(storage) = guard.as_ref() {
                return storage.get_pending_sync_count().unwrap_or(0);
            }
        }
        0
    }
}

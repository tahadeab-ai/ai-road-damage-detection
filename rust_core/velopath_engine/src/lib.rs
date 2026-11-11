pub mod api;
pub mod geometry;
pub mod inference;
pub mod occlusion;
pub mod preprocessing;
pub mod storage;
pub mod tracker;
pub mod types;

// Re-export primary types for public use
pub use api::VeloPathEngine;
pub use geometry::{CameraGeometryConfig, InversePerspectiveMapper};
pub use inference::{class_aware_nms, decode_yolo_tensor, ExecutionTier, ModelManifest};
pub use occlusion::analyze_scene_health;
pub use preprocessing::{preprocess_frame_with_roi, yuv420_to_rgb, FrameFormat, FrameRingBuffer, LetterboxResult};
pub use storage::SqliteStorage;
pub use tracker::SpatioTemporalTracker;
pub use types::*;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_defect_class_properties() {
        assert_eq!(DefectClass::D00.as_str(), "D00");
        assert_eq!(DefectClass::D10.as_str(), "D10");
        assert_eq!(DefectClass::D20.as_str(), "D20");
        assert_eq!(DefectClass::D40.as_str(), "D40");

        assert_eq!(DefectClass::from_id(0), Some(DefectClass::D00));
        assert_eq!(DefectClass::from_id(3), Some(DefectClass::D40));
        assert_eq!(DefectClass::from_id(99), None);
    }

    #[test]
    fn test_bounding_box_iou() {
        let b1 = BoundingBox::new(0.1, 0.1, 0.5, 0.5);
        let b2 = BoundingBox::new(0.1, 0.1, 0.5, 0.5);
        assert!((b1.iou(&b2) - 1.0).abs() < 1e-4);

        let b3 = BoundingBox::new(0.6, 0.6, 0.9, 0.9);
        assert_eq!(b1.iou(&b3), 0.0);
    }

    #[test]
    fn test_ipm_ground_projection() {
        let mapper = InversePerspectiveMapper::with_defaults();
        let (x, y) = mapper.project_pixel_to_ground(0.5, 0.8).expect("Projection valid");
        // Center pixel horizontally should have near 0.0 lateral offset
        assert!(x.abs() < 0.1);
        // Longitudinal distance ahead should be positive and realistic
        assert!(y > 1.0 && y < 30.0);

        let gate = InversePerspectiveMapper::association_gate_distance(y);
        assert!(gate >= 0.90 && gate <= 2.50);
    }

    #[test]
    fn test_sqlite_wal_deduplication() {
        let mut storage = SqliteStorage::open_in_memory().expect("In-memory SQLite open");

        let track = tracker::TrackItem {
            id: 1,
            class: DefectClass::D40,
            confidence: 0.92,
            bbox: BoundingBox::new(0.3, 0.3, 0.6, 0.6),
            ground: GroundCoords {
                y_meters: 5.0,
                x_meters: 0.2,
                area_sq_cm: 600.0,
            },
            hit_count: 5,
            missed_frames: 0,
            confirmed: true,
            committed_to_db: false,
            kf_state: [0.2, 5.0, 0.0, 0.0],
        };

        let telemetry = GpsTelemetry {
            latitude: 37.7749,
            longitude: -122.4194,
            speed_kmh: 40.0,
            heading_deg: 90.0,
            timestamp_ms: 1_700_000_000_000,
        };

        // First insertion should succeed
        let uuid = storage
            .insert_defect(&track, &telemetry, "crop1.jpg")
            .expect("Insert succeeds")
            .expect("UUID present");
        assert!(!uuid.is_empty());

        // Identical detection within 2 seconds and same location should be suppressed as duplicate
        let mut telemetry_dup = telemetry;
        telemetry_dup.timestamp_ms += 2_000;
        let dup_res = storage
            .insert_defect(&track, &telemetry_dup, "crop2.jpg")
            .expect("Query succeeds");
        assert!(dup_res.is_none(), "Duplicate was not suppressed");
    }

    #[test]
    fn test_class_aware_nms() {
        let b1 = BoundingBox::new(0.2, 0.2, 0.4, 0.4);
        let b2 = BoundingBox::new(0.21, 0.21, 0.41, 0.41);

        let dets = vec![
            RawDetection {
                class: DefectClass::D00,
                confidence: 0.85,
                bbox: b1,
            },
            RawDetection {
                class: DefectClass::D00,
                confidence: 0.70,
                bbox: b2,
            },
            RawDetection {
                class: DefectClass::D40,
                confidence: 0.90,
                bbox: b1, // Same bbox but different class (Class-Aware!)
            },
        ];

        let filtered = class_aware_nms(dets, 0.45);
        // D00 with 0.70 should be suppressed by D00 with 0.85, but D40 should survive!
        assert_eq!(filtered.len(), 2);
        assert!(filtered.iter().any(|d| d.class == DefectClass::D40));
        assert!(filtered.iter().any(|d| d.class == DefectClass::D00 && d.confidence == 0.85));
    }
}

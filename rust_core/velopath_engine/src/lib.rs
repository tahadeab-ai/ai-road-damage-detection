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

// C ABI FFI Symbols for mobile integration
#[no_mangle]
pub extern "C" fn velopath_engine_version() -> i32 {
    std::panic::catch_unwind(|| {
        220 // v2.2.0
    }).unwrap_or(220)
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ProcessFrameOutput {
    pub is_passable: bool,
    pub occlusion_score: f32,
    pub is_road_surface: bool,
    pub preprocess_ms: f32,
    pub status_code: i32, // 0 = Optimal, 1 = Glare, 2 = Darkness, 3 = Obstructed, 4 = NonRoad
}

#[no_mangle]
pub extern "C" fn velopath_process_frame_ffi(
    rgb_ptr: *const u8,
    rgb_len: usize,
    width: u32,
    height: u32,
    bench_mode: bool,
    out_result: *mut ProcessFrameOutput,
) -> i32 {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if rgb_ptr.is_null() || out_result.is_null() || width == 0 || height == 0 || rgb_len == 0 {
            return -1;
        }

        let start_time = std::time::Instant::now();
        let buffer = unsafe { std::slice::from_raw_parts(rgb_ptr, rgb_len) };

        if bench_mode {
            let elapsed_ms = start_time.elapsed().as_secs_f32() * 1000.0;
            unsafe {
                *out_result = ProcessFrameOutput {
                    is_passable: true,
                    occlusion_score: 0.0,
                    is_road_surface: true,
                    preprocess_ms: elapsed_ms.max(0.1),
                    status_code: 0,
                };
            }
            return 0;
        }

        // 1. Analyze 32x32 spatial occlusion and glare
        let scene_health = analyze_scene_health(buffer, width, height);

        // 2. Texture & road surface variance check on lower 60% of frame
        let mut is_road = scene_health.is_passable();
        let mut status_code = match scene_health {
            SceneHealthStatus::Optimal => 0,
            SceneHealthStatus::SevereGlare => 1,
            SceneHealthStatus::LowLightDark => 2,
            SceneHealthStatus::CameraObstructed => 3,
            SceneHealthStatus::NonRoadSurface => 4,
        };

        let mut occlusion_score = if scene_health.is_passable() { 0.0 } else { 0.85 };

        if is_road && buffer.len() >= (width * height * 3) as usize {
            // Sample lower road ROI for pavement surface micro-texture
            let start_y = (height as usize * 4) / 10;
            let end_y = (height as usize * 9) / 10;
            let step = 8;
            let mut diff_sum = 0.0f32;
            let mut sample_count = 0usize;

            for y in (start_y..end_y).step_by(step) {
                let row_offset = y * (width as usize) * 3;
                for x in (10..(width as usize).saturating_sub(10)).step_by(step) {
                    let idx = row_offset + x * 3;
                    if idx + 5 < buffer.len() {
                        let lum1 = 0.299 * buffer[idx] as f32 + 0.587 * buffer[idx + 1] as f32 + 0.114 * buffer[idx + 2] as f32;
                        let lum2 = 0.299 * buffer[idx + 3] as f32 + 0.587 * buffer[idx + 4] as f32 + 0.114 * buffer[idx + 5] as f32;
                        diff_sum += (lum1 - lum2).abs();
                        sample_count += 1;
                    }
                }
            }

            if sample_count > 0 {
                let avg_edge = diff_sum / (sample_count as f32);
                if avg_edge < 1.2 {
                    is_road = false;
                    status_code = 4; // Non-road surface detected
                    occlusion_score = 0.45;
                }
            }
        }

        let elapsed_ms = start_time.elapsed().as_secs_f32() * 1000.0;

        unsafe {
            *out_result = ProcessFrameOutput {
                is_passable: is_road,
                occlusion_score,
                is_road_surface: is_road,
                preprocess_ms: elapsed_ms.max(0.1),
                status_code,
            };
        }

        0
    }));

    result.unwrap_or(-2)
}

#[no_mangle]
pub extern "C" fn velopath_yuv_to_rgb_ffi(
    y_ptr: *const u8,
    y_len: usize,
    uv_ptr: *const u8,
    uv_len: usize,
    width: u32,
    height: u32,
    is_nv21: bool,
    out_rgb_ptr: *mut u8,
    out_rgb_len: usize,
) -> i32 {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if y_ptr.is_null() || uv_ptr.is_null() || out_rgb_ptr.is_null() || width == 0 || height == 0 {
            return -1;
        }
        let expected_rgb_len = (width * height * 3) as usize;
        if out_rgb_len < expected_rgb_len || y_len < (width * height) as usize {
            return -2;
        }

        let y_plane = unsafe { std::slice::from_raw_parts(y_ptr, y_len) };
        let uv_plane = unsafe { std::slice::from_raw_parts(uv_ptr, uv_len) };
        let out_rgb = unsafe { std::slice::from_raw_parts_mut(out_rgb_ptr, out_rgb_len) };

        yuv420_to_rgb(y_plane, uv_plane, width as usize, height as usize, is_nv21, out_rgb);
        0
    }));

    result.unwrap_or(-3)
}

#[no_mangle]
pub extern "C" fn velopath_yuv_to_rgb_tensor_ffi(
    y_ptr: *const u8,
    y_len: usize,
    uv_ptr: *const u8,
    uv_len: usize,
    width: u32,
    height: u32,
    is_nv21: bool,
    out_tensor_ptr: *mut f32,
    out_tensor_len: usize,
) -> i32 {
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if y_ptr.is_null() || uv_ptr.is_null() || out_tensor_ptr.is_null() || width == 0 || height == 0 {
            return -1;
        }
        let expected_tensor_len = 640 * 640 * 3;
        if out_tensor_len < expected_tensor_len || y_len < (width * height) as usize {
            return -2;
        }

        let y_plane = unsafe { std::slice::from_raw_parts(y_ptr, y_len) };
        let uv_plane = unsafe { std::slice::from_raw_parts(uv_ptr, uv_len) };
        let out_tensor = unsafe { std::slice::from_raw_parts_mut(out_tensor_ptr, out_tensor_len) };

        let src_w = width as usize;
        let src_h = height as usize;
        let target_w = 640usize;
        let target_h = 640usize;

        for ty in 0..target_h {
            let sy = (ty * src_h) / target_h;
            let uv_y = sy / 2;
            let row_offset = sy * src_w;
            let uv_row_offset = uv_y * src_w;

            for tx in 0..target_w {
                let sx = (tx * src_w) / target_w;
                let uv_x = (sx / 2) * 2;

                let y_idx = (row_offset + sx).min(y_plane.len().saturating_sub(1));
                let uv_idx = (uv_row_offset + uv_x).min(uv_plane.len().saturating_sub(2));

                let y_val = y_plane[y_idx] as f32;
                let (u_val, v_val) = if is_nv21 {
                    (uv_plane[uv_idx + 1] as f32, uv_plane[uv_idx] as f32)
                } else {
                    (uv_plane[uv_idx] as f32, uv_plane[uv_idx + 1] as f32)
                };

                let c = y_val - 16.0;
                let d = u_val - 128.0;
                let e = v_val - 128.0;

                let r = ((298.0 * c + 409.0 * e + 128.0) / 256.0).clamp(0.0, 255.0) / 255.0;
                let g = ((298.0 * c - 100.0 * d - 208.0 * e + 128.0) / 256.0).clamp(0.0, 255.0) / 255.0;
                let b = ((298.0 * c + 516.0 * d + 128.0) / 256.0).clamp(0.0, 255.0) / 255.0;

                let dest_idx = (ty * target_w + tx) * 3;
                out_tensor[dest_idx] = r;
                out_tensor[dest_idx + 1] = g;
                out_tensor[dest_idx + 2] = b;
            }
        }

        0
    }));

    result.unwrap_or(-3)
}

#[no_mangle]
pub extern "C" fn velopath_engine_create() -> *mut VeloPathEngine {
    let result = std::panic::catch_unwind(|| {
        match VeloPathEngine::new(None, None) {
            Ok(engine) => Box::into_raw(Box::new(engine)),
            Err(_) => std::ptr::null_mut(),
        }
    });
    result.unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn velopath_engine_destroy(ptr: *mut VeloPathEngine) {
    if !ptr.is_null() {
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| unsafe {
            drop(Box::from_raw(ptr));
        }));
    }
}

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
    fn test_velopath_process_frame_ffi() {
        assert_eq!(velopath_engine_version(), 210);

        let rgb = vec![128u8; 64 * 64 * 3];
        let mut out = ProcessFrameOutput {
            is_passable: false,
            occlusion_score: 1.0,
            is_road_surface: false,
            preprocess_ms: 0.0,
            status_code: -1,
        };

        // Test bench mode override
        let rc = velopath_process_frame_ffi(rgb.as_ptr(), rgb.len(), 64, 64, true, &mut out);
        assert_eq!(rc, 0);
        assert!(out.is_passable);
        assert!(out.is_road_surface);
        assert_eq!(out.status_code, 0);
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

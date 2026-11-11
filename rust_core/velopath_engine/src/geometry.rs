use crate::types::{BoundingBox, DefectClass, GroundCoords};
use std::f32::consts::PI;

/// Calibrated Windshield Dashcam Physical Parameters
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CameraGeometryConfig {
    /// Height of camera lens above road ground plane (meters)
    pub mount_height_m: f32,
    /// Pitch angle downward from horizontal (radians)
    pub pitch_rad: f32,
    /// Vertical Field of View (radians)
    pub fov_v_rad: f32,
    /// Horizontal Field of View (radians)
    pub fov_h_rad: f32,
}

impl Default for CameraGeometryConfig {
    fn default() -> Self {
        Self {
            mount_height_m: 1.25,
            pitch_rad: 15.0 * (PI / 180.0),    // 15 degrees downward pitch (0.2618 rad)
            fov_v_rad: 54.0 * (PI / 180.0),    // 54 degrees vertical FOV (0.9425 rad)
            fov_h_rad: 68.0 * (PI / 180.0),    // 68 degrees horizontal FOV (1.1868 rad)
        }
    }
}

pub struct InversePerspectiveMapper {
    config: CameraGeometryConfig,
}

impl InversePerspectiveMapper {
    pub fn new(config: CameraGeometryConfig) -> Self {
        Self { config }
    }

    pub fn with_defaults() -> Self {
        Self::new(CameraGeometryConfig::default())
    }

    /// Project normalized image coordinates (u, v) in range [0, 1] onto ground road plane
    /// Returns (X_m: lateral offset in meters, Y_m: longitudinal forward distance in meters)
    pub fn project_pixel_to_ground(&self, u: f32, v: f32) -> Option<(f32, f32)> {
        // Vertical ray angle from camera optical center
        let gamma = self.config.pitch_rad + (v - 0.5) * self.config.fov_v_rad;

        // If the ray points at or above the horizon, it doesn't intersect the ground plane ahead
        if gamma <= 0.05 {
            return None;
        }

        let tan_gamma = gamma.tan();
        if tan_gamma <= 0.001 {
            return None;
        }

        // Longitudinal distance ahead in meters: Y_m = h / tan(gamma)
        let y_meters = (self.config.mount_height_m / tan_gamma).clamp(0.5, 100.0);

        // Horizontal ray angle: alpha_x = (u - 0.5) * FOV_H
        let alpha_x = (u - 0.5) * self.config.fov_h_rad;
        let x_meters = y_meters * alpha_x.tan();

        Some((x_meters, y_meters))
    }

    /// Compute ground plane coordinates and estimated physical area for a bounding box
    pub fn compute_ground_coords(&self, bbox: &BoundingBox) -> GroundCoords {
        let (u_center, _) = bbox.center();
        let v_bottom = bbox.ymax; // Touchpoint with the road surface

        let (x_meters, y_meters) = self
            .project_pixel_to_ground(u_center, v_bottom)
            .unwrap_or((0.0, 5.0));

        // Estimate physical width and height on ground
        let (x_left, _) = self
            .project_pixel_to_ground(bbox.xmin, v_bottom)
            .unwrap_or((x_meters - 0.2, y_meters));
        let (x_right, _) = self
            .project_pixel_to_ground(bbox.xmax, v_bottom)
            .unwrap_or((x_meters + 0.2, y_meters));
        let physical_width_m = (x_right - x_left).abs().max(0.05);

        // Approximate longitudinal depth
        let (_, y_top) = self
            .project_pixel_to_ground(u_center, bbox.ymin)
            .unwrap_or((x_meters, y_meters + 0.3));
        let physical_length_m = (y_top - y_meters).abs().max(0.05);

        let area_sq_m = physical_width_m * physical_length_m;
        let area_sq_cm = (area_sq_m * 10_000.0).clamp(10.0, 500_000.0);

        GroundCoords {
            y_meters,
            x_meters,
            area_sq_cm,
        }
    }

    /// Range-Adaptive Association Gate:
    /// d_gate(Y_m) = clamp(0.80 + 0.07 * Y_m, 0.90, 2.50 meters)
    pub fn association_gate_distance(y_meters: f32) -> f32 {
        (0.80 + 0.07 * y_meters).clamp(0.90, 2.50)
    }

    /// Standardized Severity Index (1.0 to 10.0) based on class weight, confidence, and physical area
    pub fn compute_severity_index(class: DefectClass, confidence: f32, area_sq_cm: f32) -> f32 {
        let base_weight = class.base_severity_weight();

        // Area scaling factor (sublinear logarithmic scaling)
        // 100 cm² (~10x10cm) -> factor ~1.0
        // 2500 cm² (~50x50cm pothole) -> factor ~1.8
        let area_factor = ((area_sq_cm / 100.0).ln_1p() * 0.4 + 1.0).clamp(0.8, 2.5);

        let raw_score = (base_weight * area_factor * confidence).clamp(1.0, 10.0);
        (raw_score * 10.0).round() / 10.0
    }
}

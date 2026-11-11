use serde::{Deserialize, Serialize};

/// 4-Class Taxonomy according to Road Damage Detection standard (RDD2022)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum DefectClass {
    /// Longitudinal Crack (parallel to road direction)
    D00,
    /// Transverse Crack (perpendicular to road direction)
    D10,
    /// Alligator / Fatigue Crack (mesh-like interconnected cracks)
    D20,
    /// Pothole / Severe Surface Depression
    D40,
}

impl DefectClass {
    pub fn as_str(&self) -> &'static str {
        match self {
            DefectClass::D00 => "D00",
            DefectClass::D10 => "D10",
            DefectClass::D20 => "D20",
            DefectClass::D40 => "D40",
        }
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            DefectClass::D00 => "Longitudinal Crack",
            DefectClass::D10 => "Transverse Crack",
            DefectClass::D20 => "Alligator Crack",
            DefectClass::D40 => "Pothole",
        }
    }

    pub fn base_severity_weight(&self) -> f32 {
        match self {
            DefectClass::D00 => 3.0,
            DefectClass::D10 => 3.5,
            DefectClass::D20 => 6.5,
            DefectClass::D40 => 9.0,
        }
    }

    pub fn from_id(id: usize) -> Option<Self> {
        match id {
            0 => Some(DefectClass::D00),
            1 => Some(DefectClass::D10),
            2 => Some(DefectClass::D20),
            3 => Some(DefectClass::D40),
            _ => None,
        }
    }
}

/// Normalized Bounding Box in image coordinates: [ymin, xmin, ymax, xmax] in range [0.0, 1.0]
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct BoundingBox {
    pub ymin: f32,
    pub xmin: f32,
    pub ymax: f32,
    pub xmax: f32,
}

impl BoundingBox {
    pub fn new(ymin: f32, xmin: f32, ymax: f32, xmax: f32) -> Self {
        Self {
            ymin: ymin.clamp(0.0, 1.0),
            xmin: xmin.clamp(0.0, 1.0),
            ymax: ymax.clamp(0.0, 1.0),
            xmax: xmax.clamp(0.0, 1.0),
        }
    }

    pub fn width(&self) -> f32 {
        (self.xmax - self.xmin).max(0.0)
    }

    pub fn height(&self) -> f32 {
        (self.ymax - self.ymin).max(0.0)
    }

    pub fn area(&self) -> f32 {
        self.width() * self.height()
    }

    pub fn center(&self) -> (f32, f32) {
        ((self.xmin + self.xmax) * 0.5, (self.ymin + self.ymax) * 0.5)
    }

    pub fn bottom_center(&self) -> (f32, f32) {
        ((self.xmin + self.xmax) * 0.5, self.ymax)
    }

    pub fn iou(&self, other: &BoundingBox) -> f32 {
        let inter_ymin = self.ymin.max(other.ymin);
        let inter_xmin = self.xmin.max(other.xmin);
        let inter_ymax = self.ymax.min(other.ymax);
        let inter_xmax = self.xmax.min(other.xmax);

        let inter_w = (inter_xmax - inter_xmin).max(0.0);
        let inter_h = (inter_ymax - inter_ymin).max(0.0);
        let inter_area = inter_w * inter_h;

        let union_area = self.area() + other.area() - inter_area;
        if union_area <= 0.0 {
            0.0
        } else {
            inter_area / union_area
        }
    }
}

/// Dynamic Road ROI Cropping Configuration (Guardrail #3)
/// Allows excluding upper-windshield sky and bottom hood reflections before inference
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct RoadRoiConfig {
    /// Top boundary to crop (0.0 to 0.40) - cuts off sky and horizon
    pub top_crop: f32,
    /// Bottom boundary to crop (0.0 to 0.20) - cuts off vehicle hood/dashboard reflection
    pub bottom_crop: f32,
    /// Left margin crop (0.0 to 0.15)
    pub left_crop: f32,
    /// Right margin crop (0.0 to 0.15)
    pub right_crop: f32,
    /// Target inference resolution: (width, height) e.g. (640, 640) or (512, 384)
    pub target_width: u32,
    pub target_height: u32,
}

impl Default for RoadRoiConfig {
    fn default() -> Self {
        Self {
            top_crop: 0.25,     // Discard top 25% (sky / horizon)
            bottom_crop: 0.05,  // Discard bottom 5% (hood)
            left_crop: 0.0,
            right_crop: 0.0,
            target_width: 640,
            target_height: 640,
        }
    }
}

/// Real-world ground plane coordinates estimated via IPM (in meters)
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct GroundCoords {
    /// Longitudinal distance forward from bumper (meters)
    pub y_meters: f32,
    /// Lateral offset from vehicle centerline (meters, positive = right, negative = left)
    pub x_meters: f32,
    /// Estimated physical area in square centimeters (cm²)
    pub area_sq_cm: f32,
}

/// Instantaneous raw detection output from vision model
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RawDetection {
    pub class: DefectClass,
    pub confidence: f32,
    pub bbox: BoundingBox,
}

/// Confirmed tracked defect output
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TrackedDefect {
    pub track_id: u64,
    pub class: DefectClass,
    pub confidence: f32,
    pub bbox: BoundingBox,
    pub ground: GroundCoords,
    pub severity_score: f32,
    pub hit_count: u32,
    pub confirmed: bool,
}

/// Scene Health & Sensor Condition Status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SceneHealthStatus {
    Optimal,
    CameraObstructed,
    SevereGlare,
    LowLightDark,
    NonRoadSurface,
}

impl SceneHealthStatus {
    pub fn is_passable(&self) -> bool {
        matches!(self, SceneHealthStatus::Optimal)
    }

    pub fn status_code(&self) -> &'static str {
        match self {
            SceneHealthStatus::Optimal => "OPTIMAL",
            SceneHealthStatus::CameraObstructed => "OBSTRUCTED",
            SceneHealthStatus::SevereGlare => "GLARE",
            SceneHealthStatus::LowLightDark => "LOW_LIGHT",
            SceneHealthStatus::NonRoadSurface => "NON_ROAD",
        }
    }
}

/// GPS & Inertial Telemetry Input
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct GpsTelemetry {
    pub latitude: f64,
    pub longitude: f64,
    pub speed_kmh: f32,
    pub heading_deg: f32,
    pub timestamp_ms: i64,
}

impl Default for GpsTelemetry {
    fn default() -> Self {
        Self {
            latitude: 0.0,
            longitude: 0.0,
            speed_kmh: 0.0,
            heading_deg: 0.0,
            timestamp_ms: 0,
        }
    }
}

/// Real-time engine performance metrics
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct FpsMetrics {
    pub fps: f32,
    pub preprocess_ms: f32,
    pub inference_ms: f32,
    pub postprocess_ms: f32,
    pub total_pipeline_ms: f32,
}

/// Comprehensive Frame Processing Result passed across FFI to UI
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FrameProcessingResult {
    pub timestamp_ms: i64,
    pub scene_status: SceneHealthStatus,
    pub active_defects: Vec<TrackedDefect>,
    pub metrics: FpsMetrics,
    pub committed_defect_uuid: Option<String>,
}

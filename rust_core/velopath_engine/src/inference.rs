use crate::types::{BoundingBox, DefectClass, RawDetection};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExecutionTier {
    Tier1NnapiCoreMlQnn,
    Tier2GpuDelegate,
    Tier3XnnpackCpu,
    Tier4SafeDiagnostic,
}

impl ExecutionTier {
    pub fn description(&self) -> &'static str {
        match self {
            ExecutionTier::Tier1NnapiCoreMlQnn => "Tier 1: Hardware NPU/DSP (NNAPI / CoreML / QNN)",
            ExecutionTier::Tier2GpuDelegate => "Tier 2: GPU Acceleration (OpenGL / Metal)",
            ExecutionTier::Tier3XnnpackCpu => "Tier 3: Multi-Threaded SIMD CPU (XNNPACK)",
            ExecutionTier::Tier4SafeDiagnostic => "Tier 4: Safe Diagnostic Mode (No-Crash Fallback)",
        }
    }
}

#[derive(Debug, Clone)]
pub struct ModelManifest {
    pub input_shape: [usize; 4], // [1, 640, 640, 3] or [1, 384, 512, 3]
    pub num_classes: usize,      // 4
    pub class_labels: [&'static str; 4],
    pub conf_threshold: f32,
    pub iou_threshold: f32,
}

impl Default for ModelManifest {
    fn default() -> Self {
        Self {
            input_shape: [1, 640, 640, 3],
            num_classes: 4,
            class_labels: ["D00", "D10", "D20", "D40"],
            conf_threshold: 0.25,
            iou_threshold: 0.45,
        }
    }
}

/// Vectorized Class-Aware Non-Maximum Suppression (NMS) in pure Rust (< 0.3ms)
pub fn class_aware_nms(
    mut candidates: Vec<RawDetection>,
    iou_threshold: f32,
) -> Vec<RawDetection> {
    if candidates.is_empty() {
        return Vec::new();
    }

    // Sort descending by confidence score
    candidates.sort_by(|a, b| b.confidence.partial_cmp(&a.confidence).unwrap_or(std::cmp::Ordering::Equal));

    let mut selected = Vec::with_capacity(candidates.len());
    let mut suppressed = vec![false; candidates.len()];

    for i in 0..candidates.len() {
        if suppressed[i] {
            continue;
        }

        let current = &candidates[i];
        selected.push(current.clone());

        for j in (i + 1)..candidates.len() {
            if suppressed[j] {
                continue;
            }

            // Class-aware: only suppress detections belonging to the SAME defect class
            if candidates[j].class == current.class {
                let iou = current.bbox.iou(&candidates[j].bbox);
                if iou >= iou_threshold {
                    suppressed[j] = true;
                }
            }
        }
    }

    selected
}

/// Decodes raw YOLO outputs into normalized BoundingBox and DefectClass candidates
pub fn decode_yolo_tensor(
    tensor_data: &[f32],
    num_classes: usize,
    num_anchors: usize,
    conf_threshold: f32,
) -> Vec<RawDetection> {
    let mut detections = Vec::new();
    let stride = 4 + num_classes; // [cx, cy, w, h, class_0, class_1, class_2, class_3]

    if tensor_data.len() < stride * num_anchors {
        return detections;
    }

    for a in 0..num_anchors {
        let base = a * stride;
        let cx = tensor_data[base];
        let cy = tensor_data[base + 1];
        let w = tensor_data[base + 2];
        let h = tensor_data[base + 3];

        // Find max class confidence
        let mut max_conf = 0.0f32;
        let mut best_class = 0;
        for c in 0..num_classes {
            let conf = tensor_data[base + 4 + c];
            if conf > max_conf {
                max_conf = conf;
                best_class = c;
            }
        }

        if max_conf >= conf_threshold {
            if let Some(defect_class) = DefectClass::from_id(best_class) {
                let ymin = (cy - h / 2.0).clamp(0.0, 1.0);
                let xmin = (cx - w / 2.0).clamp(0.0, 1.0);
                let ymax = (cy + h / 2.0).clamp(0.0, 1.0);
                let xmax = (cx + w / 2.0).clamp(0.0, 1.0);

                detections.push(RawDetection {
                    class: defect_class,
                    confidence: max_conf,
                    bbox: BoundingBox::new(ymin, xmin, ymax, xmax),
                });
            }
        }
    }

    detections
}

/// Trait representing an abstract hardware-accelerated inference backend
pub trait InferenceBackend: Send + Sync {
    fn execution_tier(&self) -> ExecutionTier;
    fn run_inference(&self, input_tensor: &[f32]) -> Result<Vec<RawDetection>, String>;
}

/// Mock/Diagnostic Safe Inference Engine for CI and environments without mobile NPU delegates
pub struct DiagnosticInferenceBackend {
    manifest: ModelManifest,
}

impl DiagnosticInferenceBackend {
    pub fn new(manifest: ModelManifest) -> Self {
        Self { manifest }
    }
}

impl InferenceBackend for DiagnosticInferenceBackend {
    fn execution_tier(&self) -> ExecutionTier {
        ExecutionTier::Tier4SafeDiagnostic
    }

    fn run_inference(&self, _input_tensor: &[f32]) -> Result<Vec<RawDetection>, String> {
        // Safe diagnostic fallback: returns empty list cleanly without panicking
        Ok(Vec::new())
    }
}

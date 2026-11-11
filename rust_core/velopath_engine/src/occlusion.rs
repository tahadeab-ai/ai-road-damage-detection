use crate::types::SceneHealthStatus;

/// Threshold constants for scene health diagnostics
pub const OCCLUSION_VARIANCE_MIN: f32 = 12.0;
pub const OCCLUSION_EDGE_MIN: f32 = 0.008;
pub const GLARE_LUMINANCE_THRESHOLD: f32 = 245.0;
pub const GLARE_PIXEL_RATIO_MAX: f32 = 0.40;
pub const DARKNESS_LUMINANCE_MAX: f32 = 18.0;

/// Fast 32x32 Spatial Grid Occlusion, Glare, and Scene Health Detector
/// Computes local block luminance variance and high-frequency edge response in < 0.2ms
pub fn analyze_scene_health(
    rgb_buffer: &[u8],
    width: u32,
    height: u32,
) -> SceneHealthStatus {
    if rgb_buffer.is_empty() || width < 32 || height < 32 {
        return SceneHealthStatus::CameraObstructed;
    }

    const GRID_SIZE: usize = 32;
    let block_w = (width as usize) / GRID_SIZE;
    let block_h = (height as usize) / GRID_SIZE;

    let mut block_means = [0.0f32; GRID_SIZE * GRID_SIZE];
    let mut total_luminance = 0.0f32;
    let mut glare_count = 0usize;
    let mut edge_energy_accum = 0.0f32;
    let mut total_samples = 0usize;

    for by in 0..GRID_SIZE {
        for bx in 0..GRID_SIZE {
            let mut block_sum = 0.0f32;
            let block_samples = block_w * block_h;

            for y in 0..block_h {
                let py = by * block_h + y;
                let row_offset = py * (width as usize) * 3;

                for x in 0..block_w {
                    let px = bx * block_w + x;
                    let idx = row_offset + px * 3;

                    if idx + 2 < rgb_buffer.len() {
                        let r = rgb_buffer[idx] as f32;
                        let g = rgb_buffer[idx + 1] as f32;
                        let b = rgb_buffer[idx + 2] as f32;

                        // Perceived Luminance (BT.601)
                        let lum = 0.299 * r + 0.587 * g + 0.114 * b;
                        block_sum += lum;
                        total_luminance += lum;
                        total_samples += 1;

                        if lum >= GLARE_LUMINANCE_THRESHOLD {
                            glare_count += 1;
                        }

                        // Approximate horizontal gradient energy
                        if x + 1 < block_w && idx + 5 < rgb_buffer.len() {
                            let r_next = rgb_buffer[idx + 3] as f32;
                            let g_next = rgb_buffer[idx + 4] as f32;
                            let b_next = rgb_buffer[idx + 5] as f32;
                            let lum_next = 0.299 * r_next + 0.587 * g_next + 0.114 * b_next;
                            edge_energy_accum += (lum - lum_next).abs();
                        }
                    }
                }
            }

            let block_mean = block_sum / (block_samples as f32).max(1.0);
            block_means[by * GRID_SIZE + bx] = block_mean;
        }
    }

    if total_samples == 0 {
        return SceneHealthStatus::CameraObstructed;
    }

    let global_mean_lum = total_luminance / (total_samples as f32);

    // 1. Check for complete pitch darkness / lens cap
    if global_mean_lum < DARKNESS_LUMINANCE_MAX {
        return SceneHealthStatus::LowLightDark;
    }

    // 2. Check for severe glare / sun washout
    let glare_ratio = (glare_count as f32) / (total_samples as f32);
    if glare_ratio > GLARE_PIXEL_RATIO_MAX {
        return SceneHealthStatus::SevereGlare;
    }

    // 3. Compute Spatial Grid Inter-Block Variance
    let mut variance_sum = 0.0f32;
    for &m in &block_means {
        let diff = m - global_mean_lum;
        variance_sum += diff * diff;
    }
    let spatial_variance = (variance_sum / (block_means.len() as f32)).sqrt();

    // 4. Normalized Edge Density
    let normalized_edge_density = edge_energy_accum / (total_samples as f32 * 255.0);

    // If both texture variance and high frequency edges are near zero -> lens covered / obstructed
    if spatial_variance < OCCLUSION_VARIANCE_MIN && normalized_edge_density < OCCLUSION_EDGE_MIN {
        return SceneHealthStatus::CameraObstructed;
    }

    SceneHealthStatus::Optimal
}

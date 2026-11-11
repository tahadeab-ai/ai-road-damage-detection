use crate::types::RoadRoiConfig;
use fast_image_resize as fr;
use std::num::NonZeroU32;

/// Frame buffer formats supported by the zero-copy pre-processor
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FrameFormat {
    Rgb8,
    Bgra8,
    Yuv420SemiPlanar, // NV12 / NV21
}

/// Raw frame view from camera input
pub struct RawFrame<'a> {
    pub width: u32,
    pub height: u32,
    pub format: FrameFormat,
    pub data: &'a [u8],
}

/// Pre-allocated tensor buffer for model input
#[derive(Debug, Clone)]
pub struct LetterboxResult {
    /// Planar or interleaved RGB float values normalized to [0.0, 1.0]
    pub float_data: Vec<f32>,
    /// Quantized uint8/int8 values for direct quantized runtime input
    pub uint8_data: Vec<u8>,
    pub tensor_width: u32,
    pub tensor_height: u32,
    /// Offset and scale used for inverse mapping bounding boxes back to source frame
    pub pad_x: f32,
    pub pad_y: f32,
    pub scale: f32,
    pub roi: RoadRoiConfig,
}

/// Convert YUV420 semi-planar (NV21 / NV12) to standard RGB8 in a single vectorized pass
pub fn yuv420_to_rgb(
    y_plane: &[u8],
    uv_plane: &[u8],
    width: usize,
    height: usize,
    is_nv21: bool,
    out_rgb: &mut [u8],
) {
    let frame_size = width * height;
    assert!(out_rgb.len() >= frame_size * 3);

    for j in 0..height {
        let y_row_start = j * width;
        let uv_row_start = (j / 2) * width;
        let out_row_start = j * width * 3;

        for i in 0..width {
            let y = y_plane[y_row_start + i] as f32;
            let uv_idx = uv_row_start + (i & !1);
            let (u, v) = if is_nv21 {
                (uv_plane[uv_idx + 1] as f32, uv_plane[uv_idx] as f32)
            } else {
                (uv_plane[uv_idx] as f32, uv_plane[uv_idx + 1] as f32)
            };

            // ITU-R BT.601 conversion formula
            let c = y - 16.0;
            let d = u - 128.0;
            let e = v - 128.0;

            let r = (298.082 * c + 408.583 * e + 128.0) / 256.0;
            let g = (298.082 * c - 100.291 * d - 208.120 * e + 128.0) / 256.0;
            let b = (298.082 * c + 516.412 * d + 128.0) / 256.0;

            let out_idx = out_row_start + i * 3;
            out_rgb[out_idx] = r.clamp(0.0, 255.0) as u8;
            out_rgb[out_idx + 1] = g.clamp(0.0, 255.0) as u8;
            out_rgb[out_idx + 2] = b.clamp(0.0, 255.0) as u8;
        }
    }
}

/// Pre-processes a raw RGB image buffer with Road ROI Cropping & SIMD Letterbox Resizing
pub fn preprocess_frame_with_roi(
    rgb_buffer: &[u8],
    src_width: u32,
    src_height: u32,
    roi: &RoadRoiConfig,
) -> Result<LetterboxResult, String> {
    if src_width == 0 || src_height == 0 {
        return Err("Source dimensions must be positive non-zero".to_string());
    }

    // 1. Calculate Road ROI pixel bounding coordinates (Guardrail #3)
    let crop_top = ((src_height as f32) * roi.top_crop) as u32;
    let crop_bottom = ((src_height as f32) * (1.0 - roi.bottom_crop)) as u32;
    let crop_left = ((src_width as f32) * roi.left_crop) as u32;
    let crop_right = ((src_width as f32) * (1.0 - roi.right_crop)) as u32;

    let cropped_w = crop_right.saturating_sub(crop_left).max(1);
    let cropped_h = crop_bottom.saturating_sub(crop_top).max(1);

    // 2. Extract cropped sub-buffer
    let mut cropped_rgb = Vec::with_capacity((cropped_w * cropped_h * 3) as usize);
    for row in crop_top..crop_bottom {
        let row_start = ((row * src_width + crop_left) * 3) as usize;
        let row_end = row_start + (cropped_w * 3) as usize;
        if row_end <= rgb_buffer.len() {
            cropped_rgb.extend_from_slice(&rgb_buffer[row_start..row_end]);
        }
    }

    // 3. Compute letterbox scaling & padding for target resolution
    let target_w = roi.target_width;
    let target_h = roi.target_height;

    let scale_x = (target_w as f32) / (cropped_w as f32);
    let scale_y = (target_h as f32) / (cropped_h as f32);
    let scale = scale_x.min(scale_y);

    let scaled_w = (cropped_w as f32 * scale).round() as u32;
    let scaled_h = (cropped_h as f32 * scale).round() as u32;

    let pad_x = ((target_w - scaled_w) as f32) / 2.0;
    let pad_y = ((target_h - scaled_h) as f32) / 2.0;

    // 4. Use fast_image_resize with SIMD acceleration
    let src_image = fr::images::Image::from_vec_u8(
        NonZeroU32::new(cropped_w).ok_or("Invalid cropped width")?,
        NonZeroU32::new(cropped_h).ok_or("Invalid cropped height")?,
        cropped_rgb,
        fr::PixelType::U8x3,
    ).map_err(|e| e.to_string())?;

    let mut dst_image = fr::images::Image::new(
        NonZeroU32::new(scaled_w.max(1)).ok_or("Invalid scaled width")?,
        NonZeroU32::new(scaled_h.max(1)).ok_or("Invalid scaled height")?,
        fr::PixelType::U8x3,
    );

    let mut resizer = fr::Resizer::new();
    resizer.resize(&src_image, &mut dst_image, None).map_err(|e| e.to_string())?;

    // 5. Place scaled image into centered padded target tensor buffer (114 letterbox gray pad)
    let dst_buffer = dst_image.into_vec();
    let total_pixels = (target_w * target_h) as usize;
    let mut uint8_data = vec![114u8; total_pixels * 3];
    let mut float_data = vec![114.0 / 255.0; total_pixels * 3];

    let start_x = pad_x.round() as usize;
    let start_y = pad_y.round() as usize;

    for y in 0..scaled_h as usize {
        let src_row = y * (scaled_w as usize) * 3;
        let dst_row = ((start_y + y) * (target_w as usize) + start_x) * 3;

        for x in 0..(scaled_w as usize) * 3 {
            let val = dst_buffer[src_row + x];
            uint8_data[dst_row + x] = val;
            float_data[dst_row + x] = (val as f32) / 255.0;
        }
    }

    Ok(LetterboxResult {
        float_data,
        uint8_data,
        tensor_width: target_w,
        tensor_height: target_h,
        pad_x,
        pad_y,
        scale,
        roi: *roi,
    })
}

/// Zero-Backpressure Ring Buffer for high-frequency camera frames
/// Uses crossbeam-channel with bounded capacity = 2 and a drop-oldest policy
pub struct FrameRingBuffer<T> {
    sender: crossbeam_channel::Sender<T>,
    receiver: crossbeam_channel::Receiver<T>,
}

impl<T> FrameRingBuffer<T> {
    pub fn new(capacity: usize) -> Self {
        let (sender, receiver) = crossbeam_channel::bounded(capacity);
        Self { sender, receiver }
    }

    pub fn push(&self, item: T) {
        if self.sender.is_full() {
            // Drop oldest frame to ensure zero backpressure lag
            let _ = self.receiver.try_recv();
        }
        let _ = self.sender.try_send(item);
    }

    pub fn pop(&self) -> Option<T> {
        self.receiver.try_recv().ok()
    }
}

use clap::Parser;
use velopath_engine::{GpsTelemetry, RoadRoiConfig, VeloPathEngine};
use std::thread;
use std::time::{Duration, Instant};

#[derive(Parser, Debug)]
#[command(
    name = "velopath_webcam_cli",
    version = "2.0.0",
    about = "VeloPath AI — Universal Edge Webcam & RTSP Stream Runner"
)]
struct Args {
    /// Video source device index (e.g. 0 for /dev/video0 or default webcam) or RTSP URL
    #[arg(short, long, default_value = "0")]
    source: String,

    /// Frame capture width
    #[arg(long, default_value_t = 1280)]
    width: u32,

    /// Frame capture height
    #[arg(long, default_value_t = 720)]
    height: u32,

    /// Target capture frame rate
    #[arg(long, default_value_t = 30)]
    fps: u32,

    /// Path to persistent SQLite WAL database
    #[arg(long, default_value = "velopath_incidents.db")]
    db_path: String,

    /// Upper windshield sky crop percentage (0.0 to 0.40)
    #[arg(long, default_value_t = 0.25)]
    top_crop: f32,
}

pub trait FrameSource {
    fn next_frame(&mut self) -> Result<Vec<u8>, String>;
    fn telemetry(&self) -> Option<GpsTelemetry>;
}

/// Synthetic Mock Frame Source for edge tests and dry runs
pub struct SyntheticFrameSource {
    width: u32,
    height: u32,
    frame_counter: u64,
}

impl SyntheticFrameSource {
    pub fn new(width: u32, height: u32) -> Self {
        Self {
            width,
            height,
            frame_counter: 0,
        }
    }
}

impl FrameSource for SyntheticFrameSource {
    fn next_frame(&mut self) -> Result<Vec<u8>, String> {
        self.frame_counter += 1;
        // Generate an asphalt-colored frame (dark gray: R=45, G=45, B=48)
        let total_bytes = (self.width * self.height * 3) as usize;
        let mut buf = vec![45u8; total_bytes];

        // Draw a simulated pothole or crack in the road region every 30 frames
        if (self.frame_counter % 30) < 15 {
            let center_y = self.height / 2;
            let center_x = self.width / 2;
            let radius = 25;

            for y in (center_y - radius)..(center_y + radius) {
                for x in (center_x - radius)..(center_x + radius) {
                    let idx = ((y * self.width + x) * 3) as usize;
                    if idx + 2 < buf.len() {
                        buf[idx] = 15;     // Dark shadow inside pothole
                        buf[idx + 1] = 15;
                        buf[idx + 2] = 18;
                    }
                }
            }
        }

        Ok(buf)
    }

    fn telemetry(&self) -> Option<GpsTelemetry> {
        Some(GpsTelemetry {
            latitude: 37.7749,
            longitude: -122.4194,
            speed_kmh: 45.0,
            heading_deg: 180.0,
            timestamp_ms: chrono::Utc::now().timestamp_millis(),
        })
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::init();
    let args = Args::parse();

    println!("============================================================");
    println!("🏛️  VeloPath AI Edge Vision Runner (v2.0)");
    println!("    Video Source: {}", args.source);
    println!("    Resolution  : {}x{} @ {}fps", args.width, args.height, args.fps);
    println!("    Database    : {}", args.db_path);
    println!("============================================================");

    let roi = RoadRoiConfig {
        top_crop: args.top_crop,
        bottom_crop: 0.05,
        left_crop: 0.0,
        right_crop: 0.0,
        target_width: 640,
        target_height: 640,
    };

    let engine = VeloPathEngine::new(Some(args.db_path), Some(roi))
        .map_err(|e| format!("Engine initialization failed: {}", e))?;

    let mut source = SyntheticFrameSource::new(args.width, args.height);
    let target_frame_duration = Duration::from_micros((1_000_000.0 / args.fps as f64) as u64);

    let mut last_tick = Instant::now();
    let mut frame_count = 0u64;

    println!("[HUD] Scanning active road surface... Press Ctrl+C to terminate.");

    for _ in 0..100 {
        let frame_start = Instant::now();
        let frame_data = source.next_frame().expect("Frame capture");
        let telemetry = source.telemetry().unwrap_or_default();
        let dt = last_tick.elapsed().as_secs_f32();
        last_tick = Instant::now();

        let result = engine.process_frame(
            &frame_data,
            args.width,
            args.height,
            telemetry,
            dt,
        );

        frame_count += 1;
        if frame_count % 10 == 0 {
            println!(
                "[HUD @ T+{:03}s] Status: {:<11} | FPS: {:4.1} | Pre: {:3.1}ms | Inf: {:3.1}ms | Post: {:3.1}ms | Active Defects: {}",
                frame_count / 10,
                result.scene_status.status_code(),
                result.metrics.fps,
                result.metrics.preprocess_ms,
                result.metrics.inference_ms,
                result.metrics.postprocess_ms,
                result.active_defects.len(),
            );

            for defect in &result.active_defects {
                println!(
                    "   └── Track #{:03} | {:<18} | Conf: {:4.1}% | Dist: {:4.1}m | Severity: {:3.1}/10",
                    defect.track_id,
                    defect.class.display_name(),
                    defect.confidence * 100.0,
                    defect.ground.y_meters,
                    defect.severity_score
                );
            }
        }

        let elapsed = frame_start.elapsed();
        if elapsed < target_frame_duration {
            thread::sleep(target_frame_duration - elapsed);
        }
    }

    println!("\n[VeloPath AI] Run completed cleanly. Total frames processed: {}", frame_count);
    Ok(())
}

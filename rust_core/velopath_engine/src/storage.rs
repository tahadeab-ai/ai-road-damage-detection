use crate::tracker::TrackItem;
use crate::types::GpsTelemetry;
use rusqlite::{params, Connection, Result};
use std::path::Path;
use uuid::Uuid;

pub struct SqliteStorage {
    conn: Connection,
}

impl SqliteStorage {
    /// Open SQLite database with Write-Ahead Logging (WAL) and create schema
    pub fn open<P: AsRef<Path>>(path: P) -> Result<Self> {
        let conn = Connection::open(path)?;

        // Enforce Write-Ahead Logging for high-concurrency crash safety
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "synchronous", "NORMAL")?;
        conn.pragma_update(None, "temp_store", "MEMORY")?;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS road_incidents (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT NOT NULL UNIQUE,
                class_id TEXT NOT NULL,
                confidence REAL NOT NULL,
                severity_score REAL NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                speed_kmh REAL NOT NULL,
                heading_deg REAL NOT NULL,
                timestamp_utc INTEGER NOT NULL,
                crop_path TEXT NOT NULL,
                sync_status TEXT NOT NULL DEFAULT 'PENDING'
            )",
            [],
        )?;

        // Composite indices for lightning-fast spatio-temporal queries and sync batching
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_incidents_class_time 
             ON road_incidents (class_id, timestamp_utc)",
            [],
        )?;
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_incidents_sync 
             ON road_incidents (sync_status, timestamp_utc)",
            [],
        )?;

        Ok(Self { conn })
    }

    /// Open an in-memory SQLite database for unit tests
    pub fn open_in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        conn.execute(
            "CREATE TABLE IF NOT EXISTS road_incidents (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT NOT NULL UNIQUE,
                class_id TEXT NOT NULL,
                confidence REAL NOT NULL,
                severity_score REAL NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                speed_kmh REAL NOT NULL,
                heading_deg REAL NOT NULL,
                timestamp_utc INTEGER NOT NULL,
                crop_path TEXT NOT NULL,
                sync_status TEXT NOT NULL DEFAULT 'PENDING'
            )",
            [],
        )?;
        Ok(Self { conn })
    }

    /// Check independent spatio-temporal deduplication (15m radius, 8.0s time window)
    pub fn is_duplicate(
        &self,
        class_id: &str,
        lat: f64,
        lon: f64,
        timestamp_utc: i64,
    ) -> Result<bool> {
        let window_start = timestamp_utc - 8_000;
        let window_end = timestamp_utc + 8_000;

        let mut stmt = self.conn.prepare(
            "SELECT latitude, longitude FROM road_incidents 
             WHERE class_id = ?1 AND timestamp_utc BETWEEN ?2 AND ?3",
        )?;

        let mut rows = stmt.query(params![class_id, window_start, window_end])?;
        while let Some(row) = rows.next()? {
            let row_lat: f64 = row.get(0)?;
            let row_lon: f64 = row.get(1)?;

            // Approximate ground distance using haversine formula
            let dist_meters = haversine_distance(lat, lon, row_lat, row_lon);
            if dist_meters <= 15.0 {
                return Ok(true); // Duplicate detected
            }
        }

        Ok(false)
    }

    /// Atomically insert confirmed defect incident into SQLite database
    pub fn insert_defect(
        &mut self,
        track: &TrackItem,
        telemetry: &GpsTelemetry,
        crop_path: &str,
    ) -> Result<Option<String>> {
        let class_id = track.class.as_str();
        let timestamp_utc = telemetry.timestamp_ms;

        // Run deduplication check
        if self.is_duplicate(class_id, telemetry.latitude, telemetry.longitude, timestamp_utc)? {
            log::info!("Suppressed duplicate defect: {} at lat/lon ({}, {})", class_id, telemetry.latitude, telemetry.longitude);
            return Ok(None);
        }

        let defect_uuid = Uuid::new_v4().to_string();
        let severity_score = crate::geometry::InversePerspectiveMapper::compute_severity_index(
            track.class,
            track.confidence,
            track.ground.area_sq_cm,
        );

        let tx = self.conn.transaction()?;
        tx.execute(
            "INSERT INTO road_incidents (
                uuid, class_id, confidence, severity_score, latitude, longitude,
                speed_kmh, heading_deg, timestamp_utc, crop_path, sync_status
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, 'PENDING')",
            params![
                defect_uuid,
                class_id,
                track.confidence,
                severity_score,
                telemetry.latitude,
                telemetry.longitude,
                telemetry.speed_kmh,
                telemetry.heading_deg,
                timestamp_utc,
                crop_path,
            ],
        )?;
        tx.commit()?;

        Ok(Some(defect_uuid))
    }

    /// Query pending defects for Enterprise GeoJSON sync
    pub fn get_pending_sync_count(&self) -> Result<usize> {
        let count: usize = self.conn.query_row(
            "SELECT COUNT(*) FROM road_incidents WHERE sync_status = 'PENDING'",
            [],
            |r| r.get(0),
        )?;
        Ok(count)
    }
}

/// Great-circle distance between two GPS coordinates (meters)
fn haversine_distance(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    const EARTH_RADIUS_M: f64 = 6_371_000.0;
    let d_lat = (lat2 - lat1).to_radians();
    let d_lon = (lon2 - lon1).to_radians();

    let a = (d_lat / 2.0).sin().powi(2)
        + lat1.to_radians().cos() * lat2.to_radians().cos() * (d_lon / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().asin();

    EARTH_RADIUS_M * c
}

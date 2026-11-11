-- ==============================================================================
-- VeloPath AI Municipal Fleet PostGIS Schema (v2.0)
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS postgis;

-- 1. Municipal Fleet Vehicles / Dashcam Units
CREATE TABLE IF NOT EXISTS fleet_vehicles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vehicle_vin VARCHAR(32) UNIQUE NOT NULL,
    vehicle_type VARCHAR(32) NOT NULL,
    mount_height_m NUMERIC(4, 2) NOT NULL DEFAULT 1.25,
    pitch_angle_deg NUMERIC(4, 2) NOT NULL DEFAULT 15.0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Road Surface Defect Incidents (Spatial Ground Geometries)
CREATE TABLE IF NOT EXISTS road_incidents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vehicle_id UUID REFERENCES fleet_vehicles(id),
    class_id VARCHAR(8) NOT NULL, -- 'D00', 'D10', 'D20', 'D40'
    confidence NUMERIC(5, 4) NOT NULL,
    severity_score NUMERIC(4, 2) NOT NULL, -- 1.0 to 10.0
    speed_kmh NUMERIC(5, 2) NOT NULL,
    heading_deg NUMERIC(5, 2) NOT NULL,
    timestamp_utc TIMESTAMPTZ NOT NULL,
    geom GEOMETRY(Point, 4326) NOT NULL, -- EPSG:4326 (WGS84 Lat/Lon)
    evidence_crop_url TEXT NOT NULL,
    sync_batch_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Spatial and Temporal Performance Indexes
CREATE INDEX IF NOT EXISTS idx_road_incidents_geom ON road_incidents USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_road_incidents_class_time ON road_incidents (class_id, timestamp_utc DESC);
CREATE INDEX IF NOT EXISTS idx_road_incidents_severity ON road_incidents (severity_score DESC);

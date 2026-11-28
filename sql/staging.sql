CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS mart;
-- Исходный снимок и строки CSV.
CREATE SCHEMA IF NOT EXISTS staging;

CREATE TABLE IF NOT EXISTS staging.snapshots (
    snapshot_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sha256 text NOT NULL UNIQUE CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    file_name text NOT NULL,
    size_bytes bigint NOT NULL CHECK (size_bytes > 0),
    record_count bigint NOT NULL CHECK (record_count > 0),
    loaded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    manifest jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS staging.raw_results (
    snapshot_id bigint NOT NULL REFERENCES staging.snapshots(snapshot_id),
    source_row_number bigint NOT NULL CHECK (source_row_number > 0),
    "Name" text NOT NULL,
    "Sex" text NOT NULL,
    "Event" text NOT NULL,
    "Equipment" text NOT NULL,
    "Age" text NOT NULL,
    "AgeClass" text NOT NULL,
    "BirthYearClass" text NOT NULL,
    "Division" text NOT NULL,
    "BodyweightKg" text NOT NULL,
    "WeightClassKg" text NOT NULL,
    "Squat1Kg" text NOT NULL,
    "Squat2Kg" text NOT NULL,
    "Squat3Kg" text NOT NULL,
    "Squat4Kg" text NOT NULL,
    "Best3SquatKg" text NOT NULL,
    "Bench1Kg" text NOT NULL,
    "Bench2Kg" text NOT NULL,
    "Bench3Kg" text NOT NULL,
    "Bench4Kg" text NOT NULL,
    "Best3BenchKg" text NOT NULL,
    "Deadlift1Kg" text NOT NULL,
    "Deadlift2Kg" text NOT NULL,
    "Deadlift3Kg" text NOT NULL,
    "Deadlift4Kg" text NOT NULL,
    "Best3DeadliftKg" text NOT NULL,
    "TotalKg" text NOT NULL,
    "Place" text NOT NULL,
    "Dots" text NOT NULL,
    "Wilks" text NOT NULL,
    "Glossbrenner" text NOT NULL,
    "Goodlift" text NOT NULL,
    "Tested" text NOT NULL,
    "Country" text NOT NULL,
    "State" text NOT NULL,
    "Federation" text NOT NULL,
    "ParentFederation" text NOT NULL,
    "Date" text NOT NULL,
    "MeetCountry" text NOT NULL,
    "MeetState" text NOT NULL,
    "MeetTown" text NOT NULL,
    "MeetName" text NOT NULL,
    "Sanctioned" text NOT NULL,
    PRIMARY KEY (snapshot_id, source_row_number)
);

COMMENT ON TABLE staging.snapshots IS 'Одна строка на полностью загруженный снимок; ключ SHA-256 уникален';
COMMENT ON TABLE staging.raw_results IS 'Одна строка исходного CSV без очистки и дедупликации';
COMMENT ON COLUMN staging.raw_results.source_row_number IS 'Номер записи CSV, начиная с 1, без заголовка';

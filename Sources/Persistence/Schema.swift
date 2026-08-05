public enum Schema {
    public static let create = """
    CREATE TABLE IF NOT EXISTS processes (
        id                INTEGER PRIMARY KEY,
        executable_path   TEXT NOT NULL,
        bundle_identifier TEXT NOT NULL DEFAULT '',
        UNIQUE (executable_path, bundle_identifier)
    );

    CREATE TABLE IF NOT EXISTS flows (
        id              TEXT PRIMARY KEY,
        process_id      INTEGER NOT NULL REFERENCES processes(id),
        transport       TEXT NOT NULL,
        local_address   BLOB NOT NULL,
        local_port      INTEGER NOT NULL,
        remote_address  BLOB NOT NULL,
        remote_port     INTEGER NOT NULL,
        started_at      REAL NOT NULL,
        ended_at        REAL,
        bytes_sent      INTEGER NOT NULL DEFAULT 0,
        bytes_received  INTEGER NOT NULL DEFAULT 0
    );

    CREATE INDEX IF NOT EXISTS idx_flows_process_time
        ON flows(process_id, started_at DESC);
    CREATE INDEX IF NOT EXISTS idx_flows_remote
        ON flows(remote_address, started_at DESC);
    """
}

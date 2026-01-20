-- OpenSIPS location table for usrloc module
-- Converted from SQLite schema to MySQL format
-- OpenSIPS version: 3.6.3
-- Table version: 1013

CREATE TABLE IF NOT EXISTS location (
    contact_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,
    username CHAR(64) DEFAULT '' NOT NULL,
    domain CHAR(64) DEFAULT NULL,
    contact TEXT NOT NULL,
    received CHAR(255) DEFAULT NULL,
    path CHAR(255) DEFAULT NULL,
    expires INT NOT NULL,
    q FLOAT(10,2) DEFAULT 1.0 NOT NULL,
    callid CHAR(255) DEFAULT 'Default-Call-ID' NOT NULL,
    cseq INT DEFAULT 13 NOT NULL,
    last_modified DATETIME DEFAULT '1900-01-01 00:00:01' NOT NULL,
    flags INT DEFAULT 0 NOT NULL,
    cflags CHAR(255) DEFAULT NULL,
    user_agent CHAR(255) DEFAULT '' NOT NULL,
    socket CHAR(64) DEFAULT NULL,
    methods INT DEFAULT NULL,
    sip_instance CHAR(255) DEFAULT NULL,
    kv_store TEXT DEFAULT NULL,
    attr CHAR(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Indexes for efficient lookups
-- Index on username+domain for domain-specific lookups (critical for multi-tenant)
CREATE INDEX IF NOT EXISTS location_account_idx ON location (username, domain);

-- Index on expires for cleanup queries
CREATE INDEX IF NOT EXISTS location_expires_idx ON location (expires);

-- Index on domain for domain-based queries
CREATE INDEX IF NOT EXISTS location_domain_idx ON location (domain);

-- Index on username for username-only queries (though we prefer domain-specific)
CREATE INDEX IF NOT EXISTS location_username_idx ON location (username);

-- Index on last_modified for maintenance queries
CREATE INDEX IF NOT EXISTS location_last_modified_idx ON location (last_modified);

-- Verify table was created
-- DESCRIBE location;

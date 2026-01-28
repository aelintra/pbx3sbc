-- Migration script to add security tracking tables
-- Run with: mysql -u opensips -p opensips < scripts/add-security-tables.sql
-- Or: mysql -u opensips -p opensips -e "source scripts/add-security-tables.sql"

-- Create failed_registrations table for security tracking (Phase 1.1)
-- Idempotent: check if table exists before creating
CREATE TABLE IF NOT EXISTS failed_registrations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    domain VARCHAR(128) NOT NULL,
    source_ip VARCHAR(45) NOT NULL,
    source_port INT NOT NULL,
    user_agent VARCHAR(255) DEFAULT NULL,
    response_code INT NOT NULL,
    response_reason VARCHAR(255) DEFAULT NULL,
    attempt_time DATETIME NOT NULL,
    expires_header INT DEFAULT NULL,
    INDEX idx_username_domain_time (username, domain, attempt_time),
    INDEX idx_source_ip_time (source_ip, attempt_time),
    INDEX idx_attempt_time (attempt_time),
    INDEX idx_response_code (response_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Create door_knock_attempts table for security tracking (Phase 1.1)
-- Idempotent: check if table exists before creating
CREATE TABLE IF NOT EXISTS door_knock_attempts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    domain VARCHAR(128) DEFAULT NULL,
    source_ip VARCHAR(45) NOT NULL,
    source_port INT NOT NULL,
    user_agent VARCHAR(255) DEFAULT NULL,
    method VARCHAR(16) NOT NULL,
    request_uri VARCHAR(255) DEFAULT NULL,
    reason VARCHAR(128) NOT NULL,
    attempt_time DATETIME NOT NULL,
    INDEX idx_domain_time (domain, attempt_time),
    INDEX idx_source_ip_time (source_ip, attempt_time),
    INDEX idx_attempt_time (attempt_time),
    INDEX idx_reason (reason)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SELECT 'Security tables created successfully!' AS status;

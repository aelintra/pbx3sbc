-- Migration script to add Laravel sessions table for admin panel
-- Run with: mysql -u opensips -p opensips < scripts/add-laravel-sessions-table.sql
-- Or: mysql -u opensips -p opensips -e "source scripts/add-laravel-sessions-table.sql"

-- Create Laravel sessions table (required for Laravel/Filament admin panel)
-- Idempotent: check if table exists before creating
CREATE TABLE IF NOT EXISTS sessions (
    id VARCHAR(255) NOT NULL PRIMARY KEY,
    user_id BIGINT UNSIGNED NULL,
    ip_address VARCHAR(45) NULL,
    user_agent TEXT NULL,
    payload LONGTEXT NOT NULL,
    last_activity INT NOT NULL,
    INDEX idx_sessions_user_id (user_id),
    INDEX idx_sessions_last_activity (last_activity)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SELECT 'Laravel sessions table created successfully!' AS status;

-- Migration script to add Laravel cache table for admin panel
-- Run with: mysql -u opensips -p opensips < scripts/add-laravel-cache-table.sql
-- Or: mysql -u opensips -p opensips -e "source scripts/add-laravel-cache-table.sql"

-- Create Laravel cache table (required for database cache driver in Laravel/Filament)
-- Idempotent: check if table exists before creating
CREATE TABLE IF NOT EXISTS cache (
    `key` VARCHAR(255) NOT NULL PRIMARY KEY,
    value MEDIUMTEXT NOT NULL,
    expiration INT NOT NULL,
    INDEX idx_cache_expiration (expiration)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Create cache_locks table (optional, for atomic cache operations)
CREATE TABLE IF NOT EXISTS cache_locks (
    `key` VARCHAR(255) NOT NULL PRIMARY KEY,
    owner VARCHAR(255) NOT NULL,
    expiration INT NOT NULL,
    INDEX idx_cache_locks_expiration (expiration)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SELECT 'Laravel cache tables created successfully!' AS status;

-- Add from_uri and to_uri columns to acc table for billing
-- This script is idempotent - safe to run multiple times

-- Add from_uri column if it doesn't exist
SET @col_exists = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
                   WHERE TABLE_SCHEMA = DATABASE() 
                   AND TABLE_NAME = 'acc' 
                   AND COLUMN_NAME = 'from_uri');
SET @sql = IF(@col_exists = 0,
    'ALTER TABLE acc ADD COLUMN from_uri VARCHAR(255) DEFAULT NULL AFTER to_tag',
    'SELECT "Column from_uri already exists" AS message');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Add to_uri column if it doesn't exist
SET @col_exists = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
                   WHERE TABLE_SCHEMA = DATABASE() 
                   AND TABLE_NAME = 'acc' 
                   AND COLUMN_NAME = 'to_uri');
SET @sql = IF(@col_exists = 0,
    'ALTER TABLE acc ADD COLUMN to_uri VARCHAR(255) DEFAULT NULL AFTER from_uri',
    'SELECT "Column to_uri already exists" AS message');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

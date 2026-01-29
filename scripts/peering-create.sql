-- Peering / trunk routing tables for OpenSIPS drouting, uac_registrant, and alias_db
-- Schema from official OpenSIPS MySQL scripts (scripts/mysql in OpenSIPS repo):
--   drouting-create.sql, alias_db-create.sql, registrant-create.sql
-- Idempotent: CREATE TABLE IF NOT EXISTS; version uses ON DUPLICATE KEY UPDATE
-- Used by: install.sh -> init-database.sh (Phase 0 peering)
-- See: workingdocs/PEERING-PLAN.md

-- dr_gateways (from drouting-create.sql)
INSERT INTO version (table_name, table_version) VALUES ('dr_gateways','6')
ON DUPLICATE KEY UPDATE table_version = '6';
CREATE TABLE IF NOT EXISTS dr_gateways (
    id INT(10) UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,
    gwid CHAR(64) NOT NULL,
    type INT(11) UNSIGNED DEFAULT 0 NOT NULL,
    address CHAR(128) NOT NULL,
    strip INT(11) UNSIGNED DEFAULT 0 NOT NULL,
    pri_prefix CHAR(16) DEFAULT NULL,
    attrs CHAR(255) DEFAULT NULL,
    probe_mode INT(11) UNSIGNED DEFAULT 0 NOT NULL,
    state INT(11) UNSIGNED DEFAULT 0 NOT NULL,
    socket CHAR(128) DEFAULT NULL,
    description CHAR(128) DEFAULT NULL,
    CONSTRAINT dr_gw_idx UNIQUE (gwid)
) ENGINE=InnoDB;

-- dr_rules (from drouting-create.sql)
INSERT INTO version (table_name, table_version) VALUES ('dr_rules','4')
ON DUPLICATE KEY UPDATE table_version = '4';
CREATE TABLE IF NOT EXISTS dr_rules (
    ruleid INT(10) UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,
    groupid CHAR(255) NOT NULL,
    prefix CHAR(64) NOT NULL,
    timerec CHAR(255) DEFAULT NULL,
    priority INT(11) DEFAULT 0 NOT NULL,
    routeid CHAR(255) DEFAULT NULL,
    gwlist CHAR(255),
    sort_alg CHAR(1) DEFAULT 'N' NOT NULL,
    sort_profile INT(10) UNSIGNED DEFAULT NULL,
    attrs CHAR(255) DEFAULT NULL,
    description CHAR(128) DEFAULT NULL
) ENGINE=InnoDB;

-- dr_carriers (from drouting-create.sql)
INSERT INTO version (table_name, table_version) VALUES ('dr_carriers','3')
ON DUPLICATE KEY UPDATE table_version = '3';
CREATE TABLE IF NOT EXISTS dr_carriers (
    id INT(10) UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,
    carrierid CHAR(64) NOT NULL,
    gwlist CHAR(255) NOT NULL,
    flags INT(11) UNSIGNED DEFAULT 0 NOT NULL,
    sort_alg CHAR(1) DEFAULT 'N' NOT NULL,
    state INT(11) UNSIGNED DEFAULT 0 NOT NULL,
    attrs CHAR(255) DEFAULT NULL,
    description CHAR(128) DEFAULT NULL,
    CONSTRAINT dr_carrier_idx UNIQUE (carrierid)
) ENGINE=InnoDB;

-- dr_groups (from drouting-create.sql)
INSERT INTO version (table_name, table_version) VALUES ('dr_groups','2')
ON DUPLICATE KEY UPDATE table_version = '2';
CREATE TABLE IF NOT EXISTS dr_groups (
    id INT(10) UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,
    username CHAR(64) NOT NULL,
    domain CHAR(128) DEFAULT NULL,
    groupid INT(11) UNSIGNED DEFAULT 0 NOT NULL,
    description CHAR(128) DEFAULT NULL
) ENGINE=InnoDB;

-- registrant (from registrant-create.sql)
INSERT INTO version (table_name, table_version) VALUES ('registrant','3')
ON DUPLICATE KEY UPDATE table_version = '3';
CREATE TABLE IF NOT EXISTS registrant (
    id INT(10) UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,
    registrar CHAR(255) DEFAULT '' NOT NULL,
    proxy CHAR(255) DEFAULT NULL,
    aor CHAR(255) DEFAULT '' NOT NULL,
    third_party_registrant CHAR(255) DEFAULT NULL,
    username CHAR(64) DEFAULT NULL,
    password CHAR(64) DEFAULT NULL,
    binding_URI CHAR(255) DEFAULT '' NOT NULL,
    binding_params CHAR(64) DEFAULT NULL,
    expiry INT(1) UNSIGNED DEFAULT NULL,
    forced_socket CHAR(64) DEFAULT NULL,
    cluster_shtag CHAR(64) DEFAULT NULL,
    state INT DEFAULT 0 NOT NULL,
    CONSTRAINT registrant_idx UNIQUE (aor, binding_URI, registrar)
) ENGINE=InnoDB;

-- dbaliases (from alias_db-create.sql)
INSERT INTO version (table_name, table_version) VALUES ('dbaliases','2')
ON DUPLICATE KEY UPDATE table_version = '2';
CREATE TABLE IF NOT EXISTS dbaliases (
    id INT(10) UNSIGNED AUTO_INCREMENT PRIMARY KEY NOT NULL,
    alias_username CHAR(64) DEFAULT '' NOT NULL,
    alias_domain CHAR(64) DEFAULT '' NOT NULL,
    username CHAR(64) DEFAULT '' NOT NULL,
    domain CHAR(64) DEFAULT '' NOT NULL,
    CONSTRAINT alias_idx UNIQUE (alias_username, alias_domain)
) ENGINE=InnoDB;

-- MySQL has no CREATE INDEX IF NOT EXISTS; this matches OpenSIPS alias_db-create.sql.
-- init-database.sh runs this script only when dr_gateways is missing, so the index is created once.
-- If you run this script manually after tables exist, ignore duplicate-key error (1061) on the next line.
CREATE INDEX target_idx ON dbaliases (username, domain);

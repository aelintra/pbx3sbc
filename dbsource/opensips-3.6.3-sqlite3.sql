PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
CREATE TABLE version (
    table_name CHAR(32) NOT NULL,
    table_version INTEGER DEFAULT 0 NOT NULL,
    CONSTRAINT version_t_name_idx  UNIQUE (table_name)
);
INSERT INTO version VALUES('acc',7);
INSERT INTO version VALUES('missed_calls',5);
INSERT INTO version VALUES('dbaliases',2);
INSERT INTO version VALUES('subscriber',8);
INSERT INTO version VALUES('uri',2);
INSERT INTO version VALUES('clusterer',4);
INSERT INTO version VALUES('dialog',12);
INSERT INTO version VALUES('dialplan',5);
INSERT INTO version VALUES('dispatcher',9);
INSERT INTO version VALUES('domain',4);
INSERT INTO version VALUES('dr_gateways',6);
INSERT INTO version VALUES('dr_rules',4);
INSERT INTO version VALUES('dr_carriers',3);
INSERT INTO version VALUES('dr_groups',2);
INSERT INTO version VALUES('dr_partitions',1);
INSERT INTO version VALUES('grp',3);
INSERT INTO version VALUES('re_grp',2);
INSERT INTO version VALUES('load_balancer',3);
INSERT INTO version VALUES('silo',6);
INSERT INTO version VALUES('address',5);
INSERT INTO version VALUES('rtpproxy_sockets',0);
INSERT INTO version VALUES('rtpengine',1);
INSERT INTO version VALUES('speed_dial',3);
INSERT INTO version VALUES('tls_mgm',3);
INSERT INTO version VALUES('location',1013);
CREATE TABLE acc (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    method CHAR(16) DEFAULT '' NOT NULL,
    from_tag CHAR(64) DEFAULT '' NOT NULL,
    to_tag CHAR(64) DEFAULT '' NOT NULL,
    callid CHAR(64) DEFAULT '' NOT NULL,
    sip_code CHAR(3) DEFAULT '' NOT NULL,
    sip_reason CHAR(32) DEFAULT '' NOT NULL,
    time DATETIME NOT NULL,
    duration INTEGER DEFAULT 0 NOT NULL,
    ms_duration INTEGER DEFAULT 0 NOT NULL,
    setuptime INTEGER DEFAULT 0 NOT NULL,
    created DATETIME DEFAULT NULL
);
CREATE TABLE missed_calls (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    method CHAR(16) DEFAULT '' NOT NULL,
    from_tag CHAR(64) DEFAULT '' NOT NULL,
    to_tag CHAR(64) DEFAULT '' NOT NULL,
    callid CHAR(64) DEFAULT '' NOT NULL,
    sip_code CHAR(3) DEFAULT '' NOT NULL,
    sip_reason CHAR(32) DEFAULT '' NOT NULL,
    time DATETIME NOT NULL,
    setuptime INTEGER DEFAULT 0 NOT NULL,
    created DATETIME DEFAULT NULL
);
CREATE TABLE dbaliases (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    alias_username CHAR(64) DEFAULT '' NOT NULL,
    alias_domain CHAR(64) DEFAULT '' NOT NULL,
    username CHAR(64) DEFAULT '' NOT NULL,
    domain CHAR(64) DEFAULT '' NOT NULL,
    CONSTRAINT dbaliases_alias_idx  UNIQUE (alias_username, alias_domain)
);
CREATE TABLE subscriber (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    username CHAR(64) DEFAULT '' NOT NULL,
    domain CHAR(64) DEFAULT '' NOT NULL,
    password CHAR(25) DEFAULT '' NOT NULL,
    ha1 CHAR(64) DEFAULT '' NOT NULL,
    ha1_sha256 CHAR(64) DEFAULT '' NOT NULL,
    ha1_sha512t256 CHAR(64) DEFAULT '' NOT NULL,
    CONSTRAINT subscriber_account_idx  UNIQUE (username, domain)
);
CREATE TABLE uri (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    username CHAR(64) DEFAULT '' NOT NULL,
    domain CHAR(64) DEFAULT '' NOT NULL,
    uri_user CHAR(64) DEFAULT '' NOT NULL,
    last_modified DATETIME DEFAULT '1900-01-01 00:00:01' NOT NULL,
    CONSTRAINT uri_account_idx  UNIQUE (username, domain, uri_user)
);
CREATE TABLE clusterer (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    cluster_id INTEGER NOT NULL,
    node_id INTEGER NOT NULL,
    url CHAR(64) NOT NULL,
    state INTEGER DEFAULT 1 NOT NULL,
    no_ping_retries INTEGER DEFAULT 3 NOT NULL,
    priority INTEGER DEFAULT 50 NOT NULL,
    sip_addr CHAR(64),
    flags CHAR(64),
    description CHAR(64),
    CONSTRAINT clusterer_clusterer_idx  UNIQUE (cluster_id, node_id)
);
CREATE TABLE dialog (
    dlg_id BIGINT(10) PRIMARY KEY NOT NULL,
    callid CHAR(255) NOT NULL,
    from_uri CHAR(255) NOT NULL,
    from_tag CHAR(64) NOT NULL,
    to_uri CHAR(255) NOT NULL,
    to_tag CHAR(64) NOT NULL,
    mangled_from_uri CHAR(255) DEFAULT NULL,
    mangled_to_uri CHAR(255) DEFAULT NULL,
    caller_cseq CHAR(11) NOT NULL,
    callee_cseq CHAR(11) NOT NULL,
    caller_ping_cseq INTEGER NOT NULL,
    callee_ping_cseq INTEGER NOT NULL,
    caller_route_set TEXT(512),
    callee_route_set TEXT(512),
    caller_contact CHAR(255),
    callee_contact CHAR(255),
    caller_sock CHAR(64) NOT NULL,
    callee_sock CHAR(64) NOT NULL,
    state INTEGER NOT NULL,
    start_time INTEGER NOT NULL,
    timeout INTEGER NOT NULL,
    vars BLOB(4096) DEFAULT NULL,
    profiles TEXT(512) DEFAULT NULL,
    script_flags CHAR(255) DEFAULT NULL,
    module_flags INTEGER DEFAULT 0 NOT NULL,
    flags INTEGER DEFAULT 0 NOT NULL,
    rt_on_answer CHAR(64) DEFAULT NULL,
    rt_on_timeout CHAR(64) DEFAULT NULL,
    rt_on_hangup CHAR(64) DEFAULT NULL
);
CREATE TABLE dialplan (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    dpid INTEGER NOT NULL,
    pr INTEGER DEFAULT 0 NOT NULL,
    match_op INTEGER NOT NULL,
    match_exp CHAR(64) NOT NULL,
    match_flags INTEGER DEFAULT 0 NOT NULL,
    subst_exp CHAR(64) DEFAULT NULL,
    repl_exp CHAR(32) DEFAULT NULL,
    timerec CHAR(255) DEFAULT NULL,
    disabled INTEGER DEFAULT 0 NOT NULL,
    attrs CHAR(255) DEFAULT NULL
);
CREATE TABLE dispatcher (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    setid INTEGER DEFAULT 0 NOT NULL,
    destination CHAR(192) DEFAULT '' NOT NULL,
    socket CHAR(128) DEFAULT NULL,
    state INTEGER DEFAULT 0 NOT NULL,
    probe_mode INTEGER DEFAULT 0 NOT NULL,
    weight CHAR(64) DEFAULT 1 NOT NULL,
    priority INTEGER DEFAULT 0 NOT NULL,
    attrs CHAR(128) DEFAULT NULL,
    description CHAR(64) DEFAULT NULL
);
CREATE TABLE domain (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    domain CHAR(64) DEFAULT '' NOT NULL,
    attrs CHAR(255) DEFAULT NULL,
    accept_subdomain INTEGER DEFAULT 0 NOT NULL,
    last_modified DATETIME DEFAULT '1900-01-01 00:00:01' NOT NULL,
    CONSTRAINT domain_domain_idx  UNIQUE (domain)
);
CREATE TABLE dr_gateways (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    gwid CHAR(64) NOT NULL,
    type INTEGER DEFAULT 0 NOT NULL,
    address CHAR(128) NOT NULL,
    strip INTEGER DEFAULT 0 NOT NULL,
    pri_prefix CHAR(16) DEFAULT NULL,
    attrs CHAR(255) DEFAULT NULL,
    probe_mode INTEGER DEFAULT 0 NOT NULL,
    state INTEGER DEFAULT 0 NOT NULL,
    socket CHAR(128) DEFAULT NULL,
    description CHAR(128) DEFAULT NULL,
    CONSTRAINT dr_gateways_dr_gw_idx  UNIQUE (gwid)
);
CREATE TABLE dr_rules (
    ruleid INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    groupid CHAR(255) NOT NULL,
    prefix CHAR(64) NOT NULL,
    timerec CHAR(255) DEFAULT NULL,
    priority INTEGER DEFAULT 0 NOT NULL,
    routeid CHAR(255) DEFAULT NULL,
    gwlist CHAR(255),
    sort_alg CHAR(1) DEFAULT 'N' NOT NULL,
    sort_profile INTEGER DEFAULT NULL,
    attrs CHAR(255) DEFAULT NULL,
    description CHAR(128) DEFAULT NULL
);
CREATE TABLE dr_carriers (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    carrierid CHAR(64) NOT NULL,
    gwlist CHAR(255) NOT NULL,
    flags INTEGER DEFAULT 0 NOT NULL,
    sort_alg CHAR(1) DEFAULT 'N' NOT NULL,
    state INTEGER DEFAULT 0 NOT NULL,
    attrs CHAR(255) DEFAULT NULL,
    description CHAR(128) DEFAULT NULL,
    CONSTRAINT dr_carriers_dr_carrier_idx  UNIQUE (carrierid)
);
CREATE TABLE dr_groups (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    username CHAR(64) NOT NULL,
    domain CHAR(128) DEFAULT NULL,
    groupid INTEGER DEFAULT 0 NOT NULL,
    description CHAR(128) DEFAULT NULL
);
CREATE TABLE dr_partitions (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    partition_name CHAR(255) NOT NULL,
    db_url CHAR(255) NOT NULL,
    drd_table CHAR(255),
    drr_table CHAR(255),
    drg_table CHAR(255),
    drc_table CHAR(255),
    ruri_avp CHAR(255),
    gw_id_avp CHAR(255),
    gw_priprefix_avp CHAR(255),
    gw_sock_avp CHAR(255),
    rule_id_avp CHAR(255),
    rule_prefix_avp CHAR(255),
    carrier_id_avp CHAR(255)
);
CREATE TABLE grp (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    username CHAR(64) DEFAULT '' NOT NULL,
    domain CHAR(64) DEFAULT '' NOT NULL,
    grp CHAR(64) DEFAULT '' NOT NULL,
    last_modified DATETIME DEFAULT '1900-01-01 00:00:01' NOT NULL,
    CONSTRAINT grp_account_group_idx  UNIQUE (username, domain, grp)
);
CREATE TABLE re_grp (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    reg_exp CHAR(128) DEFAULT '' NOT NULL,
    group_id INTEGER DEFAULT 0 NOT NULL
);
CREATE TABLE load_balancer (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    group_id INTEGER DEFAULT 0 NOT NULL,
    dst_uri CHAR(128) NOT NULL,
    resources CHAR(255) NOT NULL,
    probe_mode INTEGER DEFAULT 0 NOT NULL,
    attrs CHAR(255) DEFAULT NULL,
    description CHAR(128) DEFAULT NULL
);
CREATE TABLE silo (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    src_addr CHAR(255) DEFAULT '' NOT NULL,
    dst_addr CHAR(255) DEFAULT '' NOT NULL,
    username CHAR(64) DEFAULT '' NOT NULL,
    domain CHAR(64) DEFAULT '' NOT NULL,
    inc_time INTEGER DEFAULT 0 NOT NULL,
    exp_time INTEGER DEFAULT 0 NOT NULL,
    snd_time INTEGER DEFAULT 0 NOT NULL,
    ctype CHAR(255) DEFAULT NULL,
    body BLOB DEFAULT NULL
);
CREATE TABLE address (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    grp SMALLINT(5) DEFAULT 0 NOT NULL,
    ip CHAR(50) NOT NULL,
    mask SMALLINT DEFAULT 32 NOT NULL,
    port SMALLINT(5) DEFAULT 0 NOT NULL,
    proto CHAR(4) DEFAULT 'any' NOT NULL,
    pattern CHAR(64) DEFAULT NULL,
    context_info CHAR(32) DEFAULT NULL
);
CREATE TABLE rtpproxy_sockets (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    rtpproxy_sock TEXT NOT NULL,
    set_id INTEGER NOT NULL
);
CREATE TABLE rtpengine (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    socket TEXT NOT NULL,
    set_id INTEGER NOT NULL
);
CREATE TABLE speed_dial (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    username CHAR(64) DEFAULT '' NOT NULL,
    domain CHAR(64) DEFAULT '' NOT NULL,
    sd_username CHAR(64) DEFAULT '' NOT NULL,
    sd_domain CHAR(64) DEFAULT '' NOT NULL,
    new_uri CHAR(255) DEFAULT '' NOT NULL,
    fname CHAR(64) DEFAULT '' NOT NULL,
    lname CHAR(64) DEFAULT '' NOT NULL,
    description CHAR(64) DEFAULT '' NOT NULL,
    CONSTRAINT speed_dial_speed_dial_idx  UNIQUE (username, domain, sd_domain, sd_username)
);
CREATE TABLE tls_mgm (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    domain CHAR(64) NOT NULL,
    match_ip_address CHAR(255) DEFAULT NULL,
    match_sip_domain CHAR(255) DEFAULT NULL,
    type INTEGER DEFAULT 1 NOT NULL,
    method CHAR(16) DEFAULT 'SSLv23',
    verify_cert INTEGER DEFAULT 1,
    require_cert INTEGER DEFAULT 1,
    certificate BLOB,
    private_key BLOB,
    crl_check_all INTEGER DEFAULT 0,
    crl_dir CHAR(255) DEFAULT NULL,
    ca_list BLOB DEFAULT NULL,
    ca_dir CHAR(255) DEFAULT NULL,
    cipher_list CHAR(255) DEFAULT NULL,
    dh_params BLOB DEFAULT NULL,
    ec_curve CHAR(255) DEFAULT NULL,
    CONSTRAINT tls_mgm_domain_type_idx  UNIQUE (domain, type)
);
CREATE TABLE location (
    contact_id  INTEGER PRIMARY KEY AUTOINCREMENT  NOT NULL,
    username CHAR(64) DEFAULT '' NOT NULL,
    domain CHAR(64) DEFAULT NULL,
    contact TEXT NOT NULL,
    received CHAR(255) DEFAULT NULL,
    path CHAR(255) DEFAULT NULL,
    expires INTEGER NOT NULL,
    q FLOAT(10,2) DEFAULT 1.0 NOT NULL,
    callid CHAR(255) DEFAULT 'Default-Call-ID' NOT NULL,
    cseq INTEGER DEFAULT 13 NOT NULL,
    last_modified DATETIME DEFAULT '1900-01-01 00:00:01' NOT NULL,
    flags INTEGER DEFAULT 0 NOT NULL,
    cflags CHAR(255) DEFAULT NULL,
    user_agent CHAR(255) DEFAULT '' NOT NULL,
    socket CHAR(64) DEFAULT NULL,
    methods INTEGER DEFAULT NULL,
    sip_instance CHAR(255) DEFAULT NULL,
    kv_store TEXT(512) DEFAULT NULL,
    attr CHAR(255) DEFAULT NULL
);
DELETE FROM sqlite_sequence;
CREATE INDEX acc_callid_idx  ON acc (callid);
CREATE INDEX missed_calls_callid_idx  ON missed_calls (callid);
CREATE INDEX dbaliases_target_idx  ON dbaliases (username, domain);
CREATE INDEX subscriber_username_idx  ON subscriber (username);
CREATE INDEX re_grp_group_idx  ON re_grp (group_id);
CREATE INDEX load_balancer_dsturi_idx  ON load_balancer (dst_uri);
CREATE INDEX silo_account_idx  ON silo (username, domain);
COMMIT;
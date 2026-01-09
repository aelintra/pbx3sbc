<?php
if (!isset($config)) {
    $config = new stdClass();
}

$config->db_driver = "mysql";
$config->db_host = "localhost";
$config->db_port = "3306";
$config->db_user = "opensips";
$config->db_pass = "rigmarole";
$config->db_name = "opensips";
?>

#!/usr/bin/env python3
"""Detect NAT via private Via/Contact or port mismatch (Yealink behind public NAT IP)."""
import sys
from pathlib import Path

cfg_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/etc/opensips/opensips.cfg")
text = cfg_path.read_text()

old = """route[CHECK_NAT_ENVIRONMENT] {
    $var(enable_nat_fixes) = 0;
    
    # Runtime detection: Check if endpoints are sending private IPs (indicates NAT environment)
    # This works for both LAN and NAT environments
    # If we receive requests with private IPs from endpoints (not Asterisk), enable NAT fixes
    route(CHECK_IS_FROM_ASTERISK);
    if ($var(is_from_asterisk) == 0) {
        # NOTE: nat_uac_test() causes runtime errors in OpenSIPS 3.6.3
        # Error: "Unknown flag: 19" when called at runtime
        # Using manual source IP check which works reliably
        $var(check_ip) = $si;
        route(CHECK_PRIVATE_IP);
        if ($var(is_private) == 1) {
            # Endpoint is behind NAT - enable NAT fixes for this request
            $var(enable_nat_fixes) = 1;
            xlog("NAT environment detected via source IP check: endpoint $si is behind NAT, enabling NAT fixes\\n");
        }
    }
    
    return;
}"""

new = """route[CHECK_NAT_ENVIRONMENT] {
    $var(enable_nat_fixes) = 0;
    
    # Endpoints behind NAT often arrive from a public IP (customer router) while Via/Contact
    # still advertise RFC1918 addresses. force_rport() must run for those REGISTERs.
    route(CHECK_IS_FROM_ASTERISK);
    if ($var(is_from_asterisk) == 0) {
        $var(check_ip) = $si;
        route(CHECK_PRIVATE_IP);
        if ($var(is_private) == 1) {
            $var(enable_nat_fixes) = 1;
            xlog("NAT detected: private source IP $si\\n");
        }
        if ($var(enable_nat_fixes) == 0) {
            $var(check_ip) = $(hdr(Via)[0]{via.host});
            if ($var(check_ip) != "" && $var(check_ip) != "<null>") {
                route(CHECK_PRIVATE_IP);
                if ($var(is_private) == 1) {
                    $var(enable_nat_fixes) = 1;
                    xlog("NAT detected: private IP in Via sent-by $var(check_ip)\\n");
                }
            }
        }
        if ($var(enable_nat_fixes) == 0 && $hdr(Contact) =~ "@([0-9]{1,3}\\\\.[0-9]{1,3}\\\\.[0-9]{1,3}\\\\.[0-9]{1,3})") {
            $var(check_ip) = $re;
            route(CHECK_PRIVATE_IP);
            if ($var(is_private) == 1) {
                $var(enable_nat_fixes) = 1;
                xlog("NAT detected: private IP in Contact $var(check_ip)\\n");
            }
        }
        if ($var(enable_nat_fixes) == 0) {
            $var(via_port) = $(hdr(Via)[0]{via.port});
            if ($var(via_port) != "" && $var(via_port) != "<null>" && $sp != $var(via_port)) {
                $var(enable_nat_fixes) = 1;
                xlog("NAT detected: source port $sp != Via port $var(via_port)\\n");
            }
        }
    }
    
    return;
}"""

if "NAT detected: private IP in Via sent-by" in text:
    print("Already patched")
    sys.exit(0)

if old not in text:
    print("ERROR: CHECK_NAT_ENVIRONMENT block not found", file=sys.stderr)
    sys.exit(1)

cfg_path.write_text(text.replace(old, new, 1))
print("Patched CHECK_NAT_ENVIRONMENT")

#!/usr/bin/env python3
"""Hot-patch live opensips.cfg for REGISTER 401 relay fix (2026-07-09)."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/etc/opensips/opensips.cfg"

with open(path) as f:
    text = f.read()

text = text.replace(
    '    xlog("Routing to $du for domain=$rd setid=$var(setid) method=$rm Request-URI=$ru\\n");\n\n    record_route();\n',
    '    xlog("Routing to $du for domain=$rd setid=$var(setid) method=$rm Request-URI=$ru\\n");\n\n'
    '    # REGISTER must not get Record-Route — it breaks 401 challenge relay to endpoints.\n'
    '    if (!is_method("REGISTER")) {\n        record_route();\n    }\n',
    1,
)

old_force = """    if (is_method("REGISTER")) {
        # For REGISTER requests, always force rport to ensure authentication responses reach OpenSIPS
        # This works even if the phone didn't send rport parameter
        force_rport();
        xlog("REGISTER: force_rport() called - Asterisk will send responses to source IP:port $si:$sp\\n");
    } else {
        # For other requests, only force rport if endpoint is behind NAT"""

new_force = """    # Do NOT force_rport on REGISTER toward Asterisk — fix_nated_register in request route.
    if (!is_method("REGISTER")) {
        # For other requests, only force rport if endpoint is behind NAT"""

if old_force not in text:
    print("WARN: force_rport block not found exactly", file=sys.stderr)
else:
    text = text.replace(old_force, new_force, 1)

text = text.replace(
    '    if (is_method("INVITE") && (t_check_status("401|407"))) {\n'
    '        xlog("INVITE auth challenge $rs - relaying to endpoint without modification\\n");\n'
    '        exit;\n    }',
    '    if ((is_method("INVITE") || is_method("REGISTER")) && (t_check_status("401|407"))) {\n'
    '        xlog("$rm auth challenge $rs - relaying to endpoint without modification\\n");\n'
    '        exit;\n    }',
    1,
)

marker = 'onreply_route[handle_reply_reg] {\n    if (is_method("REGISTER")) {'
insert = (
    'onreply_route[handle_reply_reg] {\n'
    '    # Auth challenges must relay to the phone before any save()/logging logic.\n'
    '    if (is_method("REGISTER") && (t_check_status("401|407"))) {\n'
    '        xlog("REGISTER auth challenge $rs - relaying to endpoint (handle_reply_reg)\\n");\n'
    '        exit;\n'
    '    }\n\n'
    '    if (is_method("REGISTER")) {'
)
if marker not in text:
    print("WARN: handle_reply_reg marker not found", file=sys.stderr)
else:
    text = text.replace(marker, insert, 1)

old_401 = """            # Skip logging 401 responses (they're part of normal authentication flow)
            if ($rs == 401) {
                # 401 is normal - skip logging (just part of authentication flow)
                exit;
            }
            
            # Log 403 Forbidden and other failures (4xx/5xx except 401)"""

new_401 = """            # 401/407 handled at top of handle_reply_reg — do not exit here (drops relay).
            
            # Log 403 Forbidden and other failures (4xx/5xx except 401)"""

if old_401 not in text:
    print("WARN: 401 exit block not found", file=sys.stderr)
else:
    text = text.replace(old_401, new_401, 1)

with open(path, "w") as f:
    f.write(text)

print(f"Patched {path}")

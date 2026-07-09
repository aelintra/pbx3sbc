#!/usr/bin/env python3
"""Set explicit NAT reply destination for REGISTER 401/407 relay."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/etc/opensips/opensips.cfg"

with open(path) as f:
    text = f.read()

old_main = """    if (($rs == 401 || $rs == 407) && (is_method("INVITE") || is_method("REGISTER"))) {
        xlog("$rm auth challenge $rs - relaying to endpoint without modification\\n");
        exit;
    }"""

new_main = """    if (($rs == 401 || $rs == 407) && (is_method("INVITE") || is_method("REGISTER"))) {
        if (is_method("REGISTER") && $avp(reg_source_ip) != "" && $avp(reg_source_port) != "") {
            $du = "sip:" + $tU + "@" + $avp(reg_source_ip) + ":" + $avp(reg_source_port) + ";transport=udp";
            xlog("REGISTER auth challenge $rs - relay dst $du (NAT source from AVP)\\n");
        } else {
            xlog("$rm auth challenge $rs - relaying to endpoint without modification\\n");
        }
        exit;
    }"""

old_reg = """    if (is_method("REGISTER") && ($rs == 401 || $rs == 407)) {
        xlog("REGISTER auth challenge $rs - relaying to endpoint (handle_reply_reg)\\n");
        exit;
    }"""

new_reg = """    if (is_method("REGISTER") && ($rs == 401 || $rs == 407)) {
        if ($avp(reg_source_ip) != "" && $avp(reg_source_port) != "") {
            $du = "sip:" + $tU + "@" + $avp(reg_source_ip) + ":" + $avp(reg_source_port) + ";transport=udp";
            xlog("REGISTER auth challenge $rs - relay dst $du (handle_reply_reg NAT)\\n");
        } else {
            xlog("REGISTER auth challenge $rs - relaying to endpoint (handle_reply_reg)\\n");
        }
        exit;
    }"""

for old, new, label in ((old_main, new_main, "main"), (old_reg, new_reg, "handle_reply_reg")):
    if old in text:
        text = text.replace(old, new, 1)
    else:
        print(f"WARN: {label} block not found", file=sys.stderr)

with open(path, "w") as f:
    f.write(text)

print(f"Patched {path}")

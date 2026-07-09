#!/usr/bin/env python3
"""Fix REGISTER 401 dropped by main onreply_route >= 300 block."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/etc/opensips/opensips.cfg"

with open(path) as f:
    text = f.read()

old_early = """    if ((is_method("INVITE") || is_method("REGISTER")) && (t_check_status("401|407"))) {
        xlog("$rm auth challenge $rs - relaying to endpoint without modification\\n");
        exit;
    }"""

new_early = """    if (($rs == 401 || $rs == 407) && (is_method("INVITE") || is_method("REGISTER"))) {
        xlog("$rm auth challenge $rs - relaying to endpoint without modification\\n");
        exit;
    }"""

if old_early in text:
    text = text.replace(old_early, new_early, 1)
else:
    print("WARN: early auth block not found", file=sys.stderr)

old_300 = """    } else if ($rs >= 300) {
        xlog("Final error response $rs received\\n");
        exit;
    }"""

new_300 = """    } else if ($rs >= 300 && $rs != 401 && $rs != 407) {
        xlog("Final error response $rs received\\n");
        exit;
    }"""

if old_300 in text:
    text = text.replace(old_300, new_300, 1)
else:
    print("WARN: >= 300 block not found", file=sys.stderr)

old_reg = 'if (is_method("REGISTER") && (t_check_status("401|407")))'
new_reg = 'if (is_method("REGISTER") && ($rs == 401 || $rs == 407))'
if old_reg in text:
    text = text.replace(old_reg, new_reg, 1)

with open(path, "w") as f:
    f.write(text)

print(f"Patched {path}")

#!/usr/bin/env python3
"""Skip REGISTER 401 in main onreply; fix handle_reply_reg NAT dst."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/etc/opensips/opensips.cfg"

with open(path) as f:
    text = f.read()

# Replace main onreply REGISTER+INVITE block with INVITE-only
import re
text = re.sub(
    r"    if \(\(\$rs == 401 \|\| \$rs == 407\) && \(is_method\(\"INVITE\"\) \|\| is_method\(\"REGISTER\"\)\)\) \{.*?\n        exit;\n    \}",
    """    # INVITE auth challenges only here — REGISTER 401 is handled in handle_reply_reg
    if (($rs == 401 || $rs == 407) && is_method("INVITE")) {
        xlog("INVITE auth challenge $rs - relaying to endpoint without modification\\n");
        exit;
    }""",
    text,
    count=1,
    flags=re.DOTALL,
)

old_avp = """            $avp(reg_source_ip) = $si;
            $avp(reg_source_port) = $sp;"""

new_avp = """            $avp(reg_source_ip) = $si;
            $avp(reg_source_port) = $sp;
            $avp(tu:reg_source_ip) = $si;
            $avp(tu:reg_source_port) = $sp;"""

if old_avp in text and "tu:reg_source_ip" not in text:
    text = text.replace(old_avp, new_avp, 1)

old_hrr = """    if (is_method("REGISTER") && ($rs == 401 || $rs == 407)) {
        if ($avp(reg_source_ip) != "" && $avp(reg_source_port) != "") {
            $du = "sip:" + $tU + "@" + $avp(reg_source_ip) + ":" + $avp(reg_source_port) + ";transport=udp";
            xlog("REGISTER auth challenge $rs - relay dst $du (handle_reply_reg NAT)\\n");
        } else {
            xlog("REGISTER auth challenge $rs - relaying to endpoint (handle_reply_reg)\\n");
        }
        exit;
    }"""

new_hrr = """    if (is_method("REGISTER") && ($rs == 401 || $rs == 407)) {
        $var(reply_ip) = $avp(tu:reg_source_ip);
        $var(reply_port) = $avp(tu:reg_source_port);
        if ($var(reply_ip) == "" || $var(reply_ip) == "<null>") {
            $var(reply_ip) = $avp(reg_source_ip);
            $var(reply_port) = $avp(reg_source_port);
        }
        if ($var(reply_ip) != "" && $var(reply_ip) != "<null>" && $var(reply_port) != "" && $var(reply_port) != "<null>") {
            $du = "sip:" + $tU + "@" + $var(reply_ip) + ":" + $var(reply_port) + ";transport=udp";
            xlog("REGISTER auth challenge $rs - relay dst $du (handle_reply_reg NAT)\\n");
        } else {
            xlog("REGISTER auth challenge $rs - relaying to endpoint (handle_reply_reg)\\n");
        }
        exit;
    }"""

if old_hrr in text:
    text = text.replace(old_hrr, new_hrr, 1)

with open(path, "w") as f:
    f.write(text)

print(f"Patched {path}")

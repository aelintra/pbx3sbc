#!/usr/bin/env python3
"""Ensure force_rport() persists on REGISTER client Via before t_relay (Yealink NAT)."""
import sys
from pathlib import Path

cfg_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/etc/opensips/opensips.cfg")
text = cfg_path.read_text()

changes = []

# 1) Persist rport after ingress NAT fix (msg_apply_changes before long route chain)
old_ingress = """                force_rport();
                xlog("REGISTER: NAT detected - forcing rport behavior: using actual source $si:$sp (endpoint may not have sent rport parameter)\\n");"""
new_ingress = """                force_rport();
                msg_apply_changes();
                xlog("REGISTER: NAT detected - forcing rport behavior: using actual source $si:$sp (endpoint may not have sent rport parameter)\\n");"""
if old_ingress in text and "msg_apply_changes" not in text.split("REGISTER: NAT detected")[0][-500:]:
    text = text.replace(old_ingress, new_ingress, 1)
    changes.append("ingress msg_apply_changes")

# 2) force_rport immediately before t_relay for REGISTER (top Via is still the phone)
old_to_disp = """    # Do NOT force_rport on REGISTER toward Asterisk — fix_nated_register in request route.
    if (!is_method("REGISTER")) {
        # For other requests, only force rport if endpoint is behind NAT
        # This avoids unnecessary Via header modification for LAN endpoints
        route(CHECK_NAT_ENVIRONMENT);
        if ($var(enable_nat_fixes) == 1) {
            force_rport();
            xlog("$rm: force_rport() called for NAT endpoint - responses will use source IP:port $si:$sp\\n");
        }
        if (is_method("INVITE") && !has_totag()) {
            force_rport();
            xlog("INVITE: force_rport() called for outbound call - auth responses will use source IP:port $si:$sp\\n");
        }
    }"""

new_to_disp = """    # REGISTER: force_rport on client Via immediately before t_relay (Yealink omits rport).
    # fix_nated_register adds received= but without rport replies go to :5060 not NAT port.
    route(CHECK_NAT_ENVIRONMENT);
    if (is_method("REGISTER") && $var(enable_nat_fixes) == 1) {
        force_rport();
        msg_apply_changes();
        xlog("REGISTER: force_rport() before t_relay — client Via rport=$sp\\n");
    }
    if (!is_method("REGISTER")) {
        # For other requests, only force rport if endpoint is behind NAT
        if ($var(enable_nat_fixes) == 1) {
            force_rport();
            xlog("$rm: force_rport() called for NAT endpoint - responses will use source IP:port $si:$sp\\n");
        }
        if (is_method("INVITE") && !has_totag()) {
            force_rport();
            xlog("INVITE: force_rport() called for outbound call - auth responses will use source IP:port $si:$sp\\n");
        }
    }"""

if old_to_disp in text:
    text = text.replace(old_to_disp, new_to_disp, 1)
    changes.append("TO_DISPATCHER REGISTER force_rport")
elif "REGISTER: force_rport() before t_relay" in text:
    changes.append("TO_DISPATCHER already patched")
else:
    print("WARN: TO_DISPATCHER block not found", file=sys.stderr)

# 3) Remove ineffective $du override in handle_reply_reg (tm ignores $du for reply relay)
old_reg_reply = """    if (is_method("REGISTER") && ($rs == 401 || $rs == 407)) {
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

new_reg_reply = """    if (is_method("REGISTER") && ($rs == 401 || $rs == 407)) {
        xlog("REGISTER auth challenge $rs - relaying to endpoint (handle_reply_reg, Via rport)\\n");
        exit;
    }"""

if old_reg_reply in text:
    text = text.replace(old_reg_reply, new_reg_reply, 1)
    changes.append("handle_reply_reg simplify")
elif "Via rport" in text:
    changes.append("handle_reply_reg already simplified")

if not changes:
    print("No changes applied", file=sys.stderr)
    sys.exit(1)

cfg_path.write_text(text)
print("Applied:", ", ".join(changes))

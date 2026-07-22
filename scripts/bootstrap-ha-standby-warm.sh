#!/usr/bin/env bash
# Copy warm-sync prerequisites from the *active* SBC to a new standby (ops laptop).
# Does not attach IAM (AWS CLI on the laptop) or open security groups.
#
# Usage:
#   export PBX3_SBC_SSH_KEY=~/Documents/pemfiles/opensips.pem
#   ./scripts/bootstrap-ha-standby-warm.sh \
#     --active ubuntu@3.93.26.82 \
#     --standby ubuntu@98.92.40.83 \
#     [--profile-name pbx3-sbc] \
#     [--standby-instance-id i-00964a57ac65383d1]
#
# Then on standby: sudo ./scripts/check-ha-standby-ready.sh --role standby

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY="${PBX3_SBC_SSH_KEY:-$HOME/Documents/pemfiles/opensips.pem}"
ACTIVE=""
STANDBY=""
PROFILE_NAME="pbx3-sbc"
STANDBY_IID=""
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

usage() {
  sed -n '2,16p' "$0" | tr -d '#'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --active) ACTIVE="${2:-}"; shift 2 ;;
    --standby) STANDBY="${2:-}"; shift 2 ;;
    --profile-name) PROFILE_NAME="${2:-}"; shift 2 ;;
    --standby-instance-id) STANDBY_IID="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$ACTIVE" && -n "$STANDBY" ]] || { echo "need --active and --standby" >&2; exit 2; }
[[ -f "$KEY" ]] || { echo "SSH key not found: $KEY" >&2; exit 1; }

SSH() { ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=25 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$@"; }

echo "=== copy log-ship.env active → standby ==="
SSH "$ACTIVE" 'sudo cat /etc/pbx3sbc/log-ship.env' | SSH "$STANDBY" '
  sudo mkdir -p /etc/pbx3sbc
  sudo tee /etc/pbx3sbc/log-ship.env >/dev/null
  sudo chmod 640 /etc/pbx3sbc/log-ship.env
  sudo chown root:root /etc/pbx3sbc/log-ship.env
  echo log-ship.env installed
'

echo "=== copy PBX3_FLEET_SERVICE_TOKEN active → standby admin .env ==="
TOKEN_LINE="$(SSH "$ACTIVE" 'grep -E "^PBX3_FLEET_SERVICE_TOKEN=" /home/ubuntu/pbx3sbc-admin/.env | head -1')"
[[ "$TOKEN_LINE" == PBX3_FLEET_SERVICE_TOKEN=* ]] || { echo "active missing fleet token" >&2; exit 1; }
printf '%s\n' "$TOKEN_LINE" | SSH "$STANDBY" '
  ENV=/home/ubuntu/pbx3sbc-admin/.env
  LINE=$(cat)
  if grep -qE "^PBX3_FLEET_SERVICE_TOKEN=" "$ENV" 2>/dev/null; then
    grep -vE "^PBX3_FLEET_SERVICE_TOKEN=" "$ENV" > /tmp/env.new
    echo "$LINE" >> /tmp/env.new
    mv /tmp/env.new "$ENV"
  else
    echo "$LINE" >> "$ENV"
  fi
  cd /home/ubuntu/pbx3sbc-admin && php artisan config:clear >/dev/null 2>&1 || true
  echo fleet_line_set
'

echo "=== ensure AWS CLI v2 on standby ==="
SSH "$STANDBY" '
  if ! command -v aws >/dev/null 2>&1; then
    cd /tmp
    curl -sS "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unzip
    unzip -qo awscliv2.zip
    sudo ./aws/install
  fi
  aws --version
'

echo "=== sudoers / panel helper ==="
SSH "$STANDBY" '
  test -x /home/ubuntu/pbx3sbc/scripts/sbc-backup-panel.sh || { echo "deploy pbx3sbc scripts first"; exit 1; }
  sudo /home/ubuntu/pbx3sbc/scripts/setup-admin-panel-sudoers.sh >/tmp/sudoers.out
  grep -E "Sudoers file created|sbc-backup-panel" /tmp/sudoers.out | head -5
  sudo systemctl reload php8.3-fpm 2>/dev/null || sudo systemctl reload php8.4-fpm 2>/dev/null || true
'

if [[ -n "$STANDBY_IID" ]] && command -v aws >/dev/null 2>&1; then
  echo "=== attach IAM instance profile $PROFILE_NAME → $STANDBY_IID ==="
  if aws ec2 describe-iam-instance-profile-associations --filters "Name=instance-id,Values=$STANDBY_IID" \
    --query 'IamInstanceProfileAssociations[0].IamInstanceProfile.Arn' --output text 2>/dev/null \
    | grep -qv '^None$\|^$'; then
    echo "instance already has a profile — skip associate (detach/replace manually if wrong)"
  else
    aws ec2 associate-iam-instance-profile \
      --region "$REGION" \
      --instance-id "$STANDBY_IID" \
      --iam-instance-profile "Name=$PROFILE_NAME" \
      --query 'IamInstanceProfileAssociation.State' --output text
    echo "wait ~15s for IMDS credentials…"
    sleep 15
  fi
else
  echo "NOTE: pass --standby-instance-id i-… to auto-attach IAM profile $PROFILE_NAME"
fi

echo "=== run readiness check on standby ==="
SSH "$STANDBY" 'sudo /home/ubuntu/pbx3sbc/scripts/check-ha-standby-ready.sh --role standby' || {
  echo "Standby not fully ready — fix FAIL lines, then re-run check."
  exit 1
}

echo "DONE — Fleet → Edge HA → Sync now"

#!/bin/sh
set -eu

DATE=$(date +%s)
NFT_FILE=/etc/nftables/monit.nft
BACKUP="${NFT_FILE}.bak.${DATE}"
TMP="$(mktemp /tmp/monit.nft.XXXXXX)"

# Get ControlGroup value for bosh-agent.service
cg=$(systemctl show -p ControlGroup --value bosh-agent.service 2>/dev/null || true)
if [ -z "$cg" ]; then
  echo "bosh-agent.service ControlGroup not found" >&2
  exit 1
fi
cg=${cg#/} # remove leading slash if present
echo "Found ControlGroup for bosh-agent.service: $cg"

# Replace the quoted cgroup path in the socket rule that matches the ip/tcp part
# The expected nft rule begins with: socket cgroupv2 level <n> "<path>" ip daddr 127.0.0.1 ...
awk_status=0
awk -v new="$cg" '
BEGIN { replaced = 0 }
/^[[:space:]]*socket[[:space:]]+cgroupv2[[:space:]]+level[[:space:]]+[0-9]+[[:space:]]+"[^"]+"[[:space:]]+ip[[:space:]]+daddr[[:space:]]+127\.0\.0\.1/ {
  sub(/"[^"]+"/, "\"" new "\"", $0)
  replaced = 1
}
{ print }
END { if (replaced == 0) exit 3 }
' "$NFT_FILE" > "$TMP" || awk_status=$?
if [ "$awk_status" -eq 3 ]; then
  echo "monit.nft socket rule not found; no changes made" >&2
  rm -f "$TMP"
  exit 1
elif [ "$awk_status" -ne 0 ]; then
  echo "failed to update monit.nft (awk error $awk_status)" >&2
  rm -f "$TMP"
  exit 1
fi

# Backup & atomically replace and try to reload nft
cp -p "$NFT_FILE" "$BACKUP"
if mv "$TMP" "$NFT_FILE"; then
  if nft -f "$NFT_FILE"; then
    echo "Updated monit.nft to cgroup: $cg"
    exit 0
  else
    echo "nft load failed, restoring backup" >&2
    mv "$BACKUP" "$NFT_FILE"
    nft -f "$NFT_FILE" || echo "failed to restore nft rules; check $NFT_FILE and $BACKUP" >&2
    exit 1
  fi
else
  echo "failed to replace $NFT_FILE" >&2
  rm -f "$TMP"
  exit 1
fi
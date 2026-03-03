#!/bin/sh
set -eu

DATE=$(date +%s)
NFT_FILE=/etc/nftables/monit.nft
BACKUP="${NFT_FILE}.bak.${DATE}"
TMP="$(mktemp /tmp/monit.nft.${DATE})"

# Get ControlGroup value for bosh-agent.service
cg=$(systemctl show -p ControlGroup --value bosh-agent.service 2>/dev/null || true)
if [ -z "$cg" ]; then
  echo "bosh-agent.service ControlGroup not found" >&2
  exit 1
fi
cg=${cg#/} # remove leading slash if present
echo "Found ControlGroup for bosh-agent.service: $cg"

# Replace the quoted cgroup path in the socket rule that matches the ip/tcp part
pattern='(^[[:space:]]*socket[[:space:]]+cgroupv2[[:space:]]+level[[:space:]]+[0-9]+[[:space:]]+")[^"]+("[[:space:]]+ip[[:space:]]+daddr[[:space:]]+127\.0\.0\.1[[:space:]]+tcp[[:space:]]+dport[[:space:]]+2822)'
esc=$(printf '%s' "$cg" | sed 's@[/&]@\&@g') # escape slashes and ampersands for sed
sed -E "s@$pattern@\1${esc}\2@" "$NFT_FILE" > "$TMP"
if cmp -s "$NFT_FILE" "$TMP"; then
  rm -f "$TMP"
  echo "monit.nft already up-to-date (using cgroup: $cg)"
  exit 0
else
  echo "monit.nft needs update (new cgroup: $cg)"
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
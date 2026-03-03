#!/bin/sh
set -eu

CERT_DIR=$(find /tmp -maxdepth 1 -type d -regex '/tmp/tmp\.[A-Za-z0-9][A-Za-z0-9]*' -print | head -n 1)
if [ -z "$CERT_DIR" ]; then
  echo "DOCKER_CERT_PATH not found (no /tmp/tmp.* directory)" >&2
  exit 1
fi
export DOCKER_HOST=tcp://172.17.0.2:4243
export DOCKER_TLS_VERIFY=1
export DOCKER_CERT_PATH="$CERT_DIR"

SCRIPT_PATH=/usr/local/sbin/update-monit-nft.sh

trap 'echo "monit-nft watcher interrupted; exiting" >&2; exit 0' INT TERM

run_update_in_container() {
  cid="$1"
  if [ ! -r "$SCRIPT_PATH" ]; then
    echo "missing host script: $SCRIPT_PATH" >&2
    return 1
  fi
  while true; do
    if docker exec -i "$cid" /bin/sh -s -- < "$SCRIPT_PATH"; then
      return 0
    fi
    echo "failed to run update-monit-nft.sh inside container $cid; retrying in 1s" >&2
    sleep 1
  done
}

# initial update for any already-running containers
for cid in $(docker ps -q 2>/dev/null); do
  run_update_in_container "$cid"
done

# listen for docker start events and update when they occur forever
while true; do
  docker events --filter 'event=start' --format '{{.Actor.ID}} {{.Type}} {{.Action}}' | while read -r id type action; do
    echo "Received docker event: ID=$id Type=$type Action=$action"
    run_update_in_container "$id"
  done || true
  echo "docker events stream ended or failed; retrying after 1s" >&2
  sleep 1
done

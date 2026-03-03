#!/bin/sh
set -eu

SCRIPT_PATH=/usr/local/sbin/update-monit-nft.sh

trap 'echo "monit-nft watcher interrupted; exiting" >&2; exit 0' INT TERM

run_update_in_container() {
  cid="$1"
  if [ ! -r "$SCRIPT_PATH" ]; then
    echo "missing host script: $SCRIPT_PATH" >&2
    return
  fi
  if ! docker exec -i "$cid" /bin/sh -s -- < "$SCRIPT_PATH"; then
    echo "failed to run update-monit-nft.sh inside container $cid" >&2
  fi
}

# initial update for any already-running containers
for cid in $(docker ps -q 2>/dev/null); do
  run_update_in_container "$cid"
done

# listen for docker start events and update when they occur forever
while true; do
  docker events --filter 'event=start' --format '{{.ID}} {{.Type}} {{.Action}}' | while read -r id type action; do
    echo "Received docker event: ID=$id Type=$type Action=$action"
    run_update_in_container "$id"
  done || true
  echo "docker events stream ended or failed; retrying after 1s" >&2
  sleep 1
done

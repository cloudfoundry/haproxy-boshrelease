#!/bin/sh
set -eu

# Find the first /tmp/tmp.* directory to use as DOCKER_CERT_PATH
CERT_DIR=$(find /tmp -maxdepth 1 -type d -regex '/tmp/tmp\.[A-Za-z0-9][A-Za-z0-9]*' -print | head -n 1)
if [ -z "$CERT_DIR" ]; then
  echo "DOCKER_CERT_PATH not found (no /tmp/tmp.* directory)" >&2
  exit 1
fi

# Setup environment variables to talk to the host's Docker daemon
export DOCKER_HOST=tcp://172.17.0.2:4243
export DOCKER_TLS_VERIFY=1
export DOCKER_CERT_PATH="$CERT_DIR"

SCRIPT_PATH=/usr/local/sbin/update-monit-nft.sh
BACKGROUND_PIDS=""

# Kill any background update processes on exit
cleanup() {
  for pid in $BACKGROUND_PIDS; do
    kill "$pid" 2>/dev/null || true
  done
  echo "monit-nft watcher interrupted; exiting" >&2
  exit 0
}
trap cleanup INT TERM

# Run the update script inside the container, retrying if it fails due to the container not being ready yet
run_update_in_container() {
  cid="$1"
  if [ ! -r "$SCRIPT_PATH" ]; then
    echo "missing host script: $SCRIPT_PATH" >&2
    return 1
  fi
  (
    while true; do
      if output=$(docker exec -i "$cid" /bin/sh -s -- < "$SCRIPT_PATH" 2>&1); then
        exit 0
      fi
      case "$output" in
        *"No such container"*)
          echo "container $cid no longer exists; stop retrying" >&2
          exit 0
          ;;
        *"is not running"*)
          echo "container $cid is not running; stop retrying" >&2
          exit 0
          ;;
        *)
          echo "failed to run update-monit-nft.sh inside container $cid; retrying in 1s" >&2
          sleep 1
          ;;
      esac
    done
  ) &
  pid=$!
  BACKGROUND_PIDS="$BACKGROUND_PIDS $pid"
  echo "started background update for container $cid (pid $pid)" >&2
}

# initial update for any already-running containers
for cid in $(docker ps -q 2>/dev/null); do
  run_update_in_container "$cid"
done

# watch for new containers and run update inside them
while true; do
  docker events --filter 'event=start' --format '{{.Actor.ID}} {{.Type}} {{.Action}}' | while read -r id type action; do
    echo "Received docker event: ID=$id Type=$type Action=$action"
    run_update_in_container "$id"
  done || true
  echo "docker events stream ended or failed; retrying after 1s" >&2
  sleep 1
done

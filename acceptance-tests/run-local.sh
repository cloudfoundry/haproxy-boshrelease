#!/usr/bin/env bash

set -eu
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${REPO_DIR}/ci/scripts/functions-ci.sh"
FOCUS=""
KEEP_RUNNING=""

usage() {
    echo -e "Usage: $0 [-F <ginkgo focus target>] [-k]

    -F      Focus on a particular test. Expects a Ginkgo test name. Keep bosh running afterwards.
    -k      Keep bosh container running. Useful for debug." 1>&2; exit 1;
}

while getopts ":F:k" o; do
    case "${o}" in
        F)
            FOCUS=${OPTARG}
            KEEP_RUNNING=true
            ;;
        k)
            KEEP_RUNNING=true
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

check_required_files() {
  PIDS=""
  REQUIRED_FILE_PATTERNS=(
    ci/scripts/stemcell/bosh-stemcell-*-ubuntu-noble.tgz!https://storage.googleapis.com/bosh-core-stemcells/1.238/bosh-stemcell-1.238-warden-boshlite-ubuntu-noble.tgz!no
    ci/scripts/stemcell-jammy/bosh-stemcell-*-ubuntu-jammy-*.tgz!https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-jammy-go_agent!yes
  )

  for entry in "${REQUIRED_FILE_PATTERNS[@]}"; do
    pattern=$(cut -f1 -d! <<<"$entry")
    url=$(cut -f2 -d! <<<"$entry")
    to_resolve=$(cut -f3 -d! <<<"$entry")
    folder=$(realpath "$(dirname "$REPO_DIR/$pattern")")
    filepattern=$(basename "$pattern")
    pattern=$folder/$filepattern

    # shellcheck disable=SC2086
    # glob resolution is desired here.
    if [ -f $pattern ]; then
      continue
    fi

    (
      echo "$filepattern not found, downloading."
      cd "$folder"
      resolved="$url"
      if [ "$to_resolve" == "yes" ]; then
        resolved=$(curl -s --write-out '\n%{redirect_url}' "$url" | tail -n1 | tr -d '\n')
      fi
      echo "Resolved URL: $resolved"
      curl -s --remote-name --remote-header-name --location "$resolved"
      echo "Downloaded '$url' successfully."
      ls -1lh "$folder/"$filepattern
    )&

    PIDS="$PIDS $!"

  done
  # shellcheck disable=SC2086
  # expansion is desired, as $PIDS is a list of PIDs. Wait on all of those PIDs.
  wait $PIDS
}

check_required_files

build_image "${REPO_DIR}/ci"
prepare_docker_scratch

# Run acceptance tests
if [ -n "$KEEP_RUNNING" ] ; then
  echo
  echo "*** KEEP_RUNNING enabled. Please clean up docker scratch after removing containers: ${DOCKER_SCRATCH}"
  echo
  docker run --privileged -v "$REPO_DIR":/repo -v "${DOCKER_SCRATCH}":/scratch/docker -e REPO_ROOT=/repo -e FOCUS="${FOCUS}" -e KEEP_RUNNING="${KEEP_RUNNING}" haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./acceptance-tests ; sleep infinity"
else
  docker run --rm --privileged -v "$REPO_DIR":/repo -v "${DOCKER_SCRATCH}":/scratch/docker -e REPO_ROOT=/repo -e KEEP_RUNNING="" haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./acceptance-tests"
  echo "Cleaning up docker scratch: ${DOCKER_SCRATCH}"
  sudo rm -rf "${DOCKER_SCRATCH}"
fi

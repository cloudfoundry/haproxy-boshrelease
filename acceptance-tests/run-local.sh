#!/usr/bin/env bash

set -eu
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${REPO_DIR}/ci/scripts/functions-ci.sh"
FOCUS=""
PARALLELISM=""
KEEP_RUNNING=""

usage() {
    echo -e "Usage: $0 [-F <ginkgo focus target>] [-P <ginkgo nodes>] [-k]

    -F      Focus on a particular test. Expects a Ginkgo test name. Keep bosh running afterwards.
    -P      Set Ginkgo parallel node count. Default is '-p' (smart parallelism).
    -k      Keep bosh container running. Useful for debug." 1>&2; exit 1;
}

while getopts ":F:P:k" o; do
    case "${o}" in
        F)
            FOCUS=${OPTARG}
            KEEP_RUNNING=true
            ;;
        P)
            PARALLELISM=${OPTARG}
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
    ci/scripts/stemcell/bosh-stemcell-*-ubuntu-noble.tgz!https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-noble?v=1.267
    ci/scripts/stemcell-jammy/bosh-stemcell-*-ubuntu-jammy-*.tgz!https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-jammy-go_agent
  )

  for entry in "${REQUIRED_FILE_PATTERNS[@]}"; do
    pattern=$(cut -f1 -d! <<<"$entry")
    url=$(cut -f2 -d! <<<"$entry")
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
      cd "$folder" && \
      resolved=$(curl -s --write-out '\n%{redirect_url}' "$url" | tail -n1 | tr -d '\n') && \
      echo "Resolved URL: $resolved" && \
      curl -s --remote-name --remote-header-name --location "$resolved" && \
      echo "Downloaded '$url' successfully." && \
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
  docker run --privileged -v "$REPO_DIR":/repo -v "${DOCKER_SCRATCH}":/scratch/docker -e REPO_ROOT=/repo -e FOCUS="${FOCUS}" -e PARALLELISM="${PARALLELISM}" -e KEEP_RUNNING="${KEEP_RUNNING}" haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./acceptance-tests ; sleep infinity"
else
  docker run --rm --privileged -v "$REPO_DIR":/repo -v "${DOCKER_SCRATCH}":/scratch/docker -e REPO_ROOT=/repo -e KEEP_RUNNING="" -e PARALLELISM="${PARALLELISM}" haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./acceptance-tests"
  echo "Cleaning up docker scratch: ${DOCKER_SCRATCH}"
  sudo rm -rf "${DOCKER_SCRATCH}"
fi

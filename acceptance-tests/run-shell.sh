#!/usr/bin/env bash

set -e
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${REPO_DIR}/ci/scripts/functions-ci.sh"

usage() {
    echo -e "Usage: $0 [-k]

    -k      Keep bosh container running. Useful for debug." 1>&2; exit 1;
}

while getopts ":k" o; do
    case "${o}" in
        k)
            KEEP_RUNNING=true
            ;;
        *)
            usage
            ;;
    esac
done

build_image "${REPO_DIR}/ci"

# Run local shell - start new container with bosh
if [ -n "${KEEP_RUNNING}" ] ; then
    docker run -it --privileged -v "$REPO_DIR":/repo -e KEEP_RUNNING="${KEEP_RUNNING}" -e REPO_ROOT=/repo haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./shell ; sleep infinity"
else
    docker run -it --rm --privileged -v "$REPO_DIR":/repo -e KEEP_RUNNING="" -e REPO_ROOT=/repo haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./shell"
fi

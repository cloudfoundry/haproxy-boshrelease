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
prepare_docker_scratch

# Run local shell - start new container with bosh
if [ -n "${KEEP_RUNNING}" ] ; then
    echo
    echo "*** KEEP_RUNNING enabled. Please clean up docker scratch after removing containers: ${DOCKER_SCRATCH}"
    echo
    docker run -it --privileged -v "$REPO_DIR":/repo -v "${DOCKER_SCRATCH}":/scratch/docker -e KEEP_RUNNING="${KEEP_RUNNING}" -e REPO_ROOT=/repo haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./shell ; sleep infinity"
else
    docker run -it --rm --privileged -v "$REPO_DIR":/repo -v "${DOCKER_SCRATCH}":/scratch/docker -e KEEP_RUNNING="" -e REPO_ROOT=/repo haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./shell"
    echo "Cleaning up docker scratch: ${DOCKER_SCRATCH}"
    sudo rm -rf "${DOCKER_SCRATCH}"
fi

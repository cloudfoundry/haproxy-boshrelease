#!/usr/bin/env bash

set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${REPO_DIR}/ci/scripts/functions-ci.sh"

build_image "${REPO_DIR}/ci"

# Run local shell
docker run -it --rm --privileged -v "$REPO_DIR":/repo -e REPO_ROOT=/repo haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./shell"

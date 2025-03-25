#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${SCRIPT_DIR}/../ci/scripts/functions-ci.sh"

build_image "${SCRIPT_DIR}/../ci"

# Run local shell
docker run -it --rm --privileged -v "$REPO_DIR":/repo -e REPO_ROOT=/repo haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./shell"

#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Build acceptance test image if not found.
if docker images -a | grep "haproxy-boshrelease-testflight " ; then
  echo "Found existing testflight image, skipping docker build. To force rebuild delete this image."
else
  pushd "$SCRIPT_DIR/../ci"
    docker build -t haproxy-boshrelease-testflight .
  popd
fi

# Run local shell
docker run -it --rm --privileged -v "$REPO_DIR":/repo -e REPO_ROOT=/repo haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./shell"

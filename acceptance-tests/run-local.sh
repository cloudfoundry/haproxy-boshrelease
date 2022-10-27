#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# if [ "$(git status -s | wc -l)" -gt 0 ]; then
#     echo "You have changes in your Git repository. Commit or clean (e.g. git clean -f) before running."
#     echo "The build will fail otherwise."
#     echo "Git Status:"
#     git status
#     exit 1
# fi

FOCUS="$1"

docker_mac_check_cgroupsv1() {
    # Force cgroups v1 on Docker for Mac
    # inspired by https://github.com/docker/for-mac/issues/6073#issuecomment-1018793677

    SETTINGS=~/Library/Group\ Containers/group.com.docker/settings.json

    cgroupsV1Enabled=$(jq '.deprecatedCgroupv1' "$SETTINGS")
    if [ "$cgroupsV1Enabled" != "true" ]; then 
        echo "deprecatedCgroupv1 should be enabled in $SETTINGS. Otherwise the acceptance tests will not run on Docker for Mac."
        echo "Check in the README.md for a convenient script to set deprecatedCgroupv1 and restart Docker."
        exit 1
    fi
}

if [ "$(uname)" == "Darwin" ]; then
    docker_mac_check_cgroupsv1
fi

# Build acceptance test image
pushd "$SCRIPT_DIR/../ci" || exit 1
 docker build --no-cache -t haproxy-boshrelease-testflight .
popd || exit 1

# Run acceptance tests
if [ -n "$FOCUS" ]; then
  docker run --privileged -v "$REPO_DIR":/repo -e REPO_ROOT=/repo -e FOCUS="$FOCUS" haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./acceptance-tests ; sleep infinity"
else
  docker run --rm --privileged -v "$REPO_DIR":/repo -e REPO_ROOT=/repo haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./acceptance-tests"
fi

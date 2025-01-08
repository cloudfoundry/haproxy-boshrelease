#!/usr/bin/env bash
FOCUS="$1"

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! [[ $(git status --porcelain=v1 2>/dev/null | wc -l) -eq 0 ]]; then
    echo "You have changes in your Git repository. Commit or clean (e.g. git clean -f) before running."
    echo "The build will fail otherwise."
    echo "Git Status:"
    git status
    exit 1
fi

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

check_required_files() {
  PIDS=""
  REQUIRED_FILE_PATTERNS=(
    ../ci/scripts/stemcell/bosh-stemcell-*-ubuntu-jammy-*.tgz!https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-jammy-go_agent
    ../ci/scripts/stemcell-bionic/bosh-stemcell-*-ubuntu-bionic-*.tgz!https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-bionic-go_agent
  )

  # BPM downloads as uuid and needs manually specifying file name
  if [ ! -f "../ci/scripts/bpm/bpm-release-latest.tgz" ] ; then
    curl -sL https://bosh.io/d/github.com/cloudfoundry/bpm-release -o ../ci/scripts/bpm/bpm-release-latest.tgz
  fi

  for entry in "${REQUIRED_FILE_PATTERNS[@]}"; do
    pattern=$(cut -f1 -d! <<<"$entry")
    url=$(cut -f2 -d! <<<"$entry")
    folder=$(realpath "$(dirname "$SCRIPT_DIR/$pattern")")
    filepattern=$(basename "$pattern")
    pattern=$folder/$filepattern

    # shellcheck disable=SC2086
    # glob resolution is desired here.
    if [ -f $pattern ]; then
      continue
    fi

    (
      echo "$filepattern not found, downloading latest."
      cd "$folder" && \
      resolved=$(curl -s --write-out '\n%{redirect_url}' "$url" | tail -n1) && \
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

if [ "$(uname)" == "Darwin" ]; then
    docker_mac_check_cgroupsv1
fi

# Build acceptance test image
pushd "$SCRIPT_DIR/../ci" || exit 1
 docker build -t haproxy-boshrelease-testflight .
popd || exit 1

# Run acceptance tests
if [ -n "$FOCUS" ]; then
  docker run --privileged -v "$REPO_DIR":/repo -e REPO_ROOT=/repo -e FOCUS="$FOCUS" haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./acceptance-tests ; sleep infinity"
else
  docker run --rm --privileged -v "$REPO_DIR":/repo -e REPO_ROOT=/repo haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./acceptance-tests"
fi

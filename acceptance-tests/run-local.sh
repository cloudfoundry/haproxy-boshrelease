#!/usr/bin/env bash

set -eu
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${REPO_DIR}/ci/scripts/functions-ci.sh"
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
    ci/scripts/stemcell/bosh-stemcell-*-ubuntu-jammy-*.tgz!https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-jammy-go_agent
    ci/scripts/stemcell-bionic/bosh-stemcell-*-ubuntu-bionic-*.tgz!https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-bionic-go_agent
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

build_image "${REPO_DIR}/ci"

# Run acceptance tests
if [ -n "$KEEP_RUNNING" ] ; then
  docker run --privileged -v "$REPO_DIR":/repo -e REPO_ROOT=/repo -e FOCUS="$FOCUS" -e KEEP_RUNNING="${KEEP_RUNNING}" haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./acceptance-tests ; sleep infinity"
else
  docker run --rm --privileged -v "$REPO_DIR":/repo -e REPO_ROOT=/repo -e KEEP_RUNNING="" haproxy-boshrelease-testflight bash -c "cd /repo/ci/scripts && ./acceptance-tests"
fi

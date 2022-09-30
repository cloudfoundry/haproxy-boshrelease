# Acceptance Tests

## Requirements

* Docker installed locally
* A matching Jammy stemcell tgz downloaded to `ci/scripts/stemcell`
  * Get it from https://bosh.io/stemcells/bosh-warden-boshlite-ubuntu-jammy-go_agent
* A matching Bionic stemcell tgz downloaded to `ci/scripts/stemcell-bionic`
  * Get it from https://bosh.io/stemcells/bosh-warden-boshlite-ubuntu-bionic-go_agent
* A BPM release tgz downloaded to `ci/scripts/bpm`
  * Get it from https://bosh.io/releases/github.com/cloudfoundry/bpm-release?all=1

## Running

```shell
cd acceptance-tests
./run-local.sh
```

### Running on Docker for Mac

The BOSH Docker CPI requires cgroups v1 to be active. Docker for Mac since 4.3.x uses cgroups v2 by default.

v1 can be restored with the flag `deprecatedCgroupv1` to `true` in `~/Library/Group Containers/group.com.docker/settings.json`.

A convenience script that does this for you is below.

**WARNING:** This will restart your Docker Desktop!

```shell
docker_restart_with_cgroupsv1() {
    SETTINGS=~/Library/Group\ Containers/group.com.docker/settings.json

    if ! command -v jq >/dev/null || ! command -v sponge; then
        echo "Requires jq and sponge. Consider installing via:"
        echo "   brew install jq moreutils"
        return
    fi

    cgroupsV1Enabled=$(jq '.deprecatedCgroupv1' "$SETTINGS")
    if [ "$cgroupsV1Enabled" = "true" ]; then
        echo "deprecatedCgroupv1 is already set to 'true'. Acceptance tests should work."
    else
        echo "Stopping Docker to set the config flag deprecatedCgroupv1 = true in $SETTINGS"

        while docker ps -q 2>/dev/null; do
            launchctl stop $(launchctl list | grep docker.docker | awk '{print $3}')
            osascript -e 'quit app "Docker"'
            echo "Waiting for Docker daemon to stop responding."
            sleep 1
        done
        echo 'Setting "deprecatedCgroupv1" to true.'

        # Add the needed cgroup config to docker settings.json
        # sponge is needed because we're updating the same file in place
        echo '{"deprecatedCgroupv1": true}' |
            jq -s '.[0] * .[1]' "$SETTINGS" - |
            sponge "$SETTINGS"
        # Restart docker desktop
        echo "Restarting Docker"
        open --background -a Docker

        while ! docker ps -q 2>/dev/null; do
            echo "Waiting for Docker daemon to be back up again. Sleeping 1s."
            sleep 1
        done
    fi

    docker info | grep "Cgroup"
}

docker_restart_with_cgroupsv1
```

The output at the end should be:
```plain
 Cgroup Driver: cgroupfs
 Cgroup Version: 1
```

### Focussed Tests

If you want to run only a specific part of the suite, you can use [focussed specs](https://onsi.github.io/ginkgo/#focused-specs)

The easiest way is to just provide the name of the tests you want to run as a command line argument like so:

```shell
./run-local.sh "description of the test to run"
```
The argument is passed as a regular expression that will match all `Describe`, `Context` or `It` closure descriptions in the suite.
So, e.g. if you want to run all tests that use mTLS, you can run:
```shell
./run-local.sh mTLS
```

However, if you want to run exactly one specific test, make sure you pass the exact description of the matching `It` closure:

```shell
./run-local.sh "Correctly terminates mTLS requests"
```

Alternatively, you add an `F` to your `Describe`, `Context` or `It` closures.
Don't forget to do a local commit before running the tests, else BOSH will fail to produce a release. The git repo must be clean before running the tests.

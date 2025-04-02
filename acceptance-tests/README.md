# Acceptance Tests

## Requirements

* Docker installed locally
* x86 based computer (cloudfoundry currently doesn't build/run on arm; rosetta can't run docker in docker for x86)

## Running

```shell
cd acceptance-tests
./run-local.sh
```

### Running on Docker for Mac

Unfortunately rosetta on arm based macs doesn't support docker in docker required for bosh docker-cpi used in this test setup. You will either have to run on x86 based mac or some remote x86 workstation. Virtualization using QEMU is possible, but so slow the tests fail on timeouts.

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

The easiest way is to just provide the name of the tests you want to run as a `-F` command line argument:

```shell
./run-local.sh -F "description of the test to run"
```

The argument is passed as a regular expression that will match all `Describe`, `Context` or `It` closure descriptions in the suite.
So, e.g. if you want to run all tests that use mTLS, you can run:

```shell
./run-local.sh -F mTLS
```

However, if you want to run exactly one specific test, make sure you pass the exact description of the matching `It` closure:

```shell
./run-local.sh -F "Correctly terminates mTLS requests"
```

Running tests in focus will also preserve the bosh container running after tests complete, so that you can easily run tests again without having to wait for bosh set-up again.

### Persistent BOSH

Because BOSH setup takes a while (it starts from scratch with bosh create-env), it is useful to preserve the container with bosh already configured to run tests. This can be done either by providing test focus as described above, or `-k` (keep) switch to `run-local.sh` and `run-shell.sh` scripts, e.g. `run-shell.sh -k`. Once initial setup is complete, scripts will output a message about how to get back into the running container:

```text
KEEP_RUNNING is true and bosh remains running.
Re-enter container via: docker exec -it b7c767c5c0e4 bash

Stop with: docker stop b7c767c5c0e4
```

After you have completed your work and have stopped the container, it is required you do further cleanup. In order to have a working overlay2 filesystem for docker-cpi, it is necessary to mount ext4 based storage from `/workspace/docker-in` into the bosh container. Each container gets its own temporary space, which in case of containers that keep running is not deleted when the tests complete. The scripts will output the location of this temporary storage:

```text
*** KEEP_RUNNING enabled. Please clean up docker scratch after removing containers: /workspace/docker-in/scratch-19517
```

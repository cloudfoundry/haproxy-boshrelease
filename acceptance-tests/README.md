# Acceptance Tests

## Requirements

* Docker installed locally
* x86 based computer (cloudfoundry currently doesn't build/run on arm; rosetta can't run docker in docker for x86)

## Running

```shell
cd acceptance-tests
./run-local.sh
```

### TLS Backend Variant

By default the tests run against HAProxy linked to the system OpenSSL from the stemcell. To exercise a different TLS backend, set the `VARIANT` environment variable:

```shell
VARIANT=awslc              ./run-local.sh   # AWS-LC, non-FIPS
VARIANT=awslc-fips         ./run-local.sh   # AWS-LC FIPS
VARIANT=patched            ./run-local.sh   # system OpenSSL + HAProxy patches
VARIANT=awslc-patched      ./run-local.sh   # AWS-LC + patches
VARIANT=awslc-fips-patched ./run-local.sh   # AWS-LC FIPS + patches
VARIANT=multi              ./run-local.sh   # multi release (all binaries bundled)
```

A single invocation runs the suite **once** against the chosen variant — `run-local.sh` is not a matrix runner. To cover several variants, invoke it once per variant in a shell loop. Each run rebuilds the BOSH release from scratch, and AWS-LC variants compile the library inside the BOSH compilation VM, so a full sweep takes hours rather than minutes.

When using `-k` (keep BOSH running, see below) the cached state belongs to whichever variant ran last — switching `VARIANT` inside a kept container is not supported. Stop the container between variants, or run without `-k`.

### Running on Docker for Mac

Acceptance tests cannot be run on Mac with arm64 architecture:
* Docker-in-Docker, which is required by this test setup, is not supported on arm64.
* The `ghcr.io/cloudfoundry/bosh/docker-cpi` image is only built for x86 and will not run on arm64.

You will need to use an x86-based Mac or a remote x86 workstation instead. Virtualization via QEMU is possible, but is too slow in practice — tests will fail on timeouts.

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

### Parallelism

By default, Ginkgo runs the test suite with smart parallelism (`-p`), automatically choosing the number of parallel nodes based on the available CPU count. You can override this with the `-P` flag:

```shell
./run-local.sh -P 4
```

This sets the number of Ginkgo parallel nodes to `4`. Set it to `1` to run tests sequentially, which can be useful for debugging flaky tests or when the host machine has limited resources.

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

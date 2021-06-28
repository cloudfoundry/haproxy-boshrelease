# Acceptance Tests

### Requirements:

* Docker installed locally
* A matching stemcell tgz downloaded to `ci/scripts/stemcell`
  * Get it from https://bosh.io/stemcells/bosh-warden-boshlite-ubuntu-xenial-go_agent
* A BPM release tgz downloaded to `ci/scripts/bpm`
  * Get it from https://bosh.io/releases/github.com/cloudfoundry/bpm-release?all=1

#### Running:

```shell
cd acceptance-tests
./run-local.sh
```

#### Focussed tests:
If you want to run only a specific part of the suite, you can use [focussed specs](https://onsi.github.io/ginkgo/#focused-specs)

The easiest way is to just add an `F` to your `Describe`, `Context` or `It` closures.
Don't forget to do a local commit before running the tests, else BOSH will fail to produce a release. The git repo must be clean before running the tests.
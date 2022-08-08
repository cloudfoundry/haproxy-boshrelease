# Continuous Integration Setup

The CI environment is maintained by the SAP Business Technology Platform on Cloud Foundry team for Routing and Networking (CFN).

## Contact

Credentials and admin access lie with that team. If you have questions or issues, please reach out via the [#haproxy-boshrelease](https://cloudfoundry.slack.com/archives/C0XRT9L22) channel on Slack.

## Setup

Concourse is used as CI system. There are two main types of tests and various release specific steps, all of which are defined in [pipeline.yml](pipeline.yml).

* `unit-tests` runs a series of unit tests on the Ruby templating based configuration file generators and includes linters for all code and test code.
* `acceptance-tests` and `acceptance-tests-pr` runs a series of acceptance tests developed in Go.
  * `acceptance-tests-pr` is executed for each PR that is marked with the `run-ci` label, while
  * `acceptance-tests` is run on new commits to `master`, e.g. after a PR has been merged.

All tests run in Docker. The image `iacbox.common.repositories.cloud.sap/haproxy-boshrelease-testflight` is a built and cached version of building [`Dockerfile`](Dockerfile).

***Note, August 2022***: The image used for acceptance tests is currently outdated and will be updated to a recent state in the near future. An updated version is so far only used for the autobump scripts.

### Unit Tests

Unit tests are executed via `rake` and are contained in [spec/haproxy/templates](../spec/haproxy/templates).

### Acceptance Tests

The acceptance tests run a full BOSH director and exercise creating and running the candidate `haproxy-boshrelease` against a test suite that covers a wide range of features and use cases supported by it.

The code can be found in [acceptance-tests](../acceptance-tests/).

The `haproxy-boshrelease` is deployed via the manifest defined in [manifests/haproxy.yml](../manifests/haproxy.yml). Most of the tests use BOSH ops-files to modify this manifest before running it.

The deployed HAProxy will in most cases have a functioning backend that simply responds with `Hello cloud foundry` to HTTP requests. This backend can be omitted and will lead to a failure state, as HAProxy in its current configuration requires the backend to start.

#### Writing new Acceptance Tests

There are examples for various types of tests already in the source code. Those include startup and draining behaviour, various types of requests and specific configurations where HAProxy modifies the request as well as general functionality checks to avoid regressoins.

 There are a few things to highlight when developing new acceptance tests:

1. The HAProxy deployed via the release is run in a container. The port to HAProxy and to the backend are forwarded via SSH tunnel to the test runner and allow interacting with either of those servers.
2. The HAProxy deployment is carried out by:

   ```golang
   func deployHAProxy(baseManifestVars baseManifestVars, 
                      customOpsfiles []string, 
                      customVars map[string]interface{}, 
                      expectSuccess bool) (haproxyInfo, varsStoreReader) { ... }
   ```

   Using `expectSuccess`, the boshrelease can be started with an incomplete configuration and manipulated by the test. This is useful, when additional resources are referenced in the HAProxy configuration and need to be uploaded to the container where HAProxy runs. Because its address is only known once BOSH deploys this container, it is not possible to upload files ahead of time.
3. Use ginkgo's "Focus" feature to execute a single test instead of the complete acceptance test suite by adding `F` to the `Declare` statements in a test, i.e. `FDeclare(...)` vs. `Declare(...)`.
4. Most tests involve ops-files, which modify the deployment manifest. Those ops-files can be tested locally via BOSH, using:

   ```shell
   bosh interpolate manifests/haproxy.yml --ops-file opsfile.yml
   ```

   This command will output (but not overwrite) the resulting HAProxy manifest after the ops-file has been applied. This is also the most convenient way to ensure that the syntax and functionality in the ops-file are correct and can be handled by the BOSH CLI.

#### Running Acceptance Tests Locally

***Note August 2022***: There is currently a mismatch between current Docker / Docker for Mac distributions and the way the `docker-cpi` for BOSH works. Running BOSH and thus the acceptance tests with the scripts as they are in this repository is currently not possible, but is being worked on.

### Version Autobumps for Dependencies

The HAProxy BOSH release contains various software bundles that comprise the release. These software bundles are retrieved from the respective web sites or GitHub, as applicable.
Versions are pinned to the currently used major or minor release of the software bundle as appropriate.

The overall logic and pinned versions are defined in the [scripts/autobump-dependencies.py](scripts/autobump-dependencies.py) script.

New upstream releases that fit the pinned version will create PRs automatically that update to the latest available version. For releases that go beyond the pinned version, the pinning can be updated and will lead to PRs for the respective new version that now matches the pinning.

Autobumping is executed daily, currently in a time slot between 7:00 - 8:00 AM central european time.

A new PR is created for each updated dependency. You may need to rebase still open autobump PRs if they were not merged before larger other changes.

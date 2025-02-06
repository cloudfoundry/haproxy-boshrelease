# Continuous Integration Setup

The CI environment is maintained by the SAP Business Technology Platform on Cloud Foundry team for Routing and Networking.

All secrets used in the pipeline and surrounding tools are kept in the team's Vault. Those secrets are only necessary for [modifying the pipeline](#updating-or-modifying-the-pipeline). For git integration, [haproxy-boshrelease pipeline](https://concourse.arp.cloudfoundry.org/teams/main/pipelines/haproxy-boshrelease) has public visibility.

## Contact

Credentials and admin access lie with that team. If you have questions or issues, please reach out via the [#haproxy-boshrelease](https://cloudfoundry.slack.com/archives/C0XRT9L22) channel on Slack.

## Setup

Concourse is used as CI system. There are two main types of tests and various release specific steps, all of which are defined in [pipeline.yml](pipeline.yml).

* `unit-tests` runs a series of unit tests on the Ruby templating based configuration file generators and includes linters for all code and test code.
* `acceptance-tests` and `acceptance-tests-pr` runs a series of acceptance tests developed in Go.
* `unit-tests-pr` and `acceptance-tests-pr` are executed for PRs that are marked with the `run-ci` label AND authored by a member of [`wg-app-runtime-platform-networking-approvers`](https://github.com/orgs/cloudfoundry/teams/wg-app-runtime-platform-networking-approvers) or technical users like `dependabot` or `CFN-CI`.
* `unit-tests-pr` and `acceptance-tests-pr` are executed for each approved PR that is marked with the `run-ci` label.
* `acceptance-tests` is run on new commits to `master`, e.g. after a PR has been merged.

All tests run in Docker. The image `cf-routing.common.repositories.cloud.sap/haproxy-boshrelease-testflight` is a built and cached version of building [`Dockerfile`](Dockerfile).

### Unit Tests

Unit tests are executed via `rake` and are contained in [spec/haproxy/templates](../spec/haproxy/templates).

### Acceptance Tests

The acceptance tests run BOSH director and exercise creating and running the candidate `haproxy-boshrelease` against a test suite that covers a wide range of features and use cases supported by it.

The code can be found in [acceptance-tests](../acceptance-tests/).

The `haproxy-boshrelease` is deployed via the manifest defined in [manifests/haproxy.yml](../manifests/haproxy.yml). Most of the tests use BOSH ops-files to modify this manifest before running it.

The deployed HAProxy will in most cases have a functioning backend that simply responds with `Hello cloud foundry` to HTTP requests. This backend can be omitted and will lead to a failure state, as HAProxy in its current configuration requires the backend to start.

#### Writing new Acceptance Tests

There are examples for various types of tests already in the source code. Those include startup and draining behaviour, various types of requests and specific configurations where HAProxy modifies the request as well as general functionality checks to avoid regressions.

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

#### Skipping Acceptance Tests on Certain Pull Requests

Since the acceptance tests are very time consuming, they are skipped for certain changes. The tests are not run if the pull request contains only minor changes such as `README.md` or `release_notes.md`.

The list of ignored files is maintained in [.ci-ignore](https://github.com/cloudfoundry/haproxy-boshrelease/blob/master/ci/.ci-ignore) and contains individual files as well as folders such as `docs`.

**Caveat:** The regular (non-PR triggered) acceptance tests are not skippable in this way.

#### Running Acceptance Tests Locally

***Note August 2022***: There is currently a mismatch between current Docker / Docker for Mac distributions and the way the `docker-cpi` for BOSH works. Running BOSH and thus the acceptance tests with the scripts as they are in this repository is currently not possible, but is being worked on.

The acceptance test validation (`acceptance-tests-pr`) in the Concourse pipeline can be used in the interim. It is enabled by setting the `run-ci` label on a PR.

### Version Autobumps for Dependencies

The HAProxy BOSH release contains various software bundles that comprise the release. These software bundles are retrieved from the respective web sites or GitHub, as applicable.
Versions are pinned to the currently used major or minor release of the software bundle as appropriate.

The overall logic and pinned versions are defined in the [scripts/autobump-dependencies.py](scripts/autobump-dependencies.py) script.

New upstream releases that fit the pinned version will create PRs automatically that update to the latest available version. For releases that go beyond the pinned version, the pinning can be updated and will lead to PRs for the respective new version that now matches the pinning.

Autobumping is executed daily, currently in a time slot between 7:00 - 8:00 AM central european time.

A new PR is created for each updated dependency. You may need to rebase still open autobump PRs if they were not merged before larger other changes.

## Updating or Modifying the Pipeline

A concourse pipeline is stored on the Concourse server's database. The `pipeline.yml` file is versioned in Git but needs to be uploaded explicitly to the server. It is kept in Git for version control and reference, but will not be automatically loaded into concourse when changed in the Git repository.

The pipeline `haproxy-boshrelease` is used to build, verify and release this BOSH release. It should remain working at all times.

New pipeline steps should be added without modifying existing steps or resources, or in a separate pipeline altogether.

A pipeline can be uploaded to concourse via the [`upload-to-concourse.sh`](upload-to-concourse.sh) script. The script and pipeline require some secrets (`vars.yml`), which can be found in the team's Vault. The script will also expose the pipeline.

### Testing new Pipeline Steps in a Branch

While developing new scripts or pipeline steps, these steps will not be in the Git `master` branch. In order to access them, _copy_ the resource `git` and define this separate resource to check out the particular branch you are working on.

Please note that the name of a git resource influences the directory name in the workspace, i.e. the directory will not be called `git` but whatever you called your copied git resource.

Note that you can use the `dir` parameter in `run` to define the working directory for the command to be called:

```yaml
    [...]
    run:
        # `dir` defines the working directory for the executed command
        dir: git-resource-and-directory-name
        path: /path/to/your/command
        args:
         - arg1
         - arg2
    [...]
```

Don't forget to remove separate pipelines that were created for testing.

Note that your test pipeline does not need to be publicly exposed. [`upload-to-concourse.sh`](upload-to-concourse.sh) does that by default, so if this is undesirable you can `fly hide-pipeline` afterwards.

### Versioning Guide

For creating a new release please follow the versioning guide based on the [Semantic Versioning Specification](https://semver.org/).

* **Major Version** (*X*.y.z) -- incremented if any backwards incompatible changes are introduced to the public API

  Used for new HAProxy **minor** versions, as they could contain breaking changes.
* **Minor Version** (x.*Y*.z) -- incremented if new, backwards compatible functionality is introduced to the public API
  
  Used when upgrading dependencies (e.g. PCRE, socat, etc.) or HAProxy **patch** versions.
* **Patch Version** (x.y.*Z*) -- incremented if only backwards compatible bug fixes are introduced
  
  Used for documentation updates, changes in the test suite or any updates in the testing frameworks (e.g. ginkgo).

Since releases `11.16.3` and `11.17.5` the build metadata has been included into the version number. The build metadata denotes the contained HAProxy version. As an example, `11.16.2+2.6.9` means that HAProxy 2.6.9 is used.

The `haproxy-boshrelease` also contains patches (see [haproxy-patches](../haproxy-patches)). The patched version is a part of the build metadata and is denoted by appending a hyphen and key word `patched`, like `11.17.4+2.6.9-patched`.

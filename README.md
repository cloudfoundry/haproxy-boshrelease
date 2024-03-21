BOSH Release for haproxy
===========================

Test for skip-ci

Questions? Pop in our [slack channel](https://cloudfoundry.slack.com/messages/haproxy-boshrelease/)!

This BOSH release is an attempt to get a more customizable/secure haproxy release than what
is provided in [cf-release](https://github.com/cloudfoundry/cf-release). It allows users to
blacklist internal-only domains, preventing potential Host header spoofing from allowing
unauthorized access of internal APIs. It also allows for better control over haproxy's
timeouts, for greater resiliency under heavy load.

Usage
-----

To deploy this BOSH release:

```
git clone https://github.com/cloudfoundry-community/haproxy-boshrelease.git
cd haproxy-boshrelease

export BOSH_ENVIRONMENT=<alias>
export BOSH_DEPLOYMENT=haproxy
bosh2 deploy manifests/haproxy.yml \
  -v haproxy-backend-port=80 \
  -v "haproxy-backend-servers=[10.10.10.10,10.10.10.11]"
```

To make alterations to the deployment you can use the `bosh2 deploy [-o operator-file.yml]` flag to provide [operations files](https://bosh.io/docs/cli-ops-files.html).

Alternately you can build a manifest using `templates/make_manifest`

You can either use the templates + examples provided to merge this in with an existing CloudFoundry
deployment, or create a new deployment using this command:

```
make_manifest <aws-ec2|warden> <comma-separated-list-of-router-servers> <additional_templates>
```

**NOTE**: `make_manifest` requires [spruce v1.8.9](https://github.com/geofffranks/spruce) or newer.

```
# Example for bare bones bosh-lite haproxy release on warden
templates/make_manifest warden 10.244.0.22
bosh deploy

# Example for using keepalive with haproxy on warden:
KEEPALIVED_VIP=10.244.50.2 templates/make_manifest warden 10.244.0.22
```

## Development

Feel free to contribute back to this via a pull request on a feature branch! Once merged, we'll
cut a new final release for you.

### Unit Tests and Linting

#### PR Validation
PRs will be automatically tested by https://concourse.cfi.sapcloud.io/teams/main/pipelines/haproxy-boshrelease once a maintainer has labelled the PR with the `run-ci` label

#### Local Test Execution
Unit/rspec Tests and linters can be run locally to verify correct functionality before pushing to the CI system.
If you change any erb logic in the jobs directory please add a corresponding test to `spec`.

```bash
# install the necessary dependencies, once
bundle package
```

```bash
# run the rspec / unit tests for the configuration generation
cd haproxy_boshrelease
bundle install
bundle exec rake spec
```

```bash
# run the linter (rubocop) to identify any issues
cd haproxy_boshrelease
bundle install
bundle exec rake lint
```

```bash
# watch the tests while developing
cd haproxy_boshrelease
bundle install
bundle exec guard
```

#### Test Debugging
Unit/rspec Tests can also be debugged/stepped through when needed. See for example the [VSCode rdbg Ruby Debugger](https://marketplace.visualstudio.com/items?itemName=KoichiSasada.vscode-rdbg) extension. You can follow the "Launch without configuration" instructions for the extension, just set the "Debug command line" input to `bundle exec rspec <filepath>`.

### Acceptance tests

See [acceptance-tests README](/acceptance-tests/README.md).

### Certificate reloads during runtime

See [external_certs README](/docs/external_certs.md)

# Acceptance Tests

Requirements:

* A running BOSH director with internet access with a cloud config that has a 'default' network and 'default' vm-type
* A release to test which has been uploaded to the BOSH director
* The following env vars set
  * `REPO_ROOT`: Absolute path to this repo
  * `RELEASE_VERSION`: The version of HAProxy to test (should match the version uploaded to the BOSH director)
  * `BOSH_CA_CERT`
  * `BOSH_CLIENT`
  * `BOSH_CLIENT_SECRET`
  * `BOSH_ENVIRONMENT`
  * `BOSH_PATH`: Path to BOSH CLI
  * `BASE_MANIFEST_PATH`: The absolute path to the [HAProxy base manifest](https://github.com/cloudfoundry-incubator/haproxy-boshrelease/blob/master/manifests/haproxy.yml)
  * `HOME`
* Go runtime installed
* [Ginkgo CLI](https://onsi.github.io/ginkgo/) installed

Running:

```shell
cd acceptance-tests
ginkgo -v -r -debug -trace -progress
```

BOSH Release for cf-haproxy
===========================

This BOSH release is an attempt to get a more customizable/secure haproxy release than what is provided in [cf-release](https://github.com/cloudfoundry/cf-release). It allows users to blacklist internal-only domains, preventing potential Host header spoofing from allowing unauthorized access of internal APIs. It also allows for better control over haproxy's timeouts, for greater resiliency under heavy load.

Usage
-----

To use this bosh release, first upload it to your bosh:

```
bosh upload release https://bosh.io/d/github.com/cloudfoundry-community/cf-haproxy-boshrelease
```

To deploy it, you will need the repository that contains templates:

```
git clone https://github.com/cloudfoundry-community/cf-haproxy-boshrelease.git
cd cf-haproxy-boshrelease
git checkout latest
```

You can either use the templates + examples provided to merge this in with an existing CloudFoundry deployment, or create a new deployment, via `make_manifest <aws-ec2|warden> <comma-separated-list-of-router-servers> <additional_templates>`

```
# Example for bare bones bosh-lite cloudfoundry release on warden
templates/make_manifest warden 10.244.0.22
bosh verify deployment
bosh deploy
```

### Development

Feel free to contribute back to this via a pull request on a feature branch! Once merged, we'll cut a new final release for you.

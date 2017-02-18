BOSH Release for haproxy
===========================

Questions? Pop in our [slack channel](https://cloudfoundry.slack.com/messages/haproxy-boshrelease/)!

This BOSH release is an attempt to get a more customizable/secure haproxy release than what
is provided in [cf-release](https://github.com/cloudfoundry/cf-release). It allows users to
blacklist internal-only domains, preventing potential Host header spoofing from allowing
unauthorized access of internal APIs. It also allows for better control over haproxy's 
timeouts, for greater resiliency under heavy load.

Usage
-----

To use this bosh release, first upload it to your bosh:

```
bosh upload release https://bosh.io/d/github.com/cloudfoundry-community/haproxy-boshrelease
```

To deploy it, you will need the repository that contains templates:

```
git clone https://github.com/cloudfoundry-community/haproxy-boshrelease.git
cd haproxy-boshrelease
git checkout latest
```

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

### Development

Feel free to contribute back to this via a pull request on a feature branch! Once merged, we'll
cut a new final release for you.

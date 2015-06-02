# BOSH Release for cf-haproxy

This BOSH release is an attempt to get a more customizable/secure haproxy
release than what is provided in [cf-release](https://github.com/cloudfoundry/cf-release).
It allows users to blacklist internal-only domains, preventing potential Host header spoofing
from allowing unauthorized access of internal APIs. It also allows for better control over haproxy's
timeouts, for greater resiliency under heavy load.

## Usage

To use this bosh release, first upload it to your bosh:

```
bosh upload release https://bosh.io/d/github.com/cloudfoundry-community/sslproxy-boshrelease
```

To deploy it, you will need the repository that contains templates:

```
git clone https://github.com/cloudfoundry-community/sslproxy-boshrelease.git
cd sslproxy-boshrelease
git checkout latest
```

Now update the examples/<iaas>*.yml with your settings.

Finally, target and deploy:

```
bosh deployment examples/<iaas>.yml
bosh verify deployment
bosh deploy
```

### Development

Feel free to contribute back to this via a pull request on a feature branch! Once merged, we'll
cut a new final release for you.

After the first release you need to contact [Dmitriy Kalinin](mailto://dkalinin@pivotal.io) to request your project is added to https://bosh.io/releases (as mentioned in README above).

# New Features

- Support has been added for pulling in certificates to be managed
  out of band to `haproxy-boshrelease`. This is useful for cases where
  many certs need to be provided to HAProxy in an on demand basis without
  doing a full bosh deploy + restarting HAProxy every time a client's
  certificate changes. See the [docs](https://github.com/cloudfoundry-incubator/haproxy-boshrelease/blob/master/docs/external_certs.md) for more details!

# Acknowledgments

Thanks @domdom82 for the feature!

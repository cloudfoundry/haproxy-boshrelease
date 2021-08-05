# Fixes
- Host header and SNI are now treated as case insensitive in domain fronting checks [details](https://github.com/cloudfoundry-incubator/haproxy-boshrelease/pull/238)

# New Features
- The `client_cert_ignore_err` property now also applies to errors in the CA-file. Previously it would only ignore errors in the certificate itself. [details](https://github.com/cloudfoundry-incubator/haproxy-boshrelease/pull/236)
- Added experimental support for hot-patching releases. The `haproxy-11.4.0.tgz` asset remains as the default release and contains the unaltered haproxy source. [details](https://github.com/cloudfoundry-incubator/haproxy-boshrelease/pull/237)

# Acknowledgements

Thanks @peterellisjones and @domdom82 for the PRs / fixes!

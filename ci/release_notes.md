# Fixes
- Additional mTLS headers will now follow the same logic as the XFCC header [details](https://github.com/cloudfoundry-incubator/haproxy-boshrelease/blob/master/jobs/haproxy/spec#L338)
- The `disable_domain_fronting` property now only applies if the client sends a SNI on the TLS handshake. This can be combined with the `strict_sni` setting to force every client to use SNI.

# New Features
- The `disable_domain_fronting` property now has a third option `mtls_only` that will prevent domain fronting only for mTLS requests [details](https://github.com/cloudfoundry-incubator/haproxy-boshrelease/blob/master/jobs/haproxy/spec#L74)

# Acknowledgements

Thanks @peterellisjones for the PRs and fixes!

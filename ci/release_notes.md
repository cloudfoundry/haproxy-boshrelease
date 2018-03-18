# New Features
- `haproxy` has been upgraded to v1.8.4 from v1.6.12
- `haproxy` is now build with pcre2 10.32, and pcre2 JIT enabled
- With the introduction of haproxy v1.8.4, there is now support for
  per-certificate TLS binding options. To make use of this, use
  `ha_proxy.crt_list` instead of `ha_proxy.ssl_pem`. It allows
  custom `client_ca_file`, `verify`, `ssl_ciphers`, `client_revocation_list`,
  settings for each provided certificate, as well as an `snifilter` to
  restrict use of each cert to specific domains.

  For more information:
  - https://cbonte.github.io/haproxy-dconv/1.8/configuration.html#5.1-crt-list
  - https://github.com/cloudfoundry-incubator/haproxy-boshrelease/blob/master/jobs/haproxy/spec#L83-L127
- There is now an `ha_proxy.disable_tcp_accept_proxy` parameter to disable the PROXY protocol
  for tcp-based backends while still leaving it enabled for http/https based backends

# Fixes
- `haproxy.config.erb` has been cleaned up considerably, and
  should be a lot more readable pre and post template rendering.
- The HTTP frontend now supports accept-proxy.
- Bugs where accept-proxy was not honored during mutual TLS have been
  resolved
- `ha_proxy.client_cert` is no longer required to enable TLS. It is
  still honored to enable mutual tls, but the boshrelease will also
  use the presence of the following parameters to enable mutual TLS:
  - `ha_proxy.client_ca_file`
  - `ha_proxy.client_revocation_list`
  - `ha_proxy.crt_list.<i>.client_ca_file`
  - `ha_proxy.crt_list.<i>.client_revocation_list`
  - `ha_proxy.crt_list.<i>.verify` - only when value is not "none"
- The following options are now honored in the `:4443` backend:
  - `ha_proxy.cidr_whitelist`
  - `ha_proxy.cidr_blacklist`
  - `ha_proxy.block_all`
  - `ha_proxy.hsts_*`
  - `ha_proxy.rsp_headers`
- The `X-Forwarded-Client_Cert` header is now set for requests in the `:4443`
  backend.
- The `X-Forwarded-Proto` header behavior in the `:4443` backend now
  matches the behavior in the `:443` backend
- Spec descriptions + examples were updated for `resolvers`

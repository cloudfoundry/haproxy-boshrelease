# New Features

- `haproxy_boshrelease` now supports the same `X-Forwarded-Client-Cert` behaviors as the
  gorouter. You can set `ha_proxy.forwarded_client_cert` to `always_forward_only`, `forward_only`,
  or `sanitize_set`. However, the default for `haproxy_boshrelease` is `sanitize_set`. This differs
  from previous behaviors.

# Acknowledgements

Thanks to @jgf for supplying this feature!

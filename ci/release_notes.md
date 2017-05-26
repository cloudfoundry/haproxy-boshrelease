# Improvements

- Operators can now optionally disable TLS v1.0 or TLS v1.1, via
  the `ha_proxy.disable_tls_10` and `haproxy.disable_tls_11` properties.
  Default behavior is unchanged, and TLS v1.0/v1.1/v1.2 are enabled
  by default.

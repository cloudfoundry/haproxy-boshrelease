# Bug Fixes

- Resolved an issue where certs specified using the new `cert_chain`
  and `private_key` would result in an invalid cert file, if a newline
  wasn't provided in the `cert_chain` value. Leading + trailing whitespace
  are now removed, and the newline is added for you.
- When using links for the TCP backend, the `health_check_http` property is now consumed, to
  set up an HTTP health check for the backend. If not there, it will fail
  to the default `ha_proxy.tcp_link_health_check_http` value (or if that
  isn't present, no health check is enabled)

# Acknowledgements

Thanks @ryanmoran and @philippthun for the fixes!

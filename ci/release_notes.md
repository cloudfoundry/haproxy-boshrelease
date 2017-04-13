# Improvements

- Removed RC4 ciphers from the default cipher suite
- Added HSTS support via the `ha_proxy.enable_hsts`,
  `ha_proxy.hsts_include_subdomains`, `ha_proxy.hsts_preload`,
  and `ha_proxy.hsts_max_age` properties. HSTS is off by default.
- Added support for disabling TLS tickets to improve Forward
  Secrecy, via `ha_proxy.disable_tls_tickets`. TLS tickets are
  disabled by default

# Acknowledgements

- Many thanks to @lcacciagioni for his work on these SSL
  improvements!

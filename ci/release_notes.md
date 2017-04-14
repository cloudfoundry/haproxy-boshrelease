# Improvements

- Removed RC4 ciphers from the default cipher suite
- Added HSTS support via the `ha_proxy.enable_hsts`,
  `ha_proxy.hsts_include_subdomains`, `ha_proxy.hsts_preload`,
  and `ha_proxy.hsts_max_age` properties. HSTS is off by default.
- Added support for disabling TLS tickets to improve Forward
  Secrecy, via `ha_proxy.disable_tls_tickets`. TLS tickets are
  disabled by default

- Updated haproxy to v1.6.12 (from 1.6.10)
- Updated pcre to v8.40 (from 8.36)
- Updated socat to v1.7.3.2 (from 1.7.3.1)

# Acknowledgements

- Many thanks to @lcacciagioni for his work on these SSL
  improvements!


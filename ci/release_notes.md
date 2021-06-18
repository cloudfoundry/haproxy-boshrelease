# Fixes
- Several fixes to throw alerts if conflicting configuration properties are set
- certs.ttar: Fixed a bug where OPTIONAL_EXT_CERTS was appended to all internal certs instead of just the crt-list

# New Features
- Tests have been greatly improved with unit and acceptance tests
- Support for HTTP/2 was added
- Support for master CLI was added (see [documentation](http://cbonte.github.io/haproxy-dconv/2.2/management.html#9.4) here)
- Support for ssl_min_version and ssl_max_version properties in crt-list was added

# Acknowledgements

Thanks @gerg for the HTTP/2 PR!
Thanks @b1tamara for the ssl_min_version/ssl_max_version PR!
Thanks @peterellisjones for adding unit and acceptance tests and various fixes!
Thanks @peterellisjones and @46bit for the master CLI PR!

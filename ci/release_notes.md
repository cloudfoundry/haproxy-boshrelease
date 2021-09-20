# Fixes
- `ssl_ciphersuites` no longer has a default value. This fixes support for Xenial stemcells which are not compatible with the HAProxy `ssl-default-server-ciphersuites` and `ssl-default-bind-ciphersuites` config properties as they do not have OpenSSL >= 1.1.1. We also added an acceptance test to catch future changes which break Xenial support.

# New Features
- When using backend healthchecks via `enable_health_check_http: true`, the new flag `disable_monit_health_check_http` can be used to prevent BOSH considering the VMs unhealthy if the HAProxy backends are unhealthy. This can be useful when you deploy HAProxy before deploying your backend servers and therefore have a period of time when the backend servers are not yet deployed.

# Acknowledgements

Thanks @maxmoehl, @crhntr, @jaristiz for the PR / fixes!

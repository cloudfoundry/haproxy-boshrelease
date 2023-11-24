# Fixes
- Fixes sporadic HTTP/2 issues: https://github.com/cloudfoundry/haproxy-boshrelease/issues/571

# New Features
- none

# Upgrades
- `HAProxy` has been upgraded from v2.8.3 to v2.8.4

# Remarks
- haproxy-boshrelease v13.2.0 was skipped due to issues within the CI
- HTTP/2 requests that would be hit by https://github.com/cloudfoundry/haproxy-boshrelease/issues/571, will be successful but the access log writes `SD--`

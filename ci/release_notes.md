# Fixes
- Idle connections will no longer be cut immediately during restarts or reloads. HAproxy will instead try to close them gracefully via `connection: close` [PR](https://github.com/cloudfoundry/haproxy-boshrelease/pull/331)
- HAproxy will no longer restart accidentally during draining. This could happen if HAproxy drained and closed itself before BOSH issued a `monit stop`, giving monit a time window to restart HAproxy again. [PR](https://github.com/cloudfoundry/haproxy-boshrelease/pull/331)

# New Features
- HAproxy now supports Ubuntu Jammy stemcells and OpenSSL 3.0 [PR](https://github.com/cloudfoundry/haproxy-boshrelease/pull/329)

# Upgrades

- `ginkgo` has been upgraded from v1.16.2 to v2.2.0 [PR](https://github.com/cloudfoundry/haproxy-boshrelease/pull/330)

# Acknowledgements

Thanks @domdom82 for the PR / fixes!

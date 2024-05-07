# Announcements
- We deprecate support for `disable_tls_10`, `disable_tls_11`, `disable_tls_12` and `disable_tls_13`, move to `ssl_min_ver` and `ssl-max-ver` instead. The deprecated configuration might be removed with the next major release. 

# Fixes
- :warning: Default health check behavior for Proxy Protocol scenarios was changed: Proxy Protocol is now also enabled for the health check endpoint by default. Use `disable_health_check_proxy: true` to disable it again, see https://github.com/cloudfoundry/haproxy-boshrelease/pull/633 (thanks @a18e) :warning:

# New Features
- For mTLS scenarios, the root CA DN (`ssl_c_r_dn`) is now sent besides other client certificate headers, see https://github.com/cloudfoundry/haproxy-boshrelease/pull/659 (thanks @Mrizwanshaik)
- Rate limiting now also works for IPv6 client IP addresses, see https://github.com/cloudfoundry/haproxy-boshrelease/pull/633 (thanks @a18e)
- SSL versions can be properly set via `ssl_min_ver` and `ssl-max-ver` as a successor of e.g. [no-tlsv10](https://docs.haproxy.org/2.7/configuration.html#5.2-no-tlsv10), see https://github.com/cloudfoundry/haproxy-boshrelease/pull/657 (thanks @kinjelom)
- An additional pre-start script can be defined via `pre_start_script`, see https://github.com/cloudfoundry/haproxy-boshrelease/pull/657 (thanks @kinjelom)
- Authentication for the /stats endpoint can be disabled by defining `stats_user` empty, see https://github.com/cloudfoundry/haproxy-boshrelease/pull/657 (thanks @kinjelom)
- Well formatted raw config can be appended via `raw_blocks` as per spec, see https://github.com/cloudfoundry/haproxy-boshrelease/pull/652. Additional config before `raw_blocks` can be actively switched using `config_mode`, see https://github.com/cloudfoundry/haproxy-boshrelease/pull/657 (thanks @kinjelom)

# Upgrades
- Minor version bumps

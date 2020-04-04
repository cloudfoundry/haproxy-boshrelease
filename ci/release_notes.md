# Breaking Changes

- HAProxy now logs to stdout by default! They will now show up in /var/vcap/sys/log/haproxy
  and can be forwarded using the syslog-boshrelease like any other log. If you wish to use
  syslog to forward logs directly, this can still be accomplished, however you will likely want
  to also set `ha_proxy.log_format` back to `rfc3164` as its default changed to `raw` in support of
  `stdout` logging.

  If you make use of `ha_proxy.nbproc` at a value larger than one, `stdout` logging is not supported,
  and a syslog server must be specified. This is *NOT* required when using `ha_proxy.nbthread > 1`.

- The deprecated `ha_proxy.threads` property has been removed in favor of `ha_proxy.nbproc`
  and `ha_proxy.nbthread`

# New Features

- Support for live config reloading was added via a `reload` script. This can be used in use cases
  where config updates need to happen out of band to BOSH, where stopping and restarting processes
  is too disruptive. No changes were made to traditional BOSH process management for HAProxy as a result
  of this change, but the capability is now there for operators or other processes running on HAProxy
  VMs to trigger these reloads.
- `ha_proxy.maxrewrite` is now tunable for supporting large headers from things like X-Forwarded-Client-Cert.

# Upgrades

- `haproxy` has been upgraded to [v1.9.15](https://www.haproxy.com/blog/haproxy-1-9-has-arrived/) from v1.8.20.
- `pcre2` has been upgraded to [v10.34](https://www.pcre.org/changelog.txt) from v10.31.
- `socat` has been upgraded to [v1.7.3.4](http://www.dest-unreach.org/socat/doc/CHANGES) from v1.7.3.2.

# Acknowledgements

Thanks @domdom82 for the live reloading support and @stefanlay for the header length fix!

# New Features

- Syslog length and format can now be configured via `ha_proxy.log_max_length` and `ha_proxy.log_format`.
  Defaults remain unchanged at 1024 bytes, and rfc3164.

- HAProxy can now bind to the default interface on both IPv4 and IPv6 simultaneously, via the `ha_proxy.v4v6`
  property. When this is set, you must also set the `ha_proxy.binding_ip` to `::` for it to take effect. This
  feature is off by default.


# Acknowledgements

Thanks go to @cunnie for the IPv6 binding, and @msahihi for the log customization PRs!

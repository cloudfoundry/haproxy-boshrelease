# New Features

- `haproxy` now supports a graceful drain on connections (disabled by default).
  To enable it, use `ha_proxy.drain_enable: true`. If haproxy does not complete
  its drain within the `ha_proxy.drain_timeout` perioud (defaults to 30s), it will
  shut off haproxy without waiting for in-flight connections to complete.

  `ha_proxy.drain_frontend_grace_time` can be used to set a delay between shutdown and
  when the frontends stop accepting connections.

# Acknowledgements

Thanks @stefanlay for the new feature!

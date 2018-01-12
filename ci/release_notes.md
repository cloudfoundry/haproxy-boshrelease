# New Features

- *tcp-routing* support. HAProxy can now consume the `tcp-routing` link
  from the [routing-release](https://github.com/cloudfoundry/routing-release/blob/d1e5369935688080e69335058922c2f0970dbfdb/jobs/tcp_router/spec#L18-L20).
  Ports used by HAProxy for this can be controlled via the `ha_proxy.tcp_routing.port_range`
  property.

# Acknowledgements

Thanks @ishustava for adding this feature!

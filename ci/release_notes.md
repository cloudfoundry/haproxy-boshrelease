# Improvements

- The default values for `ha_proxy.keepalive_timeout` and `ha_proxy.request_timeout` have been reduced to `0.2` seconds, and `5` seconds, respectively

- There is now the ability to configure a backend port separate from the frontend port for the TCP backend
  configured via the `tcp_backend` link. If the `backend_port` property is exposed in the link, it is used.
  If not, the `ha_proxy.tcp_link_port` will be used. If that is not set, the `port` link property will be used.

- The HTTP Host header is now logged by HAProxy on http/https backends.

- HAProxy can now be configured to run across multiple cores, for improved performance when handling SSL
  termination, via the `ha_proxy.threads` property. If enabled, this will create additional
  HAProxy `stats` sockets (as well as http-based listeners, if `ha_proxy.stats_bind` is also enabled) - one
  for each new HAProxy process. If you are monitoring HAProxy performance using those endpoints, make sure
  that you grab statistics from each monitoring socket, as each one is tied to a single HAProxy process.

- Generic blacklist + whitelist support has been added for HAProxy for http and https listeners. If specified,
  HAProxy will ensure requests come from an IP that is either whitelisted, or not blacklisted. See the
  `ha_proxy.cidr_blacklist`, `ha_proxy.cidr_whitelist`, and `ha_proxy.block_all` properties.

  These options are separate from the `ha_proxy.internal_only_domains` and `ha_proxy.trusted_domain_cidrs`.
  The latter add ACLs to specific domains, whereas these new settings apply across all traffic.

- The load balancing algorithm for TCP backends can be defined by adding the `balance` property to the backend
  definition. Defaults to `roundrobin`, and must be one of HAProxy's supported load balancing algorithms.

- The HAProxy `tune.bufsize` is now configurable via the `ha_proxy.buffer_size_bytes` property, should HAProxy
  need to be able to handle requests with large cookies/query strings that exceed the default `16384` bytes

- The `ha_proxy.enable_health_check_http` property can be specified to enable a health-check on the
  http/https backend servers. If set to `true`, this will cause HAProxy to listen on `:8080` on the
  HAProxy server's IP. Setting the `health_check_http` property on TCP backend definitions to a port number
  will similarly enable an http-based health check endpoint on the specified port.

# Acknowledgments

Many thanks to Juergen Graf, Soha Alboghdady, and Felix Reyn for all their contributions to this release!

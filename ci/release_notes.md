# New Features

- The `haproxy` job can now be easily configured to use the CF Routing tier's HTTP-based
  health checks. Specify `ha_proxy.backend_use_http_health = true` to enable it. If custom
  ports or URIs are necessary for HTTP backend health checks, they can be specified via
  `ha_proxy.backend_http_health_port` and `ha_proxy.backend_http_health_uri`. There are similar
  properties available for the `ha_proxy.routed_backends` datastructures via `backend_use_http_health`,
  `backend_http_health_port`, and `backend_http_health_uri` properties on each routed backend
  definition.

  Generic TCP routing was not updated with support for custom HTTP backends. However, when the
  `tcp_router` link is consumed from Cloud Foundry, it now enforces the use of HTTP health checks
  to the TCP router. Previously, only a TCP port check on port 80 was done.

- Added a property to allow lua scripts to be easily loaded into the HA proxy config
  via `ha_proxy.lua_scripts`. This is a list of full paths to the lua script on disk.
  You'll want to provide those with some other boshrelease.

- Added a property for providing arbitrary frontend config to haproxy via `ha_proxy.frontend_config`.
  This applies to all of the haproxy frontends.

- Added a property for providing arbitrary backend config to haproxy backends via the `ha_proxy.backend_config`,
  and `ha_proxy.tcp_backend_config` (the former will be used on default + routed HTTP backends, the latter on
  all tcp-mode backends).

- Added a property for providing arbitrary global config to haproxy via `ha_proxy.global_config`.

- Improved logging to include info related to health check/backend status, and elevate log levels for error messages.

# Fixes

- The default logging endpoint has changed from `127.0.0.1` to `/dev/log`, which resolves issues where `haproxy`
  was deployed on a VM that did not have TCP/UDP listeners enabled in `rsyslog`.

# Acknowledgements

Thanks @teancom for helping out with the features for this release!

# New Features
- `ha_proxy.tcp_link_check_port` property added as an optional port for tcp_backend health checks.
- `ha_proxy.forwarded_client_cert` now supports a new `forward_only_if_route_service` option. This allows HAproxy to forward client certificates if (and only if) they are forwarded by a CF route service. Requires gorouter to check the validity of the route service secret for security.

# Upgrades

- `haproxy` has been upgraded to v2.2.14 from v2.2.13

# Acknowledgements

Thanks @46bit for the `forward_only_if_route_service` PR!
Thanks @domdom82 for the `tcp_link_check_port` PR!

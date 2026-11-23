# Dual-Stack (IPv4 + IPv6) Configuration

Use `ha_proxy.bindings` to configure the sockets used by every generated
listener. This includes HTTP, HTTPS, WSS, HTTP health checks, CF TCP routing,
generic TCP frontends, and TCP health checks. The stats listener continues to
use `ha_proxy.stats_bind`.

## Explicit bindings

Each entry has an `address`. Addresses are IP literals, not hostnames, CIDRs,
ports, bracketed IPv6 literals, or zone IDs. Input order is retained in the
generated `bind` directives.

### IPv4 only

```yaml
ha_proxy:
  bindings:
  - address: 0.0.0.0
```

IPv4 is inherently IPv4-only, so it has no `ipv6_mode` option:

```
bind 0.0.0.0:443 ssl crt /var/vcap/jobs/haproxy/config/ssl
```

### IPv6 wildcard

The IPv6 wildcard must explicitly state how it handles IPv4:

```yaml
ha_proxy:
  bindings:
  - address: "::"
    ipv6_mode: v6only
```

This produces an IPv6-only socket:

```
bind [::]:443 v6only ssl crt /var/vcap/jobs/haproxy/config/ssl
```

For a single dual-stack socket, use `v4v6` instead:

```yaml
ha_proxy:
  bindings:
  - address: "::"
    ipv6_mode: v4v6
```

```
bind [::]:443 v4v6 ssl crt /var/vcap/jobs/haproxy/config/ssl
```

Only wildcard `::` accepts `ipv6_mode`, because it can be an IPv4 wildcard as
well. A specific IPv6 address cannot act as an IPv4 wildcard and therefore has
no mode:

```yaml
ha_proxy:
  bindings:
  - address: "fd00::12"
```

### Separate IPv4 and IPv6 sockets

Use an IPv4 wildcard and an IPv6-only wildcard when separate sockets are
required:

```yaml
ha_proxy:
  bindings:
  - address: 0.0.0.0
  - address: "::"
    ipv6_mode: v6only
```

All listener-specific options, including TLS, ALPN, and PROXY protocol, are
rendered on every generated bind directive.

## Validation and compatibility

`bindings` is a non-empty array of maps. Duplicate normalized addresses are
rejected, as are wildcard/specific combinations in the same address family.
An IPv6 wildcard with `ipv6_mode: v4v6` cannot be combined with an IPv4
binding. `bindings` cannot be used with a non-empty legacy `binding_ip` or
with `v4v6: true`; set those legacy values to their defaults (`""` and
`false`) before migrating.

When `bindings` is absent, the existing `binding_ip` and `v4v6` behavior is
unchanged, including its historical `if_p("ha_proxy.v4v6")` handling. Because
`v4v6` has a false default, that legacy presence-based block runs when
`v4v6` is false or omitted. As a result, legacy `binding_ip: "::"` currently
renders `v4v6` regardless of whether `v4v6` is true, false, or omitted. This
compatibility quirk is intentionally preserved. Use `bindings` with
`ipv6_mode: v6only` or `ipv6_mode: v4v6` to explicitly select the IPv6/IPv4
behavior.

## Migrating from `frontend_config`

If `frontend_config` was used to add a second bind directive, replace the
manual configuration with explicit bindings. This avoids duplicating TLS and
other listener options and applies the same sockets to all generated listeners.

Before:

```yaml
ha_proxy:
  binding_ip: 0.0.0.0
  disable_http: true
  frontend_config: |
    bind :::443 ssl crt /var/vcap/jobs/haproxy/config/ssl
```

After:

```yaml
ha_proxy:
  bindings:
  - address: 0.0.0.0
  - address: "::"
    ipv6_mode: v6only
```

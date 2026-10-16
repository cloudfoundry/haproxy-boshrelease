# Dual-Stack (IPv4 + IPv6) Configuration

HAProxy can serve traffic on both IPv4 and IPv6 using two approaches.

## Option A: Single Socket with v4v6

A single IPv6 wildcard socket accepts both IPv4 and IPv6 connections:

```yaml
ha_proxy:
  binding_ip: "::"
  v4v6: true
```

This generates one bind directive per listener:
```
bind :::443 ssl crt /var/vcap/jobs/haproxy/config/ssl v4v6
```

**Note:** `v4v6` only takes effect when `binding_ip` is `::`.

## IPv6-only mode (v6only)

When `binding_ip` is set to `::` without enabling `v4v6`, the `v6only`
option is automatically added to all bind directives:

```yaml
ha_proxy:
  binding_ip: "::"
  # v4v6 not set or false
```

This generates:
```
bind :::443 ssl crt /var/vcap/jobs/haproxy/config/ssl v6only
```

The `v6only` option ensures the IPv6 socket does not accept IPv4
connections, regardless of the kernel's `net.ipv6.bindv6only` sysctl
setting. Without it, behavior depends on the kernel default -- on most
Linux distributions (including standard BOSH stemcells), an IPv6 wildcard
socket silently accepts IPv4 connections as `::ffff:` mapped addresses.

**Breaking change:** Deployments using `binding_ip: "::"` without
`v4v6: true` that relied on the kernel default to accept IPv4 traffic
must now explicitly set `v4v6: true` to restore dual-stack behavior.

## Option B: Separate Sockets with binding_ips

For environments that require distinct IPv4 and IPv6 sockets:

```yaml
ha_proxy:
  binding_ips:
  - 0.0.0.0
  - "::"
```

This generates two bind directives per listener:
```
bind 0.0.0.0:443 ssl crt /var/vcap/jobs/haproxy/config/ssl
bind [::]:443 v6only ssl crt /var/vcap/jobs/haproxy/config/ssl
```

IPv6 addresses automatically receive the `v6only` option to prevent
them from also accepting IPv4 connections.

### Scope

`binding_ips` applies globally to all generated listeners:
HTTP, HTTPS, WSS (port 4443), health checks, CF TCP routing, and
generic TCP frontends.

When `binding_ips` is set, `binding_ip` is ignored for generated
listeners.

### Constraints

- `binding_ips` cannot be combined with `v4v6: true`
- `binding_ips` cannot be combined with a non-empty `binding_ip`
- Entries must be valid IP address literals (no hostnames, CIDRs, or ports)
- Duplicate addresses are rejected
- The list must not be empty when set

### Migrating from frontend_config

If you previously used `frontend_config` to add a second bind line,
you can replace it with `binding_ips` and remove the raw configuration:

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
  binding_ips:
  - 0.0.0.0
  - "::"
```

The `binding_ips` approach is safer because it automatically applies
all TLS, ALPN, mTLS, and PROXY protocol options to every bind directive,
and does not require disabling other frontends.

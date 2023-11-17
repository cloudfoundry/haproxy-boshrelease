# Fixes
No fixes. Version bumps may contain fixes.

# New Features
- Add an option to enable the HAProxy Prometheus Metrics endpoint (https://github.com/cloudfoundry/haproxy-boshrelease/pull/536), thx @benjaminguttmann-avtq
```
  ha_proxy.stats_promex_enable:
     description: "If true, haproxy will enable native prometheus exporter."
     default: false
  ha_proxy.stats_promex_path:
    description: "Define prometheus exporter path."
    default: "/metrics"
```

# Upgrades
- Various bumps for the CI environment that did not impact the resulting boshrelease.
- Minor refactoring to use `host_only` converter, thx @maxmoehl

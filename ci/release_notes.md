# Improvements

- Added the ability to customize what IP blocks are allowed access
  to the internal_only_domains, via the `ha_proxy.trusted_domain_cidrs`
  property.

  **NOTE:** By default, the trusted_domain_cidrs block all traffic
  (secure by default), so depending on your architecture, you may need to
  add this property to your manifest to retain access to those domains. Testing
  this upgrade in a non-production environment first is *highly* recommended.


# Improvements

- `ha_proxy.trusted_domain_cidrs` can now be specified as a base64 encoded blob if desired.

# Fixes

- Resolved an issue where haproxy failed to start when the `ha_proxy.trusted_domain_cidrs` value was too long

# Acknowledgements

Thanks @Soha-Albaghdady for the fix!

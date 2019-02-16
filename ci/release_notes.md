# Fixes

- Adds support for a `dont_track_primary` property for keepalived, to resolve
  a DHCP related issue on OpenStack found in #132
- CI builds + the base manifest for HAProxy now use the latest available copy of BPM on
  the BOSH director

# Acknowledgements

Thanks @rkoster for the fix!

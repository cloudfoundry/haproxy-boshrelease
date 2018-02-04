# Bug Fixes

- `keepalived` now waits on all its children to exit, and tracks the PId of the `checker`
  process.
- Fixed a bug resulting in keepalived configs from being properly generated when specifying
  interfaces explicitly using the `keepalived.interface` property.

# Acknowledgements

Thanks @poblin-orange and @aveyrenc for finding and squashing these bugs!

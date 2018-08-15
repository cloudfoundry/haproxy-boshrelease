# New Features

- Added a new `ha_proxy.raw_config` attribute, to allow users to specify an
  entire haproxy config to be used. This replaces all other haproxy config logic
  in the boshrelease, and should be used with care.
- HAProxy is now compiled with LUA support, which may be useful when providing
  a custom config.

# Acknowledgements

Thanks @teancom for the help!

# Improvements

- Converted HAProxy to start using BPM
- Updated default manifest to use the xenial stemcell
- The default value for the haproxy `keep-alive` timeout is now 6 seconds, to improve compatibility with
  various HTTP clients.
- The `keepalived` job now provides a link including the VIP that keepalived uses
- Added configurable `ha_proxy.max_connections` and `ha_proxy.max_open_files` properties for controlling
  the number of simultaneous HAProxy connections without creating new boshreleases now.
- Fixed an issue with the `ha_proxy.crt_list` property not properly detecting mutual tls settings unless
  the `verify` key was present on every certificate.


# Acknowledgments

Thanks to @rosenhouse, @mathias-ewald, @Fn0rd1, @dueckminor, and @xoebus for the feature requests/bug reports!

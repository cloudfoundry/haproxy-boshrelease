# Improvements

- Converted HAProxy to start using BPM
- Updated default manifest to use the xenial stemcell
- The default value for the haproxy `keep-alive` timeout is now 6 seconds, to improve compatibility with
  various HTTP clients.

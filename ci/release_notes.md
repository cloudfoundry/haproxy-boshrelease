# New Features

- It is now possible to force HAProxy to require SNI from a client
  to match one of HAProxies defined certificates. If enabled, and the
  client does not requets a corresponding host via SNI, the request will
  be rejected, rather than being served HAProxy's default certificate.
  To enable, set the `ha_proxy.strict_sni` property to `true`.

# Acknowledgements

Thanks @b1tamara for the new feature!

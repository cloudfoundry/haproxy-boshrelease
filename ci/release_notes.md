# Link Support

- The `haproxy` job now supports consuming links for backends.
  You can provide it the `http_backend` link, to control the default
  http/https backend. You can also give it an additional `tcp_backend`
  link to add in a tcp-backend that uses links. If your link doesn't
  support providing the `port` property, the job fails back to `ha_proxy.tcp_link_port`
  and `ha_proxy.backend_port`, depending on which link is in play.

# Acknowledgements

Many thanks to @rkoster for bringing link support to `haproxy-boshrelease`!

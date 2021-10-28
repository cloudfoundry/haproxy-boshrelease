# New Features
- `ha_proxy.backend_match_http_protocol` This causes HAProxy to use the same HTTP protocol for backend connections that was used for frontend connections. Note that this property ignores the value of ha_proxy.enable_http2, and requires that ha_proxy.backend_ssl is not off for HTTP2 support

# Acknowledgements

Thanks @peterellisjones, @Rob-rls, @Mrizwanshaik for the PR

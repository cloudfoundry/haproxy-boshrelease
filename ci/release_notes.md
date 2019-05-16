# New Features

- Custom HTTP responses can be configured using `ha_proxy.custom_http_error_files`. It  takes
  a map of status codes to raw http  responses to send. This allows operators to customize things
  like the 502/503 errors returned by HA Proxy.

# Acknowledgements

Many thanks to @rodolf2488 and @barakyo for implementing this!

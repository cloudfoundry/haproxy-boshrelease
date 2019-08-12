# New Features

- Via `backend_prefer_local_az`, haproxy can now be configured to prefer sending traffic
  to backend servers in the same BOSH AZ as the haproxy server, to save cross-az traffic.
  This option is currently off by default, but will likely become on by default in a future
  release.

# Acknowledgments

Thanks @h0nIg for the new feature!

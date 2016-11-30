# New Features

- Thanks to @seongkki, haproxy stats are now viewable
  at `haproxy_ip:9000/haproxy_stats`, provided you specify the
  BOSH properties outlined in https://github.com/seongkki/haproxy-boshrelease/blob/e861c1aed3f8f47e78a2015598fdf5951213ceae/jobs/haproxy/spec#L77-L89

  Access is locked down by default, and credentials are required.

- @joek updated HAProxy to v1.6.10, and added support for resolving backend
  servers via DNS. Should be useful when you're hosting HAProxy in front of
  a cluster using Consul DNS to manage HA.

# Acknowledgements

Thanks @joek + @seongkki for the contributions!

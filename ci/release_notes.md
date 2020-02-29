# Upgrades

- `haproxy` has been upgraded to [v1.9.11](https://www.haproxy.com/blog/haproxy-1-9-has-arrived/) from v1.8.20.
- `pcre2` has been upgraded to [v10.33](https://www.pcre.org/changelog.txt) from v10.31.
- `socat` has been upgraded to [v1.7.3.3](http://www.dest-unreach.org/socat/doc/CHANGES) from v1.7.3.2.

# New Features

- Support for live config reloading was added via a `reload` script. This can be used in use cases
  where config updates need to happen out of band to BOSH, where stopping and restarting processes
  is too disruptive. No changes were made to traditional BOSH process management for HAProxy as a result
  of this change, but the capability is now there for operators or other processes running on HAProxy
  VMs to trigger these reloads.

# Acknowledgements

Thanks @domdom82 for the live reloading support!

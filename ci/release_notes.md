# Fixes
- Fix infinite sleep after reload. Watch for pid instead [PR](https://github.com/cloudfoundry/haproxy-boshrelease/pull/299)
- Remove `nbproc` keyword as it is no longer supported in HAproxy 2.5 [PR](https://github.com/cloudfoundry/haproxy-boshrelease/pull/300)

# New Features
- Replace `grace` keyword with a better solution as `grace` creates problems with reloading HAproxy [PR](https://github.com/cloudfoundry/haproxy-boshrelease/pull/302) (See [docs on grace in 2.5](https://docs.haproxy.org/2.5/configuration.html#grace))
- HAproxy dependencies are now auto-bumped! [PR](https://github.com/cloudfoundry/haproxy-boshrelease/pull/298)

# Upgrades

- `HAproxy` has been upgraded to v2.5.8 from v2.5.7
- `socat` has been upgraded to v1.7.4.3 from v1.7.4.1
- `hatop` has been upgraded to v0.8.2 from v0.8.0
- `lua` has been upgraded to v5.4.4 from v5.4.3


# Acknowledgements

Thanks @peanball and @a18e for the autobumping feature!
Thanks @maxmoehl for removing the `nbproc` keyword!
Thanks @domdom82 for improving the grace period handling!

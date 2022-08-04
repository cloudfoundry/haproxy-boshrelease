# Fixes
- Fix infinite sleep after reload. Watch for pid instead [PR](https://github.com/cloudfoundry/haproxy-boshrelease/pull/299)
- Remove `nbproc` keyword as it is no longer supported in HAproxy 2.5 [PR](https://github.com/cloudfoundry/haproxy-boshrelease/pull/300)

# New Features
- Replace `grace` keyword with a better solution as `grace` creates problems with reloading HAproxy [PR](https://github.com/cloudfoundry/haproxy-boshrelease/pull/302) (See [docs on grace in 2.5](https://docs.haproxy.org/2.5/configuration.html#grace))
- HAproxy dependencies are now auto-bumped! [PR](https://github.com/cloudfoundry/haproxy-boshrelease/pull/298)

# Upgrades

- `HAproxy` has been upgraded from `v2.5.7` to `v2.5.8`
- `socat` has been upgraded from `v1.7.4.1` to `v1.7.4.3`
- `hatop` has been upgraded from `v0.8.0` to `v0.8.2`
- `lua` has been upgraded from `v5.4.3` to `v5.4.4`


# Acknowledgements

Thanks @peanball and @a18e for the autobumping feature!
Thanks @maxmoehl for removing the `nbproc` keyword!
Thanks @domdom82 for improving the grace period handling!

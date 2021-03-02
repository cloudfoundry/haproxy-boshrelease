# Fixes
- Fix soft reload which stopped working with the switch to BPM 1.1.9 and the addition of the [feature](https://github.com/cloudfoundry-incubator/haproxy-boshrelease/commit/9a73a3e2c5d5c4b9386e4537eb7417bc47978b1a) that allowed HAproxy to log to stdout, which requires launching in foreground.

# New Features
- Switch to [master-worker-mode](https://www.haproxy.com/de/blog/haproxy-process-management/) to allow `reload` to work with `nbproc > 1`

# Acknowledgements

Thanks @domdom82 for the PR!

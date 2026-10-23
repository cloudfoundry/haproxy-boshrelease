# `packages/` — the complete release

This directory holds **every** package in the release. `bosh create-release` bundles all of them, so a
plain `bosh create-release` of the committed tree produces the one and only release — there is no
build-time assembly.

- `haproxy-deps` (lua, pcre2, socat, hatop, and the `ttar` helper), `keepalived` — shared, compiled once
- `haproxy-openssl`, `haproxy-openssl-patched`, `haproxy-awslc`, `haproxy-awslc-patched`,
  `haproxy-awslc-fips`, `haproxy-awslc-fips-patched` — the six HAProxy binaries: each SSL
  variant (openssl, awslc, awslc-fips) built with and without the community patches
- `aws-lc-src` (shared source), `aws-lc`, `aws-lc-fips`, `cmake` — crypto build dependencies

The SSL backend is chosen at **deploy time** via the `ha_proxy.ssl_variant` property (default
`openssl`); see `jobs/haproxy/templates/haproxy_wrapper.erb`. Every deploy compiles all bundled
binaries; switching backends later is a property change + redeploy with no recompile.

Dependencies are one-directional: every `haproxy-*` binary depends on `haproxy-deps`; `aws-lc` and
`aws-lc-fips` build from the shared `aws-lc-src` + `cmake`. HAProxy patches for the `-patched`
variants are plain source files under [`../src/haproxy-patches/`](../src/haproxy-patches/), applied at
compile time by `src/apply-patches.sh`.

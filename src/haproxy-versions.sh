#!/usr/bin/env bash
# Version definitions for HAProxy and its bundled dependencies (lua, pcre,
# socat, hatop). Sourced by the haproxy binary/deps packaging scripts.
#
# AWS-LC / cmake / golang versions live in src/aws-lc-versions.sh instead, so
# that bumping anything here does not re-fingerprint the crypto packages and
# trigger an unnecessary AWS-LC recompile. Consumers that need everything (the
# monolithic packages/haproxy/packaging and the CI scripts) source both files.
# Maintained automatically by ci/scripts/autobump-dependencies.py — do not edit by hand.
HAPROXY_VERSION=3.2.26  # https://www.haproxy.org/download/3.2/src/haproxy-3.2.26.tar.gz
LUA_VERSION=5.4.9  # https://www.lua.org/ftp/lua-5.4.9.tar.gz
PCRE_VERSION=10.49  # https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.49/pcre2-10.49.tar.gz
SOCAT_VERSION=1.8.1.3  # http://www.dest-unreach.org/socat/download/socat-1.8.1.3.tar.gz
HATOP_VERSION=0.8.2  # https://github.com/jhunt/hatop/releases/download/v0.8.2/hatop

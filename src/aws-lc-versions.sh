#!/usr/bin/env bash
# Version definitions for the AWS-LC / crypto packages (cmake, aws-lc, aws-lc-fips).
#
# Kept separate from haproxy-versions.sh on purpose: BOSH fingerprints each
# package by the contents of the files it bundles. If these versions lived in
# haproxy-versions.sh (which the crypto packages would then bundle), every
# HAProxy/lua/pcre/socat/hatop bump would change the crypto packages'
# fingerprints and force an unnecessary AWS-LC recompile With this
# split, the aws-lc/cmake fingerprints only change when a crypto version does,
# so the director reuses the cached compiled artifact across HAProxy bumps.
# Maintained automatically by ci/scripts/autobump-dependencies.py — do not edit by hand.
AWS_LC_VERSION=4.0.0  # https://github.com/aws/aws-lc/archive/refs/tags/v4.0.0.tar.gz (LTS line; builds both FIPS and non-FIPS)
CMAKE_VERSION=4.4.3  # https://github.com/Kitware/CMake/releases/download/v4.4.3/cmake-4.4.3-linux-x86_64.tar.gz
GOLANG_VERSION=1.27.3  # https://go.dev/dl/go1.27.3.linux-amd64.tar.gz

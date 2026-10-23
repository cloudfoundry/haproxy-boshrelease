#!/usr/bin/env bash
# Shared HAProxy compile, sourced by every haproxy-<variant> packaging script.
#
# The caller sets SSL_MAKE_FLAGS (the only thing that differs between SSL
# backends) before sourcing this. Bundled HAProxy patches are applied when the
# package ships patch files under haproxy-patches/ — that presence is the ONLY
# thing distinguishing a -patched package from its twin, so the -patched and base
# packaging scripts are identical and this logic lives in one place.
#
# Requires, with the package root as CWD:
#   HAPROXY_VERSION   from haproxy-versions.sh (sourced by the caller)
#   SSL_MAKE_FLAGS    e.g. "USE_OPENSSL=1" or
#                     "USE_OPENSSL_AWSLC=1 SSL_INC=<pkg>/include SSL_LIB=<pkg>/lib"
PKG_ROOT=$(pwd)
DEPS_DIR=/var/vcap/packages/haproxy-deps

mkdir -p ${BOSH_INSTALL_TARGET}/bin

echo "Unpacking HAproxy..."
tar xf haproxy/haproxy-${HAPROXY_VERSION}.tar.gz
pushd haproxy-${HAPROXY_VERSION}
  # -patched packages ship patch files under haproxy-patches/; apply them when present.
  if ls ${PKG_ROOT}/haproxy-patches/*.patch >/dev/null 2>&1; then
    source ${PKG_ROOT}/apply-patches.sh
  fi

  echo "Installing HAproxy..."
  make TARGET=linux-glibc USE_PROMEX=1 ${SSL_MAKE_FLAGS} \
    USE_PCRE2=1 USE_PCRE2_JIT=yes USE_STATIC_PCRE2=1 USE_ZLIB=1 \
    PCRE2DIR=${DEPS_DIR} \
    USE_LUA=1 LUA_LIB=${DEPS_DIR}/lib LUA_INC=${DEPS_DIR}/include
  cp haproxy ${BOSH_INSTALL_TARGET}/bin/
  chmod 755 ${BOSH_INSTALL_TARGET}/bin/haproxy
popd

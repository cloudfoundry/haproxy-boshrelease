# Usage of the functions
# install_<component> "${VERSION}" "$BOSH_INSTALL_TARGET"

function install_hatop {
  local INSTALL_TARGET=$1
  local PACKAGE_VERSION=$2

  echo "Installing hatop ${PACKAGE_VERSION}..."
  cp "haproxy/hatop-${PACKAGE_VERSION}" "${INSTALL_TARGET}/bin/hatop"
  chmod 755 "${INSTALL_TARGET}/bin/hatop"
  cp hatop-wrapper "${INSTALL_TARGET}/"
  chmod 755 "${INSTALL_TARGET}/hatop-wrapper"
}

function install_lua {
  local INSTALL_TARGET=$1
  local PACKAGE_VERSION=$2

  echo "Extracting lua ${PACKAGE_VERSION}..."
  tar xzf "haproxy/lua-${PACKAGE_VERSION}.tar.gz"
  local PACKAGE_DIR="lua-${PACKAGE_VERSION}"
  echo "Building ${PACKAGE_VERSION}..."
  pushd "${PACKAGE_DIR}" || { echo "Error: can't pushd to '${PACKAGE_DIR}'."; return 1; }
    make linux install INSTALL_TOP="${INSTALL_TARGET}"
  popd || { echo "Error: can't popd from '${PACKAGE_DIR}'."; return 1; }
}

function install_pcre2 {
  local INSTALL_TARGET=$1
  local PACKAGE_VERSION=$2

  echo "Extracting pcre2 ${PACKAGE_VERSION}..."
  tar xzf "haproxy/pcre2-${PACKAGE_VERSION}.tar.gz"
  local PACKAGE_DIR="pcre2-${PACKAGE_VERSION}"
  echo "Building ${PACKAGE_VERSION}..."
  pushd "${PACKAGE_DIR}" || { echo "Error: can't pushd to '${PACKAGE_DIR}'."; return 1; }
    ./configure \
      --enable-jit \
      --prefix "${INSTALL_TARGET}"
    make
    make install
  popd || { echo "Error: can't popd from '${PACKAGE_DIR}'."; return 1; }
}

function install_socat {
  local INSTALL_TARGET=$1
  local PACKAGE_VERSION=$2

  echo "Extracting socat ${PACKAGE_VERSION}..."
  tar xzf "haproxy/socat-${PACKAGE_VERSION}.tar.gz"
  local PACKAGE_DIR="socat-${PACKAGE_VERSION}"
  echo "Building ${PACKAGE_VERSION}..."
  pushd "${PACKAGE_DIR}" || { echo "Error: can't pushd to '${PACKAGE_DIR}'."; return 1; }
    ./configure
    make
    cp socat "${INSTALL_TARGET}/bin"
    chmod 755 "${INSTALL_TARGET}/bin/socat"
  popd || { echo "Error: can't popd from '${PACKAGE_DIR}'."; return 1; }
}

function install_haproxy {
  local INSTALL_TARGET=$1
  local PACKAGE_VERSION=$2

  echo "Extracting HAproxy (version ${PACKAGE_VERSION})..."
  tar xf "haproxy/haproxy-${PACKAGE_VERSION}.tar.gz"
  local PACKAGE_DIR="haproxy-${PACKAGE_VERSION}"
  pushd "${PACKAGE_DIR}" || { echo "Error: can't pushd to '${PACKAGE_DIR}'."; return 1; }
    if [ -f ../haproxy/patches.tar.gz ]; then
      echo "Patching ${PACKAGE_VERSION}..."
      mkdir -p "${INSTALL_TARGET}/applied-patches"
      tar xf "../haproxy/patches.tar.gz"
      for patchfile in haproxy-patches/*.patch; do
        echo "Applying patch file ${patchfile}"
        # Conservatively limit patch fuzz factor to 0 to reduce chance of faulty patch
        patch -F 0 -p0 < "${patchfile}"
        # Save patches in install target for inspection later
        cp "${patchfile}" "${INSTALL_TARGET}/applied-patches"
      done
      rm -r haproxy-patches
    fi
    echo "Building ${PACKAGE_VERSION}..."
    local makeArgs=(
      TARGET=linux-glibc
      USE_OPENSSL=1
      USE_PCRE2=1
      USE_PCRE2_JIT=yes
      USE_STATIC_PCRE2=1
      USE_ZLIB=1
      PCRE2DIR="${INSTALL_TARGET}"
      USE_LUA=1
      LUA_LIB="${INSTALL_TARGET}/lib"
      LUA_INC="${INSTALL_TARGET}/include"
    )
    local COMPILATION_FLAGS=""
    if [[ "$PACKAGE_VERSION" == 1.* ]]; then
      COMPILATION_FLAGS="-Wno-deprecated-declarations"
    else
      makeArgs+=( USE_PROMEX=1 )
    fi
    CFLAGS="$COMPILATION_FLAGS" make "${makeArgs[@]}"
    cp haproxy "${INSTALL_TARGET}/bin/"
    chmod 755 "${INSTALL_TARGET}/bin/haproxy"
  popd || { echo "Error: can't popd from '${PACKAGE_DIR}'."; return 1; }
}

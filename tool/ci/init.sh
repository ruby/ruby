#!/bin/bash

if [ "${OPENSSL_VERSION}" != "" ]; then
  OPENSSL_DIR="/opt/openssl/openssl-${OPENSSL_VERSION}"
  export PATH="${OPENSSL_DIR}/bin:${PATH}"
  export CFLAGS="-I${OPENSSL_DIR}/include"
  export LDFLAGS="-L${OPENSSL_DIR}/lib"
  export LD_LIBRARY_PATH="${OPENSSL_DIR}/lib"
  export PKG_CONFIG_PATH="${OPENSSL_DIR}/lib/pkgconfig"
fi

echo "Using GCC ${CC:-default} and OpenSSL ${OPENSSL_VERSION:-default}."

exec $*

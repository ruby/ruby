#!/bin/bash

set -e

if [ ${#} -lt 1 ]; then
  echo "OpenSSL version required." 1>&2
  exit 1
fi

OPENSSL_VERSION="${1}"
OPENSSL_DIR="/opt/openssl/openssl-${OPENSSL_VERSION}"
BUILD_DIR="/build/openssl"

if [ -d "${BUILD_DIR}" ]; then
  rm -rf "${BUILD_DIR}"
fi
mkdir -p "${BUILD_DIR}"
curl -s https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz | \
  tar -C "${BUILD_DIR}" -xzf -
pushd "${BUILD_DIR}/openssl-${OPENSSL_VERSION}"
if [ -d "${OPENSSL_DIR}" ]; then
  rm -rf "${OPENSSL_DIR}"
fi
./Configure \
  --prefix=${OPENSSL_DIR} \
  enable-crypto-mdebug enable-crypto-mdebug-backtrace \
  linux-x86_64
make -s -j$(nproc)
make install_sw
popd

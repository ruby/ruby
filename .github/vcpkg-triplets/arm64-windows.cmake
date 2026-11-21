set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)

# MSVC 14.51 for ARM64 calls __chkstk before saving x30 in some prologues.
# OpenSSL, built with /Gs0, then has tls_parse_all_extensions return into
# itself, and every TLS handshake crashes.
set(VCPKG_PLATFORM_TOOLSET_VERSION 14.44)

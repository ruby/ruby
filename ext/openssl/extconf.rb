# -*- coding: us-ascii -*-
# frozen_string_literal: true
=begin
= Info
  'OpenSSL for Ruby 2' project
  Copyright (C) 2002  Michal Rokos <m.rokos@sh.cvut.cz>
  All rights reserved.

= Licence
  This program is licensed under the same licence as Ruby.
  (See the file 'LICENCE'.)
=end

require "mkmf"

dir_config("openssl")
dir_config("kerberos")

Logging::message "=== OpenSSL for Ruby configurator ===\n"

##
# Adds -DOSSL_DEBUG for compilation and some more targets when GCC is used
# To turn it on, use: --with-debug or --enable-debug
#
if with_config("debug") or enable_config("debug")
  $defs.push("-DOSSL_DEBUG")
end

have_func("rb_io_maybe_wait") # Ruby 3.1

Logging::message "=== Checking for system dependent stuff... ===\n"
have_library("nsl", "t_open")
have_library("socket", "socket")
if $mswin || $mingw
  have_library("ws2_32")
end

if $mingw
  append_cflags '-D_FORTIFY_SOURCE=2'
  append_ldflags '-fstack-protector'
  have_library 'ssp'
end

def find_openssl_library
  if $mswin || $mingw
    # required for static OpenSSL libraries
    have_library("gdi32") # OpenSSL <= 1.0.2 (for RAND_screen())
    have_library("crypt32")
  end

  return false unless have_header("openssl/ssl.h")

  ret = have_library("crypto", "CRYPTO_malloc") &&
    have_library("ssl", "SSL_new")
  return ret if ret

  if $mswin
    # OpenSSL >= 1.1.0: libcrypto.lib and libssl.lib.
    if have_library("libcrypto", "CRYPTO_malloc") &&
        have_library("libssl", "SSL_new")
      return true
    end

    # OpenSSL <= 1.0.2: libeay32.lib and ssleay32.lib.
    if have_library("libeay32", "CRYPTO_malloc") &&
        have_library("ssleay32", "SSL_new")
      return true
    end

    # LibreSSL: libcrypto-##.lib and libssl-##.lib, where ## is the ABI version
    # number. We have to find the version number out by scanning libpath.
    libpath = $LIBPATH.dup
    libpath |= ENV["LIB"].split(File::PATH_SEPARATOR)
    libpath.map! { |d| d.tr(File::ALT_SEPARATOR, File::SEPARATOR) }

    ret = [
      ["crypto", "CRYPTO_malloc"],
      ["ssl", "SSL_new"]
    ].all? do |base, func|
      result = false
      libs = ["lib#{base}-[0-9][0-9]", "lib#{base}-[0-9][0-9][0-9]"]
      libs = Dir.glob(libs.map{|l| libpath.map{|d| File.join(d, l + ".*")}}.flatten).map{|path| File.basename(path, ".*")}.uniq
      libs.each do |lib|
        result = have_library(lib, func)
        break if result
      end
      result
    end
    return ret if ret
  end
  return false
end

Logging::message "=== Checking for required stuff... ===\n"
pkg_config_found = pkg_config("openssl") && have_header("openssl/ssl.h")

if !pkg_config_found && !find_openssl_library
  Logging::message "=== Checking for required stuff failed. ===\n"
  Logging::message "Makefile wasn't created. Fix the errors above.\n"
  raise "OpenSSL library could not be found. You might want to use " \
    "--with-openssl-dir=<dir> option to specify the prefix where OpenSSL " \
    "is installed."
end

version_ok = if have_macro("LIBRESSL_VERSION_NUMBER", "openssl/opensslv.h")
  is_libressl = true
  checking_for("LibreSSL version >= 3.1.0") {
    try_static_assert("LIBRESSL_VERSION_NUMBER >= 0x30100000L", "openssl/opensslv.h") }
else
  checking_for("OpenSSL version >= 1.0.2") {
    try_static_assert("OPENSSL_VERSION_NUMBER >= 0x10002000L", "openssl/opensslv.h") }
end
unless version_ok
  raise "OpenSSL >= 1.0.2 or LibreSSL >= 3.1.0 is required"
end

# Prevent wincrypt.h from being included, which defines conflicting macro with openssl/x509.h
if is_libressl && ($mswin || $mingw)
  $defs.push("-DNOCRYPT")
end

Logging::message "=== Checking for OpenSSL features... ===\n"
# compile options
have_func("RAND_egd")
engines = %w{dynamic 4758cca aep atalla chil
             cswift nuron sureware ubsec padlock capi gmp gost cryptodev}
engines.each { |name|
  have_func("ENGINE_load_#{name}()", "openssl/engine.h")
}

# added in 1.1.0
if !have_struct_member("SSL", "ctx", "openssl/ssl.h") || is_libressl
  $defs.push("-DHAVE_OPAQUE_OPENSSL")
end
have_func("EVP_MD_CTX_new")
have_func("EVP_MD_CTX_free")
have_func("EVP_MD_CTX_pkey_ctx")
have_func("X509_STORE_get_ex_data")
have_func("X509_STORE_set_ex_data")
have_func("X509_STORE_get_ex_new_index")
have_func("X509_CRL_get0_signature")
have_func("X509_REQ_get0_signature")
have_func("X509_REVOKED_get0_serialNumber")
have_func("X509_REVOKED_get0_revocationDate")
have_func("X509_get0_tbs_sigalg")
have_func("X509_STORE_CTX_get0_untrusted")
have_func("X509_STORE_CTX_get0_cert")
have_func("X509_STORE_CTX_get0_chain")
have_func("OCSP_SINGLERESP_get0_id")
have_func("SSL_CTX_get_ciphers")
have_func("X509_up_ref")
have_func("X509_CRL_up_ref")
have_func("X509_STORE_up_ref")
have_func("SSL_SESSION_up_ref")
have_func("EVP_PKEY_up_ref")
have_func("SSL_CTX_set_min_proto_version(NULL, 0)", "openssl/ssl.h")
have_func("SSL_CTX_get_security_level")
have_func("X509_get0_notBefore")
have_func("SSL_SESSION_get_protocol_version")
have_func("TS_STATUS_INFO_get0_status")
have_func("TS_STATUS_INFO_get0_text")
have_func("TS_STATUS_INFO_get0_failure_info")
have_func("TS_VERIFY_CTS_set_certs(NULL, NULL)", "openssl/ts.h")
have_func("TS_VERIFY_CTX_set_store")
have_func("TS_VERIFY_CTX_add_flags")
have_func("TS_RESP_CTX_set_time_cb")
have_func("EVP_PBE_scrypt")
have_func("SSL_CTX_set_post_handshake_auth")

# added in 1.1.1
have_func("EVP_PKEY_check")

# added in 3.0.0
have_func("SSL_set0_tmp_dh_pkey")
have_func("ERR_get_error_all")
have_func("TS_VERIFY_CTX_set_certs(NULL, NULL)", "openssl/ts.h")
have_func("SSL_CTX_load_verify_file")
have_func("BN_check_prime")
have_func("EVP_MD_CTX_get0_md")
have_func("EVP_MD_CTX_get_pkey_ctx")
have_func("EVP_PKEY_eq")
have_func("EVP_PKEY_dup")

Logging::message "=== Checking done. ===\n"

create_header
create_makefile("openssl")
Logging::message "Done.\n"

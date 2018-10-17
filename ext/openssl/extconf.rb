# -*- coding: us-ascii -*-
# frozen_string_literal: false
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
require File.expand_path('../deprecation', __FILE__)

dir_config("openssl")
dir_config("kerberos")

Logging::message "=== OpenSSL for Ruby configurator ===\n"

# Add -Werror=deprecated-declarations to $warnflags if available
OpenSSL.deprecated_warning_flag

##
# Adds -DOSSL_DEBUG for compilation and some more targets when GCC is used
# To turn it on, use: --with-debug or --enable-debug
#
if with_config("debug") or enable_config("debug")
  $defs.push("-DOSSL_DEBUG")
end

Logging::message "=== Checking for system dependent stuff... ===\n"
have_library("nsl", "t_open")
have_library("socket", "socket")
if $mswin || $mingw
  have_library("ws2_32")
end

Logging::message "=== Checking for required stuff... ===\n"
result = pkg_config("openssl") && have_header("openssl/ssl.h")

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

unless result
  unless find_openssl_library
    Logging::message "=== Checking for required stuff failed. ===\n"
    Logging::message "Makefile wasn't created. Fix the errors above.\n"
    exit 1
  end
end

result = checking_for("OpenSSL version is 0.9.8 or later") {
  try_static_assert("OPENSSL_VERSION_NUMBER >= 0x00908000L", "openssl/opensslv.h")
}
unless result
  raise "OpenSSL 0.9.8 or later required."
end

if /darwin/ =~ RUBY_PLATFORM and !OpenSSL.check_func("SSL_library_init()", "openssl/ssl.h")
  raise "Ignore OpenSSL broken by Apple.\nPlease use another openssl. (e.g. using `configure --with-openssl-dir=/path/to/openssl')"
end

Logging::message "=== Checking for OpenSSL features... ===\n"
# compile options

# SSLv2 and SSLv3 may be removed in future versions of OpenSSL, and even macros
# like OPENSSL_NO_SSL2 may not be defined.
have_func("SSLv2_method")
have_func("SSLv3_method")
have_func("TLSv1_1_method")
have_func("TLSv1_2_method")
have_func("RAND_egd")
engines = %w{builtin_engines openbsd_dev_crypto dynamic 4758cca aep atalla chil
             cswift nuron sureware ubsec padlock capi gmp gost cryptodev aesni}
engines.each { |name|
  OpenSSL.check_func_or_macro("ENGINE_load_#{name}", "openssl/engine.h")
}

if ($mswin || $mingw) && have_macro("LIBRESSL_VERSION_NUMBER", "openssl/opensslv.h")
  $defs.push("-DNOCRYPT")
end

# added in 0.9.8X
have_func("EVP_CIPHER_CTX_new")
have_func("EVP_CIPHER_CTX_free")
OpenSSL.check_func_or_macro("SSL_CTX_clear_options", "openssl/ssl.h")

# added in 1.0.0
have_func("ASN1_TIME_adj")
have_func("EVP_CIPHER_CTX_copy")
have_func("EVP_PKEY_base_id")
have_func("HMAC_CTX_copy")
have_func("PKCS5_PBKDF2_HMAC")
have_func("X509_NAME_hash_old")
have_func("X509_STORE_CTX_get0_current_crl")
have_func("X509_STORE_set_verify_cb")
have_func("i2d_ASN1_SET_ANY")
have_func("SSL_SESSION_cmp") # removed
OpenSSL.check_func_or_macro("SSL_set_tlsext_host_name", "openssl/ssl.h")
have_struct_member("CRYPTO_THREADID", "ptr", "openssl/crypto.h")
have_func("EVP_PKEY_get0")

# added in 1.0.1
have_func("SSL_CTX_set_next_proto_select_cb")
have_macro("EVP_CTRL_GCM_GET_TAG", ['openssl/evp.h']) && $defs.push("-DHAVE_AUTHENTICATED_ENCRYPTION")

# added in 1.0.2
have_func("EC_curve_nist2nid")
have_func("X509_REVOKED_dup")
have_func("X509_STORE_CTX_get0_store")
have_func("SSL_CTX_set_alpn_select_cb")
OpenSSL.check_func_or_macro("SSL_CTX_set1_curves_list", "openssl/ssl.h")
OpenSSL.check_func_or_macro("SSL_CTX_set_ecdh_auto", "openssl/ssl.h")
OpenSSL.check_func_or_macro("SSL_get_server_tmp_key", "openssl/ssl.h")
have_func("SSL_is_server")

# added in 1.1.0
if !have_struct_member("SSL", "ctx", "openssl/ssl.h") ||
    try_static_assert("LIBRESSL_VERSION_NUMBER >= 0x2070000fL", "openssl/opensslv.h")
  $defs.push("-DHAVE_OPAQUE_OPENSSL")
end
have_func("CRYPTO_lock") || $defs.push("-DHAVE_OPENSSL_110_THREADING_API")
have_func("BN_GENCB_new")
have_func("BN_GENCB_free")
have_func("BN_GENCB_get_arg")
have_func("EVP_MD_CTX_new")
have_func("EVP_MD_CTX_free")
have_func("HMAC_CTX_new")
have_func("HMAC_CTX_free")
OpenSSL.check_func("RAND_pseudo_bytes", "openssl/rand.h") # deprecated
have_func("X509_STORE_get_ex_data")
have_func("X509_STORE_set_ex_data")
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
OpenSSL.check_func_or_macro("SSL_CTX_set_tmp_ecdh_callback", "openssl/ssl.h") # removed
OpenSSL.check_func_or_macro("SSL_CTX_set_min_proto_version", "openssl/ssl.h")
have_func("SSL_CTX_get_security_level")
have_func("X509_get0_notBefore")
have_func("SSL_SESSION_get_protocol_version")

Logging::message "=== Checking done. ===\n"

create_header
create_makefile("openssl")
Logging::message "Done.\n"

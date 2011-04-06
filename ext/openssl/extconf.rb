=begin
= $RCSfile$ -- Generator for Makefile

= Info
  'OpenSSL for Ruby 2' project
  Copyright (C) 2002  Michal Rokos <m.rokos@sh.cvut.cz>
  All rights reserved.

= Licence
  This program is licenced under the same licence as Ruby.
  (See the file 'LICENCE'.)

= Version
  $Id$
=end

require "mkmf"

dir_config("openssl")
dir_config("kerberos")

message "=== OpenSSL for Ruby configurator ===\n"

##
# Adds -Wall -DOSSL_DEBUG for compilation and some more targets when GCC is used
# To turn it on, use: --with-debug or --enable-debug
#
if with_config("debug") or enable_config("debug")
  $defs.push("-DOSSL_DEBUG") unless $defs.include? "-DOSSL_DEBUG"

  if CONFIG['GCC'] == 'yes'
    $CPPFLAGS += " -Wall" unless $CPPFLAGS.split.include? "-Wall"
  end
end

message "=== Checking for system dependent stuff... ===\n"
have_library("nsl", "t_open")
have_library("socket", "socket")
have_header("assert.h")

message "=== Checking for required stuff... ===\n"
if $mingw
  have_library("wsock32")
  have_library("gdi32")
end

result = pkg_config("openssl") && have_header("openssl/ssl.h")

unless result
  result = have_header("openssl/ssl.h")
  result &&= %w[crypto libeay32].any? {|lib| have_library(lib, "OpenSSL_add_all_digests")}
  result &&= %w[ssl ssleay32].any? {|lib| have_library(lib, "SSL_library_init")}
  unless result
    message "=== Checking for required stuff failed. ===\n"
    message "Makefile wasn't created. Fix the errors above.\n"
    exit 1
  end
end

unless have_header("openssl/conf_api.h")
  message "OpenSSL 0.9.6 or later required.\n"
  exit 1
end

%w"rb_str_set_len rb_block_call".each {|func| have_func(func, "ruby.h")}

message "=== Checking for OpenSSL features... ===\n"
have_func("ERR_peek_last_error")
have_func("BN_mod_add")
have_func("BN_mod_sqr")
have_func("BN_mod_sub")
have_func("BN_pseudo_rand_range")
have_func("BN_rand_range")
have_func("CONF_get1_default_config_file")
have_func("EVP_CIPHER_CTX_copy")
have_func("EVP_CIPHER_CTX_set_padding")
have_func("EVP_CipherFinal_ex")
have_func("EVP_CipherInit_ex")
have_func("EVP_DigestFinal_ex")
have_func("EVP_DigestInit_ex")
have_func("EVP_MD_CTX_cleanup")
have_func("EVP_MD_CTX_create")
have_func("EVP_MD_CTX_destroy")
have_func("EVP_MD_CTX_init")
have_func("HMAC_CTX_cleanup")
have_func("HMAC_CTX_copy")
have_func("HMAC_CTX_init")
have_func("PEM_def_callback")
have_func("PKCS5_PBKDF2_HMAC")
have_func("PKCS5_PBKDF2_HMAC_SHA1")
have_func("X509V3_set_nconf")
have_func("X509V3_EXT_nconf_nid")
have_func("X509_CRL_add0_revoked")
have_func("X509_CRL_set_issuer_name")
have_func("X509_CRL_set_version")
have_func("X509_CRL_sort")
have_func("X509_STORE_get_ex_data")
have_func("X509_STORE_set_ex_data")
have_func("OBJ_NAME_do_all_sorted")
have_func("SSL_SESSION_get_id")
have_func("SSL_SESSION_cmp")
have_func("OPENSSL_cleanse")
have_func("SSLv2_method")
have_func("SSLv2_server_method")
have_func("SSLv2_client_method")
unless have_func("SSL_set_tlsext_host_name", ['openssl/ssl.h'])
  have_macro("SSL_set_tlsext_host_name", ['openssl/ssl.h']) && $defs.push("-DHAVE_SSL_SET_TLSEXT_HOST_NAME")
end
if have_header("openssl/engine.h")
  have_func("ENGINE_add")
  have_func("ENGINE_load_builtin_engines")
  have_func("ENGINE_load_openbsd_dev_crypto")
  have_func("ENGINE_get_digest")
  have_func("ENGINE_get_cipher")
  have_func("ENGINE_cleanup")
  have_func("ENGINE_load_4758cca")
  have_func("ENGINE_load_aep")
  have_func("ENGINE_load_atalla")
  have_func("ENGINE_load_chil")
  have_func("ENGINE_load_cswift")
  have_func("ENGINE_load_nuron")
  have_func("ENGINE_load_sureware")
  have_func("ENGINE_load_ubsec")
end
if checking_for('OpenSSL version is 0.9.7 or later') {
    try_static_assert('OPENSSL_VERSION_NUMBER >= 0x00907000L', 'openssl/opensslv.h')
  }
  have_header("openssl/ocsp.h")
end
have_struct_member("EVP_CIPHER_CTX", "flags", "openssl/evp.h")
have_struct_member("EVP_CIPHER_CTX", "engine", "openssl/evp.h")
have_struct_member("X509_ATTRIBUTE", "single", "openssl/x509.h")

message "=== Checking done. ===\n"

create_header
create_makefile("openssl")
message "Done.\n"

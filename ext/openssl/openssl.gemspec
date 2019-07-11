# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "openssl"
  s.version = "2.1.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.metadata = { "msys2_mingw_dependencies" => "openssl" } if s.respond_to? :metadata=
  s.require_paths = ["lib"]
  s.authors = ["Martin Bosslet", "SHIBATA Hiroshi", "Zachary Scott", "Kazuki Yamaguchi"]
  s.date = "2018-10-17"
  s.description = "It wraps the OpenSSL library."
  s.email = ["ruby-core@ruby-lang.org"]
  s.extensions = ["ext/openssl/extconf.rb"]
  s.extra_rdoc_files = ["README.md", "CONTRIBUTING.md", "History.md"]
  s.files = ["BSDL", "CONTRIBUTING.md", "History.md", "LICENSE.txt", "README.md", "ext/openssl/deprecation.rb", "ext/openssl/extconf.rb", "ext/openssl/openssl_missing.c", "ext/openssl/openssl_missing.h", "ext/openssl/ossl.c", "ext/openssl/ossl.h", "ext/openssl/ossl_asn1.c", "ext/openssl/ossl_asn1.h", "ext/openssl/ossl_bio.c", "ext/openssl/ossl_bio.h", "ext/openssl/ossl_bn.c", "ext/openssl/ossl_bn.h", "ext/openssl/ossl_cipher.c", "ext/openssl/ossl_cipher.h", "ext/openssl/ossl_config.c", "ext/openssl/ossl_config.h", "ext/openssl/ossl_digest.c", "ext/openssl/ossl_digest.h", "ext/openssl/ossl_engine.c", "ext/openssl/ossl_engine.h", "ext/openssl/ossl_hmac.c", "ext/openssl/ossl_hmac.h", "ext/openssl/ossl_kdf.c", "ext/openssl/ossl_kdf.h", "ext/openssl/ossl_ns_spki.c", "ext/openssl/ossl_ns_spki.h", "ext/openssl/ossl_ocsp.c", "ext/openssl/ossl_ocsp.h", "ext/openssl/ossl_pkcs12.c", "ext/openssl/ossl_pkcs12.h", "ext/openssl/ossl_pkcs7.c", "ext/openssl/ossl_pkcs7.h", "ext/openssl/ossl_pkey.c", "ext/openssl/ossl_pkey.h", "ext/openssl/ossl_pkey_dh.c", "ext/openssl/ossl_pkey_dsa.c", "ext/openssl/ossl_pkey_ec.c", "ext/openssl/ossl_pkey_rsa.c", "ext/openssl/ossl_rand.c", "ext/openssl/ossl_rand.h", "ext/openssl/ossl_ssl.c", "ext/openssl/ossl_ssl.h", "ext/openssl/ossl_ssl_session.c", "ext/openssl/ossl_version.h", "ext/openssl/ossl_x509.c", "ext/openssl/ossl_x509.h", "ext/openssl/ossl_x509attr.c", "ext/openssl/ossl_x509cert.c", "ext/openssl/ossl_x509crl.c", "ext/openssl/ossl_x509ext.c", "ext/openssl/ossl_x509name.c", "ext/openssl/ossl_x509req.c", "ext/openssl/ossl_x509revoked.c", "ext/openssl/ossl_x509store.c", "ext/openssl/ruby_missing.h", "lib/openssl.rb", "lib/openssl/bn.rb", "lib/openssl/buffering.rb", "lib/openssl/cipher.rb", "lib/openssl/config.rb", "lib/openssl/digest.rb", "lib/openssl/pkcs5.rb", "lib/openssl/pkey.rb", "lib/openssl/ssl.rb", "lib/openssl/x509.rb"]
  s.homepage = "https://github.com/ruby/openssl"
  s.licenses = ["Ruby"]
  s.rdoc_options = ["--main", "README.md"]
  s.required_ruby_version = Gem::Requirement.new(">= 2.3.0")
  s.rubygems_version = "3.0.0.beta1"
  s.summary = "OpenSSL provides SSL, TLS and general purpose cryptography."

  s.add_runtime_dependency("ipaddr", [">= 0"])
  s.add_development_dependency("rake", [">= 0"])
  s.add_development_dependency("rake-compiler", [">= 0"])
  s.add_development_dependency("test-unit", ["~> 3.0"])
  s.add_development_dependency("rdoc", [">= 0"])
end

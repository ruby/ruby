# -*- encoding: utf-8 -*-
# stub: openssl 2.1.2 ruby lib
# stub: ext/openssl/extconf.rb

Gem::Specification.new do |s|
  s.name = "openssl".freeze
  s.version = "2.1.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "msys2_mingw_dependencies" => "openssl" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Martin Bosslet".freeze, "SHIBATA Hiroshi".freeze, "Zachary Scott".freeze, "Kazuki Yamaguchi".freeze]
  s.date = "2018-10-17"
  s.description = "It wraps the OpenSSL library.".freeze
  s.email = ["ruby-core@ruby-lang.org".freeze]
  s.extensions = ["ext/openssl/extconf.rb".freeze]
  s.extra_rdoc_files = ["README.md".freeze, "CONTRIBUTING.md".freeze, "History.md".freeze]
  s.files = ["BSDL".freeze, "CONTRIBUTING.md".freeze, "History.md".freeze, "LICENSE.txt".freeze, "README.md".freeze, "ext/openssl/deprecation.rb".freeze, "ext/openssl/extconf.rb".freeze, "ext/openssl/openssl_missing.c".freeze, "ext/openssl/openssl_missing.h".freeze, "ext/openssl/ossl.c".freeze, "ext/openssl/ossl.h".freeze, "ext/openssl/ossl_asn1.c".freeze, "ext/openssl/ossl_asn1.h".freeze, "ext/openssl/ossl_bio.c".freeze, "ext/openssl/ossl_bio.h".freeze, "ext/openssl/ossl_bn.c".freeze, "ext/openssl/ossl_bn.h".freeze, "ext/openssl/ossl_cipher.c".freeze, "ext/openssl/ossl_cipher.h".freeze, "ext/openssl/ossl_config.c".freeze, "ext/openssl/ossl_config.h".freeze, "ext/openssl/ossl_digest.c".freeze, "ext/openssl/ossl_digest.h".freeze, "ext/openssl/ossl_engine.c".freeze, "ext/openssl/ossl_engine.h".freeze, "ext/openssl/ossl_hmac.c".freeze, "ext/openssl/ossl_hmac.h".freeze, "ext/openssl/ossl_kdf.c".freeze, "ext/openssl/ossl_kdf.h".freeze, "ext/openssl/ossl_ns_spki.c".freeze, "ext/openssl/ossl_ns_spki.h".freeze, "ext/openssl/ossl_ocsp.c".freeze, "ext/openssl/ossl_ocsp.h".freeze, "ext/openssl/ossl_pkcs12.c".freeze, "ext/openssl/ossl_pkcs12.h".freeze, "ext/openssl/ossl_pkcs7.c".freeze, "ext/openssl/ossl_pkcs7.h".freeze, "ext/openssl/ossl_pkey.c".freeze, "ext/openssl/ossl_pkey.h".freeze, "ext/openssl/ossl_pkey_dh.c".freeze, "ext/openssl/ossl_pkey_dsa.c".freeze, "ext/openssl/ossl_pkey_ec.c".freeze, "ext/openssl/ossl_pkey_rsa.c".freeze, "ext/openssl/ossl_rand.c".freeze, "ext/openssl/ossl_rand.h".freeze, "ext/openssl/ossl_ssl.c".freeze, "ext/openssl/ossl_ssl.h".freeze, "ext/openssl/ossl_ssl_session.c".freeze, "ext/openssl/ossl_version.h".freeze, "ext/openssl/ossl_x509.c".freeze, "ext/openssl/ossl_x509.h".freeze, "ext/openssl/ossl_x509attr.c".freeze, "ext/openssl/ossl_x509cert.c".freeze, "ext/openssl/ossl_x509crl.c".freeze, "ext/openssl/ossl_x509ext.c".freeze, "ext/openssl/ossl_x509name.c".freeze, "ext/openssl/ossl_x509req.c".freeze, "ext/openssl/ossl_x509revoked.c".freeze, "ext/openssl/ossl_x509store.c".freeze, "ext/openssl/ruby_missing.h".freeze, "lib/openssl.rb".freeze, "lib/openssl/bn.rb".freeze, "lib/openssl/buffering.rb".freeze, "lib/openssl/cipher.rb".freeze, "lib/openssl/config.rb".freeze, "lib/openssl/digest.rb".freeze, "lib/openssl/pkcs5.rb".freeze, "lib/openssl/pkey.rb".freeze, "lib/openssl/ssl.rb".freeze, "lib/openssl/x509.rb".freeze]
  s.homepage = "https://github.com/ruby/openssl".freeze
  s.licenses = ["Ruby".freeze]
  s.rdoc_options = ["--main".freeze, "README.md".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.3.0".freeze)
  s.rubygems_version = "3.0.0.beta1".freeze
  s.summary = "OpenSSL provides SSL, TLS and general purpose cryptography.".freeze

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<ipaddr>.freeze, [">= 0"])
      s.add_development_dependency(%q<rake>.freeze, [">= 0"])
      s.add_development_dependency(%q<rake-compiler>.freeze, [">= 0"])
      s.add_development_dependency(%q<test-unit>.freeze, ["~> 3.0"])
      s.add_development_dependency(%q<rdoc>.freeze, [">= 0"])
    else
      s.add_dependency(%q<ipaddr>.freeze, [">= 0"])
      s.add_dependency(%q<rake>.freeze, [">= 0"])
      s.add_dependency(%q<rake-compiler>.freeze, [">= 0"])
      s.add_dependency(%q<test-unit>.freeze, ["~> 3.0"])
      s.add_dependency(%q<rdoc>.freeze, [">= 0"])
    end
  else
    s.add_dependency(%q<ipaddr>.freeze, [">= 0"])
    s.add_dependency(%q<rake>.freeze, [">= 0"])
    s.add_dependency(%q<rake-compiler>.freeze, [">= 0"])
    s.add_dependency(%q<test-unit>.freeze, ["~> 3.0"])
    s.add_dependency(%q<rdoc>.freeze, [">= 0"])
  end
end

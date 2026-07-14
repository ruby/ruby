# frozen_string_literal: true

require_relative "helper"
require "rubygems/security"

unless Gem::HAVE_OPENSSL
  warn "Skipping Gem::Security tests.  openssl not found."
end

if Gem.java_platform?
  warn "Skipping Gem::Security tests on jruby."
end

class TestGemSecurity < Gem::TestCase
  def test_class_create_cert
    name = PUBLIC_CERT.subject
    key = PRIVATE_KEY

    cert = Gem::Security.create_cert name, key, 60, Gem::Security::EXTENSIONS, 5

    assert_kind_of OpenSSL::X509::Certificate, cert

    assert_equal    2,                     cert.version
    assert_equal    5,                     cert.serial
    assert_equal    key.public_key.public_to_pem, cert.public_key.public_to_pem
    assert_in_delta Time.now,              cert.not_before, 10
    assert_in_delta Time.now + 60,         cert.not_after, 10
    assert_equal    name.to_s,             cert.subject.to_s

    assert_equal 3, cert.extensions.length,
                 cert.extensions.map {|e| e.to_a.first }

    constraints = cert.extensions.find {|ext| ext.oid == "basicConstraints" }
    assert_equal "CA:FALSE", constraints.value

    key_usage = cert.extensions.find {|ext| ext.oid == "keyUsage" }
    assert_equal "Digital Signature, Key Encipherment, Data Encipherment",
                 key_usage.value

    key_ident = cert.extensions.find {|ext| ext.oid == "subjectKeyIdentifier" }
    assert_equal 59, key_ident.value.length

    assert_equal "", cert.issuer.to_s
    assert_equal name.to_s, cert.subject.to_s
  end

  def test_class_create_cert_self_signed
    subject = PUBLIC_CERT.subject

    cert = Gem::Security.create_cert_self_signed subject, PRIVATE_KEY, 60

    assert_equal "/CN=nobody/DC=example", cert.issuer.to_s
    assert_equal "sha256WithRSAEncryption", cert.signature_algorithm
  end

  def test_class_create_cert_email
    email = "nobody@example"
    name = PUBLIC_CERT.subject
    key = PRIVATE_KEY

    cert = Gem::Security.create_cert_email email, key, 60

    assert_kind_of OpenSSL::X509::Certificate, cert

    assert_equal    2,                     cert.version
    assert_equal    1,                     cert.serial
    assert_equal    key.public_key.public_to_pem, cert.public_key.public_to_pem
    assert_in_delta Time.now,              cert.not_before, 10
    assert_in_delta Time.now + 60,         cert.not_after, 10
    assert_equal    name.to_s,             cert.subject.to_s
    assert_equal    name.to_s,             cert.issuer.to_s

    assert_equal 5, cert.extensions.length,
                 cert.extensions.map {|e| e.to_a.first }

    constraints = cert.extensions.find {|ext| ext.oid == "subjectAltName" }
    assert_equal "email:nobody@example", constraints.value

    constraints = cert.extensions.find {|ext| ext.oid == "basicConstraints" }
    assert_equal "CA:FALSE", constraints.value

    key_usage = cert.extensions.find {|ext| ext.oid == "keyUsage" }
    assert_equal "Digital Signature, Key Encipherment, Data Encipherment",
                 key_usage.value

    key_ident = cert.extensions.find {|ext| ext.oid == "subjectKeyIdentifier" }
    assert_equal 59, key_ident.value.length
  end

  def test_class_create_key
    key = Gem::Security.create_key "rsa"

    assert_kind_of OpenSSL::PKey::RSA, key
  end

  def test_class_create_key_downcases
    key = Gem::Security.create_key "DSA"

    assert_kind_of OpenSSL::PKey::DSA, key
  end

  def test_class_create_key_ec
    key = Gem::Security.create_key "ec"

    assert_kind_of OpenSSL::PKey::EC, key
  end

  def test_class_create_key_ml_dsa_44
    omit_unless_support_pqc

    key = Gem::Security.create_key "ml-dsa-44"

    assert_kind_of OpenSSL::PKey::PKey, key
    assert_match(/type_name=ML-DSA-44/, key.inspect)
  end

  def test_class_create_key_ml_dsa_65
    omit_unless_support_pqc

    key = Gem::Security.create_key "ml-dsa-65"

    assert_kind_of OpenSSL::PKey::PKey, key
    assert_match(/type_name=ML-DSA-65/, key.inspect)
  end

  def test_class_create_key_ml_dsa_87
    omit_unless_support_pqc

    key = Gem::Security.create_key "ml-dsa-87"

    assert_kind_of OpenSSL::PKey::PKey, key
    assert_match(/type_name=ML-DSA-87/, key.inspect)
  end

  def test_class_create_key_ml_dsa_44_without_ml_dsa_support
    omit_if_support_ml_dsa_key

    e = assert_raise Gem::Security::Exception do
      Gem::Security.create_key "ml-dsa-44"
    end

    assert_match(
      /^ML-DSA-44 key generation failed: ML-DSA-44 requires OpenSSL >= 3\.5/,
      e.message
    )
  end

  def test_class_create_key_ml_dsa_65_without_ml_dsa_support
    omit_if_support_ml_dsa_key

    e = assert_raise Gem::Security::Exception do
      Gem::Security.create_key "ml-dsa-65"
    end

    assert_match(
      /^ML-DSA-65 key generation failed: ML-DSA-65 requires OpenSSL >= 3\.5/,
      e.message
    )
  end

  def test_class_create_key_ml_dsa_87_without_ml_dsa_support
    omit_if_support_ml_dsa_key

    e = assert_raise Gem::Security::Exception do
      Gem::Security.create_key "ml-dsa-87"
    end

    assert_match(
      /^ML-DSA-87 key generation failed: ML-DSA-87 requires OpenSSL >= 3\.5/,
      e.message
    )
  end

  def test_class_create_key_raises_unknown_algorithm
    e = assert_raise Gem::Security::Exception do
      Gem::Security.create_key "NOT_RSA"
    end

    assert_equal "NOT_RSA algorithm not found. RSA, DSA, EC, "\
                 "ML-DSA-44, ML-DSA-65, and ML-DSA-87 "\
                 "algorithms are supported.",
                 e.message
  end

  def test_class_digest_required_rsa
    assert Gem::Security.digest_required?(Gem::Security.create_key("rsa"))
  end

  def test_class_digest_required_dsa
    assert Gem::Security.digest_required?(Gem::Security.create_key("dsa"))
  end

  def test_class_digest_required_ec
    assert Gem::Security.digest_required?(Gem::Security.create_key("ec"))
  end

  def test_class_digest_required_ml_dsa_65
    omit_unless_support_pqc

    refute Gem::Security.digest_required?(Gem::Security.create_key("ml-dsa-65"))
  end

  def test_class_get_public_key_rsa
    pkey_pem = PRIVATE_KEY.public_key.public_to_pem

    assert_equal pkey_pem, Gem::Security.get_public_key(PRIVATE_KEY).public_to_pem
  end

  def test_class_get_public_key_ec
    pkey = Gem::Security.get_public_key(EC_PRIVATE_KEY)

    assert_respond_to pkey, :public_to_pem
  end

  def test_class_get_public_key_ml_dsa_65
    omit_unless_support_pqc

    pkey = Gem::Security.get_public_key(ML_DSA_65_PRIVATE_KEY)

    assert_respond_to pkey, :public_to_pem
  end

  def test_class_email_to_name
    assert_equal "/CN=nobody/DC=example",
                 Gem::Security.email_to_name("nobody@example").to_s

    assert_equal "/CN=nobody/DC=example/DC=com",
                 Gem::Security.email_to_name("nobody@example.com").to_s

    assert_equal "/CN=no.body/DC=example",
                 Gem::Security.email_to_name("no.body@example").to_s

    assert_equal "/CN=no_body/DC=example",
                 Gem::Security.email_to_name("no+body@example").to_s
  end

  def test_class_re_sign
    assert_equal "sha256WithRSAEncryption", EXPIRED_CERT.signature_algorithm
    re_signed = Gem::Security.re_sign EXPIRED_CERT, PRIVATE_KEY, 60

    assert_in_delta Time.now,      re_signed.not_before, 10
    assert_in_delta Time.now + 60, re_signed.not_after,  10
    assert_equal EXPIRED_CERT.serial + 1, re_signed.serial

    assert re_signed.verify PUBLIC_KEY
    assert_equal "sha256WithRSAEncryption", re_signed.signature_algorithm
  end

  def test_class_re_sign_not_self_signed
    e = assert_raise Gem::Security::Exception do
      Gem::Security.re_sign CHILD_CERT, CHILD_KEY
    end

    child_alt_name = CHILD_CERT.extensions.find do |extension|
      extension.oid == "subjectAltName"
    end

    assert_equal "#{child_alt_name.value} is not self-signed, contact " \
                 "#{CHILD_CERT.issuer} to obtain a valid certificate",
                 e.message
  end

  def test_class_re_sign_wrong_key
    e = assert_raise Gem::Security::Exception do
      Gem::Security.re_sign ALTERNATE_CERT, PRIVATE_KEY
    end

    assert_equal "incorrect signing key for re-signing " +
                 ALTERNATE_CERT.subject.to_s,
                 e.message
  end

  def test_class_reset
    trust_dir = Gem::Security.trust_dir

    Gem::Security.reset

    refute_equal trust_dir, Gem::Security.trust_dir
  end

  def test_class_sign
    assert_sign PUBLIC_CERT, PRIVATE_KEY
  end

  def test_class_sign_AltName
    issuer = PUBLIC_CERT.subject
    signee = OpenSSL::X509::Name.parse "/CN=signee/DC=example"

    cert = Gem::Security.create_cert_email "signee@example", PRIVATE_KEY

    signed = Gem::Security.sign cert, PRIVATE_KEY, PUBLIC_CERT, 60

    assert_equal    PUBLIC_KEY.public_to_pem, signed.public_key.public_to_pem
    assert_equal    signee.to_s,       signed.subject.to_s
    assert_equal    issuer.to_s,       signed.issuer.to_s

    assert_in_delta Time.now,          signed.not_before, 10
    assert_in_delta Time.now + 60,     signed.not_after, 10

    assert_equal "sha256WithRSAEncryption", signed.signature_algorithm

    assert_equal 5, signed.extensions.length,
                 signed.extensions.map {|e| e.to_a.first }

    constraints = signed.extensions.find {|ext| ext.oid == "issuerAltName" }
    assert_equal "email:nobody@example", constraints.value, "issuerAltName"

    constraints = signed.extensions.find {|ext| ext.oid == "subjectAltName" }
    assert_equal "email:signee@example", constraints.value, "subjectAltName"

    constraints = signed.extensions.find {|ext| ext.oid == "basicConstraints" }
    assert_equal "CA:FALSE", constraints.value

    key_usage = signed.extensions.find {|ext| ext.oid == "keyUsage" }
    assert_equal "Digital Signature, Key Encipherment, Data Encipherment",
                 key_usage.value

    key_ident =
      signed.extensions.find {|ext| ext.oid == "subjectKeyIdentifier" }
    assert_equal 59, key_ident.value.length

    assert signed.verify PUBLIC_KEY
  end

  def test_class_sign_ml_dsa_65
    omit_unless_support_pqc

    assert_sign ML_DSA_65_PUBLIC_CERT, ML_DSA_65_PRIVATE_KEY
  end

  def test_class_trust_dir
    trust_dir = Gem::Security.trust_dir

    expected = File.join Gem.user_home, ".gem/trust"

    assert_equal expected, trust_dir.dir
  end

  def test_class_write_private_key
    key = Gem::Security.create_key "rsa"

    path = File.join @tempdir, "test-private_key.pem"

    Gem::Security.write_private_key key, path

    assert_path_exist path

    key_from_file = File.read path

    assert_equal key.private_to_pem, key_from_file
  end

  def test_class_write_private_key_ml_dsa_65
    omit_unless_support_pqc

    key = Gem::Security.create_key "ml-dsa-65"

    path = File.join @tempdir, "test-ml-dsa-private_key.pem"

    Gem::Security.write_private_key key, path

    assert_path_exist path

    key_from_file = File.read path

    assert_equal key.private_to_pem, key_from_file
  end

  def test_class_write_private_key_encrypted
    key = Gem::Security.create_key "rsa"

    path = File.join @tempdir, "test-private_encrypted_key.pem"

    passphrase = "It should be long."

    Gem::Security.write_private_key key, path, 0o600, passphrase

    assert_path_exist path

    key_from_file = OpenSSL::PKey::RSA.new File.read(path), passphrase

    assert_equal key.private_to_pem, key_from_file.private_to_pem
  end

  def test_class_write_private_key_encrypted_ml_dsa_65
    omit_unless_support_pqc

    key = Gem::Security.create_key "ml-dsa-65"

    path = File.join @tempdir, "test-ml-dsa-private_encrypted_key.pem"

    passphrase = "It should be long."

    Gem::Security.write_private_key key, path, 0o600, passphrase

    assert_path_exist path

    key_from_file = OpenSSL::PKey.read File.read(path), passphrase

    assert_equal key.private_to_pem, key_from_file.private_to_pem
  end

  def test_class_write_private_key_encrypted_cipher
    key = Gem::Security.create_key "rsa"

    path = File.join @tempdir, "test-private_encrypted__with_non_default_cipher_key.pem"

    passphrase = "It should be long."

    cipher = OpenSSL::Cipher.new "AES-192-CBC"

    Gem::Security.write_private_key key, path, 0o600, passphrase, cipher

    assert_path_exist path

    # Gem::Security.write_private_key outputs PKCS #8 format which doesn't have
    # DEK-Info header to assert cipher name unlike PKCS #1 RSAPrivateKey.
    # We cannot assert the cipher name in the PEM text.
    key_from_file = OpenSSL::PKey.read File.read(path), passphrase

    assert_equal key.private_to_pem, key_from_file.private_to_pem
  end

  def test_class_write_private_key_encrypted_cipher_ml_dsa_65
    omit_unless_support_pqc

    key = Gem::Security.create_key "ml-dsa-65"

    path = File.join @tempdir,
      "test-ml-dsa-private_encrypted_with_non_default_cipher_key.pem"

    passphrase = "It should be long."

    cipher = OpenSSL::Cipher.new "AES-192-CBC"

    Gem::Security.write_private_key key, path, 0o600, passphrase, cipher

    assert_path_exist path

    # Unlike RSA's traditional PEM format where the cipher name appears in a
    # plaintext DEK-Info header, ML-DSA uses private_to_pem which outputs PKCS#8
    # format where there is no header, and the cipher name doesn't appear as a
    # text. So we cannot assert the cipher name in the PEM text.
    key_from_file = OpenSSL::PKey.read File.read(path), passphrase

    assert_equal key.private_to_pem, key_from_file.private_to_pem
  end

  def test_class_write_certificate
    path = File.join @tempdir, "test-public_cert.pem"

    Gem::Security.write_certificate PUBLIC_CERT, path

    assert_path_exist path

    cert_from_file = File.read path

    assert_equal PUBLIC_CERT.to_pem, cert_from_file
  end

  private

  def assert_sign(signing_cert, signing_key)
    issuer = signing_cert.subject
    signee = OpenSSL::X509::Name.new([["CN", "signee"], ["DC", "example"]])

    key  = signing_key
    cert = OpenSSL::X509::Certificate.new
    cert.subject = signee
    public_key = Gem::Security.get_public_key(key)
    cert.public_key = public_key

    signed = Gem::Security.sign cert, key, signing_cert, 60
    signed_public_key = Gem::Security.get_public_key(signed)

    assert_equal    public_key.public_to_pem, signed_public_key.public_to_pem
    assert_equal    signee.to_s,           signed.subject.to_s
    assert_equal    issuer.to_s,           signed.issuer.to_s

    assert_in_delta Time.now,              signed.not_before, 10
    assert_in_delta Time.now + 60,         signed.not_after, 10

    assert_equal 4, signed.extensions.length,
                 signed.extensions.map {|e| e.to_a.first }

    constraints = signed.extensions.find {|ext| ext.oid == "issuerAltName" }
    assert_equal "email:nobody@example", constraints.value, "issuerAltName"

    constraints = signed.extensions.find {|ext| ext.oid == "basicConstraints" }
    assert_equal "CA:FALSE", constraints.value

    key_usage = signed.extensions.find {|ext| ext.oid == "keyUsage" }
    assert_equal "Digital Signature, Key Encipherment, Data Encipherment",
                 key_usage.value

    key_ident =
      signed.extensions.find {|ext| ext.oid == "subjectKeyIdentifier" }
    assert_equal 59, key_ident.value.length

    assert signed.verify key
  end
end if Gem::HAVE_OPENSSL && !Gem.java_platform?

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
  CHILD_KEY = load_key "child"
  EC_KEY = load_key "private_ec", "Foo bar"

  ALTERNATE_CERT = load_cert "child"
  CHILD_CERT     = load_cert "child"
  EXPIRED_CERT   = load_cert "expired"

  def setup
    super

    @SEC = Gem::Security
  end

  def test_class_create_cert
    name = PUBLIC_CERT.subject
    key = PRIVATE_KEY

    cert = @SEC.create_cert name, key, 60, Gem::Security::EXTENSIONS, 5

    assert_kind_of OpenSSL::X509::Certificate, cert

    assert_equal    2,                     cert.version
    assert_equal    5,                     cert.serial
    assert_equal    key.public_key.to_pem, cert.public_key.to_pem
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
    assert_equal "B1:1A:54:09:67:45:60:02:02:D7:CE:F4:1D:60:4A:89:DF:E7:58:D9",
                 key_ident.value

    assert_equal "", cert.issuer.to_s
    assert_equal name.to_s, cert.subject.to_s
  end

  def test_class_create_cert_self_signed
    subject = PUBLIC_CERT.subject

    cert = @SEC.create_cert_self_signed subject, PRIVATE_KEY, 60

    assert_equal "/CN=nobody/DC=example", cert.issuer.to_s
    assert_equal "sha256WithRSAEncryption", cert.signature_algorithm
  end

  def test_class_create_cert_email
    email = "nobody@example"
    name = PUBLIC_CERT.subject
    key = PRIVATE_KEY

    cert = @SEC.create_cert_email email, key, 60

    assert_kind_of OpenSSL::X509::Certificate, cert

    assert_equal    2,                     cert.version
    assert_equal    1,                     cert.serial
    assert_equal    key.public_key.to_pem, cert.public_key.to_pem
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
    assert_equal "B1:1A:54:09:67:45:60:02:02:D7:CE:F4:1D:60:4A:89:DF:E7:58:D9",
                 key_ident.value
  end

  def test_class_create_key
    key = @SEC.create_key "rsa"

    assert_kind_of OpenSSL::PKey::RSA, key
  end

  def test_class_create_key_downcases
    key = @SEC.create_key "DSA"

    assert_kind_of OpenSSL::PKey::DSA, key
  end

  def test_class_create_key_raises_unknown_algorithm
    e = assert_raise Gem::Security::Exception do
      @SEC.create_key "NOT_RSA"
    end

    assert_equal "NOT_RSA algorithm not found. RSA, DSA, and EC algorithms are supported.",
                 e.message
  end

  def test_class_get_public_key_rsa
    pkey_pem = PRIVATE_KEY.public_key.to_pem

    assert_equal pkey_pem, @SEC.get_public_key(PRIVATE_KEY).to_pem
  end

  def test_class_get_public_key_ec
    pkey = @SEC.get_public_key(EC_KEY)

    assert_respond_to pkey, :to_pem
  end

  def test_class_email_to_name
    assert_equal "/CN=nobody/DC=example",
                 @SEC.email_to_name("nobody@example").to_s

    assert_equal "/CN=nobody/DC=example/DC=com",
                 @SEC.email_to_name("nobody@example.com").to_s

    assert_equal "/CN=no.body/DC=example",
                 @SEC.email_to_name("no.body@example").to_s

    assert_equal "/CN=no_body/DC=example",
                 @SEC.email_to_name("no+body@example").to_s
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

    assert_equal "#{child_alt_name.value} is not self-signed, contact " +
                 "#{ALTERNATE_CERT.issuer} to obtain a valid certificate",
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
    trust_dir = @SEC.trust_dir

    @SEC.reset

    refute_equal trust_dir, @SEC.trust_dir
  end

  def test_class_sign
    issuer = PUBLIC_CERT.subject
    signee = OpenSSL::X509::Name.new([["CN", "signee"], ["DC", "example"]])

    key  = PRIVATE_KEY
    cert = OpenSSL::X509::Certificate.new
    cert.subject = signee

    cert.subject    = signee
    cert.public_key = key.public_key

    signed = @SEC.sign cert, key, PUBLIC_CERT, 60

    assert_equal    key.public_key.to_pem, signed.public_key.to_pem
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
    assert_equal "B1:1A:54:09:67:45:60:02:02:D7:CE:F4:1D:60:4A:89:DF:E7:58:D9",
                 key_ident.value

    assert signed.verify key
  end

  def test_class_sign_AltName
    issuer = PUBLIC_CERT.subject
    signee = OpenSSL::X509::Name.parse "/CN=signee/DC=example"

    cert = @SEC.create_cert_email "signee@example", PRIVATE_KEY

    signed = @SEC.sign cert, PRIVATE_KEY, PUBLIC_CERT, 60

    assert_equal    PUBLIC_KEY.to_pem, signed.public_key.to_pem
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
    assert_equal "B1:1A:54:09:67:45:60:02:02:D7:CE:F4:1D:60:4A:89:DF:E7:58:D9",
                 key_ident.value

    assert signed.verify PUBLIC_KEY
  end

  def test_class_trust_dir
    trust_dir = @SEC.trust_dir

    expected = File.join Gem.user_home, ".gem/trust"

    assert_equal expected, trust_dir.dir
  end

  def test_class_write
    key = @SEC.create_key "rsa"

    path = File.join @tempdir, "test-private_key.pem"

    @SEC.write key, path

    assert_path_exist path

    key_from_file = File.read path

    assert_equal key.to_pem, key_from_file
  end

  def test_class_write_encrypted
    key = @SEC.create_key "rsa"

    path = File.join @tempdir, "test-private_encrypted_key.pem"

    passphrase = "It should be long."

    @SEC.write key, path, 0600, passphrase

    assert_path_exist path

    key_from_file = OpenSSL::PKey::RSA.new File.read(path), passphrase

    assert_equal key.to_pem, key_from_file.to_pem
  end

  def test_class_write_encrypted_cipher
    key = @SEC.create_key "rsa"

    path = File.join @tempdir, "test-private_encrypted__with_non_default_cipher_key.pem"

    passphrase = "It should be long."

    cipher = OpenSSL::Cipher.new "AES-192-CBC"

    @SEC.write key, path, 0600, passphrase, cipher

    assert_path_exist path

    key_file_contents = File.read(path)

    assert key_file_contents.split("\n")[2].match(cipher.name)

    key_from_file = OpenSSL::PKey::RSA.new key_file_contents, passphrase

    assert_equal key.to_pem, key_from_file.to_pem
  end
end if Gem::HAVE_OPENSSL && !Gem.java_platform?

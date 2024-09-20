require_relative '../../../../spec_helper'
require 'openssl'

describe "OpenSSL::X509::Store#verify" do
  it "returns true for valid certificate" do
    key = OpenSSL::PKey::RSA.new 2048
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse "/DC=org/DC=truffleruby/CN=TruffleRuby CA"
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 10
    cert.not_after = cert.not_before + 365 * 24 * 60 * 60
    cert.sign key, OpenSSL::Digest.new('SHA256')
    store = OpenSSL::X509::Store.new
    store.add_cert(cert)
    [store.verify(cert), store.error, store.error_string].should == [true, 0, "ok"]
  end

  it "returns false for an expired certificate" do
    key = OpenSSL::PKey::RSA.new 2048
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse "/DC=org/DC=truffleruby/CN=TruffleRuby CA"
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 10
    cert.not_after = Time.now - 5
    cert.sign key, OpenSSL::Digest.new('SHA256')
    store = OpenSSL::X509::Store.new
    store.add_cert(cert)
    store.verify(cert).should == false
  end

  it "returns false for an expired root certificate" do
    root_key = OpenSSL::PKey::RSA.new 2048
    root_cert = OpenSSL::X509::Certificate.new
    root_cert.version = 2
    root_cert.serial = 1
    root_cert.subject = OpenSSL::X509::Name.parse "/DC=org/DC=truffleruby/CN=TruffleRuby CA"
    root_cert.issuer = root_cert.subject
    root_cert.public_key = root_key.public_key
    root_cert.not_before = Time.now - 10
    root_cert.not_after = Time.now - 5
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = root_cert
    ef.issuer_certificate = root_cert
    root_cert.add_extension(ef.create_extension("basicConstraints","CA:TRUE",true))
    root_cert.add_extension(ef.create_extension("keyUsage","keyCertSign, cRLSign", true))
    root_cert.add_extension(ef.create_extension("subjectKeyIdentifier","hash",false))
    root_cert.add_extension(ef.create_extension("authorityKeyIdentifier","keyid:always",false))
    root_cert.sign(root_key, OpenSSL::Digest.new('SHA256'))


    key = OpenSSL::PKey::RSA.new 2048
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 2
    cert.subject = OpenSSL::X509::Name.parse "/DC=org/DC=truffleruby/CN=TruffleRuby certificate"
    cert.issuer = root_cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now
    cert.not_after = cert.not_before + 1 * 365 * 24 * 60 * 60
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = root_cert
    cert.add_extension(ef.create_extension("keyUsage","digitalSignature", true))
    cert.add_extension(ef.create_extension("subjectKeyIdentifier","hash",false))
    cert.sign(root_key, OpenSSL::Digest.new('SHA256'))

    store = OpenSSL::X509::Store.new
    store.add_cert(root_cert)
    store.add_cert(cert)
    store.verify(cert).should == false
  end
end

#!/usr/bin/env ruby

require 'openssl'
require 'ca_config'

include OpenSSL

$stdout.sync = true

cn = ARGV.shift || 'CA'

unless FileTest.exist?('private')
  Dir.mkdir('private', 0700)
end
unless FileTest.exist?('newcerts')
  Dir.mkdir('newcerts')
end
unless FileTest.exist?('crl')
  Dir.mkdir('crl')
end
unless FileTest.exist?('serial')
  File.open('serial', 'w') do |f|
    f << '2'
  end
end

print "Generating CA keypair: "
keypair = PKey::RSA.new(CAConfig::CA_RSA_KEY_LENGTH) { putc "." }
putc "\n"

now = Time.now
cert = X509::Certificate.new
name = CAConfig::NAME.dup << ['CN', cn]
cert.subject = cert.issuer = X509::Name.new(name)
cert.not_before = now
cert.not_after = now + CAConfig::CA_CERT_DAYS * 24 * 60 * 60
cert.public_key = keypair.public_key
cert.serial = 0x1
cert.version = 2 # X509v3

key_usage = ["cRLSign", "keyCertSign"]
ef = X509::ExtensionFactory.new
ef.subject_certificate = cert
ef.issuer_certificate = cert # we needed subjectKeyInfo inside, now we have it
ext1 = ef.create_extension("basicConstraints","CA:TRUE", true)
ext2 = ef.create_extension("nsComment","Ruby/OpenSSL Generated Certificate")
ext3 = ef.create_extension("subjectKeyIdentifier", "hash")
ext4 = ef.create_extension("keyUsage", key_usage.join(","), true)
cert.extensions = [ext1, ext2, ext3, ext4]
ext0 = ef.create_extension("authorityKeyIdentifier", "keyid:always,issuer:always")
cert.add_extension(ext0)
cert.sign(keypair, OpenSSL::Digest::SHA1.new)

keypair_file = CAConfig::KEYPAIR_FILE
puts "Writing keypair."
File.open(keypair_file, "w", 0400) do |f|
  f << keypair.export(Cipher::DES.new(:EDE3, :CBC), &CAConfig::PASSWD_CB)
end

cert_file = CAConfig::CERT_FILE
puts "Writing #{cert_file}."
File.open(cert_file, "w", 0644) do |f|
  f << cert.to_pem
end

puts "DONE. (Generated certificate for '#{cert.subject}')"

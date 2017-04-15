#!/usr/bin/env ruby

require 'openssl'
require 'ca_config'
require 'fileutils'
require 'getopts'

include OpenSSL

def usage
  myname = File::basename($0)
  $stderr.puts "Usage: #{myname} [--type (client|server|ca|ocsp)] [--out certfile] csr_file"
  exit
end

getopts nil, 'type:client', 'out:', 'force'

cert_type = $OPT_type
out_file = $OPT_out || 'cert.pem'
csr_file = ARGV.shift or usage
ARGV.empty? or usage

csr = X509::Request.new(File.open(csr_file).read)
unless csr.verify(csr.public_key)
  raise "CSR sign verification failed."
end
p csr.public_key
if csr.public_key.n.num_bits < CAConfig::CERT_KEY_LENGTH_MIN
  raise "Key length too short"
end
if csr.public_key.n.num_bits > CAConfig::CERT_KEY_LENGTH_MAX
  raise "Key length too long"
end
if csr.subject.to_a[0, CAConfig::NAME.size] != CAConfig::NAME
  unless $OPT_force
    p csr.subject.to_a
    p CAConfig::NAME
    raise "DN does not match"
  end
end

# Only checks signature here.  You must verify CSR according to your CP/CPS.

$stdout.sync = true

# CA setup

ca_file = CAConfig::CERT_FILE
puts "Reading CA cert (from #{ca_file})"
ca = X509::Certificate.new(File.read(ca_file))

ca_keypair_file = CAConfig::KEYPAIR_FILE
puts "Reading CA keypair (from #{ca_keypair_file})"
ca_keypair = PKey::RSA.new(File.read(ca_keypair_file), &CAConfig::PASSWD_CB)

serial = File.open(CAConfig::SERIAL_FILE, "r").read.chomp.hex
File.open(CAConfig::SERIAL_FILE, "w") do |f|
  f << sprintf("%04X", serial + 1)
end

# Generate new cert

cert = X509::Certificate.new
from = Time.now # + 30 * 60	# Wait 30 minutes.
cert.subject = csr.subject
cert.issuer = ca.subject
cert.not_before = from
cert.not_after = from + CAConfig::CERT_DAYS * 24 * 60 * 60
cert.public_key = csr.public_key
cert.serial = serial
cert.version = 2 # X509v3

basic_constraint = nil
key_usage = []
ext_key_usage = []
case cert_type
when "ca"
  basic_constraint = "CA:TRUE"
  key_usage << "cRLSign" << "keyCertSign"
when "terminalsubca"
  basic_constraint = "CA:TRUE,pathlen:0"
  key_usage << "cRLSign" << "keyCertSign"
when "server"
  basic_constraint = "CA:FALSE"
  key_usage << "digitalSignature" << "keyEncipherment"
  ext_key_usage << "serverAuth"
when "ocsp"
  basic_constraint = "CA:FALSE"
  key_usage << "nonRepudiation" << "digitalSignature"
  ext_key_usage << "serverAuth" << "OCSPSigning"
when "client"
  basic_constraint = "CA:FALSE"
  key_usage << "nonRepudiation" << "digitalSignature" << "keyEncipherment"
  ext_key_usage << "clientAuth" << "emailProtection"
else
  raise "unknonw cert type \"#{cert_type}\" is specified."
end

ef = X509::ExtensionFactory.new
ef.subject_certificate = cert
ef.issuer_certificate = ca
ex = []
ex << ef.create_extension("basicConstraints", basic_constraint, true)
ex << ef.create_extension("nsComment","Ruby/OpenSSL Generated Certificate")
ex << ef.create_extension("subjectKeyIdentifier", "hash")
#ex << ef.create_extension("nsCertType", "client,email")
ex << ef.create_extension("keyUsage", key_usage.join(",")) unless key_usage.empty?
#ex << ef.create_extension("authorityKeyIdentifier", "keyid:always,issuer:always")
#ex << ef.create_extension("authorityKeyIdentifier", "keyid:always")
ex << ef.create_extension("extendedKeyUsage", ext_key_usage.join(",")) unless ext_key_usage.empty?

ex << ef.create_extension("crlDistributionPoints", CAConfig::CDP_LOCATION) if CAConfig::CDP_LOCATION
ex << ef.create_extension("authorityInfoAccess", "OCSP;" << CAConfig::OCSP_LOCATION) if CAConfig::OCSP_LOCATION
cert.extensions = ex
cert.sign(ca_keypair, OpenSSL::Digest::SHA1.new)

# For backup

cert_file = CAConfig::NEW_CERTS_DIR + "/#{cert.serial}_cert.pem"
File.open(cert_file, "w", 0644) do |f|
  f << cert.to_pem
end

puts "Writing cert.pem..."
FileUtils.copy(cert_file, out_file)

puts "DONE. (Generated certificate for '#{cert.subject}')"

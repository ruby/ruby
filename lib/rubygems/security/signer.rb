# frozen_string_literal: true
##
# Basic OpenSSL-based package signing class.

class Gem::Security::Signer

  ##
  # The chain of certificates for signing including the signing certificate

  attr_accessor :cert_chain

  ##
  # The private key for the signing certificate

  attr_accessor :key

  ##
  # The digest algorithm used to create the signature

  attr_reader :digest_algorithm

  ##
  # The name of the digest algorithm, used to pull digests out of the hash by
  # name.

  attr_reader :digest_name # :nodoc:

  ##
  # Creates a new signer with an RSA +key+ or path to a key, and a certificate
  # +chain+ containing X509 certificates, encoding certificates or paths to
  # certificates.

  def initialize key, cert_chain, passphrase = nil
    @cert_chain = cert_chain
    @key        = key

    unless @key then
      default_key  = File.join Gem.default_key_path
      @key = default_key if File.exist? default_key
    end

    unless @cert_chain then
      default_cert = File.join Gem.default_cert_path
      @cert_chain = [default_cert] if File.exist? default_cert
    end

    @digest_algorithm = Gem::Security::DIGEST_ALGORITHM
    @digest_name      = Gem::Security::DIGEST_NAME

    @key = OpenSSL::PKey::RSA.new File.read(@key), passphrase if
      @key and not OpenSSL::PKey::RSA === @key

    if @cert_chain then
      @cert_chain = @cert_chain.compact.map do |cert|
        next cert if OpenSSL::X509::Certificate === cert

        cert = File.read cert if File.exist? cert

        OpenSSL::X509::Certificate.new cert
      end

      load_cert_chain
    end
  end

  ##
  # Extracts the full name of +cert+.  If the certificate has a subjectAltName
  # this value is preferred, otherwise the subject is used.

  def extract_name cert # :nodoc:
    subject_alt_name = cert.extensions.find { |e| 'subjectAltName' == e.oid }

    if subject_alt_name then
      /\Aemail:/ =~ subject_alt_name.value

      $' || subject_alt_name.value
    else
      cert.subject
    end
  end

  ##
  # Loads any missing issuers in the cert chain from the trusted certificates.
  #
  # If the issuer does not exist it is ignored as it will be checked later.

  def load_cert_chain # :nodoc:
    return if @cert_chain.empty?

    while @cert_chain.first.issuer.to_s != @cert_chain.first.subject.to_s do
      issuer = Gem::Security.trust_dir.issuer_of @cert_chain.first

      break unless issuer # cert chain is verified later

      @cert_chain.unshift issuer
    end
  end

  ##
  # Sign data with given digest algorithm

  def sign data
    return unless @key

    if @cert_chain.length == 1 and @cert_chain.last.not_after < Time.now then
      re_sign_key
    end

    full_name = extract_name @cert_chain.last

    Gem::Security::SigningPolicy.verify @cert_chain, @key, {}, {}, full_name

    @key.sign @digest_algorithm.new, data
  end

  ##
  # Attempts to re-sign the private key if the signing certificate is expired.
  #
  # The key will be re-signed if:
  # * The expired certificate is self-signed
  # * The expired certificate is saved at ~/.gem/gem-public_cert.pem
  # * There is no file matching the expiry date at
  #   ~/.gem/gem-public_cert.pem.expired.%Y%m%d%H%M%S
  #
  # If the signing certificate can be re-signed the expired certificate will
  # be saved as ~/.gem/gem-public_cert.pem.expired.%Y%m%d%H%M%S where the
  # expiry time (not after) is used for the timestamp.

  def re_sign_key # :nodoc:
    old_cert = @cert_chain.last

    disk_cert_path = File.join Gem.default_cert_path
    disk_cert = File.read disk_cert_path rescue nil
    disk_key  =
      File.read File.join(Gem.default_key_path) rescue nil

    if disk_key == @key.to_pem and disk_cert == old_cert.to_pem then
      expiry = old_cert.not_after.strftime '%Y%m%d%H%M%S'
      old_cert_file = "gem-public_cert.pem.expired.#{expiry}"
      old_cert_path = File.join Gem.user_home, ".gem", old_cert_file

      unless File.exist? old_cert_path then
        Gem::Security.write old_cert, old_cert_path

        cert = Gem::Security.re_sign old_cert, @key

        Gem::Security.write cert, disk_cert_path

        @cert_chain = [cert]
      end
    end
  end

end


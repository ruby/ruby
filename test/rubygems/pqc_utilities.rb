# frozen_string_literal: true

# This file can be loaded by RubyGems test-unit files and Bundler rspec files.
# Don't add test-unit or rspec dependent logic in this file.

require "socket"
require "openssl"

module Gem::PQCUtilities
  CERTS_DIR = __dir__

  # PQC algorithms ML-KEM and ML-DSA require OpenSSL >= 3.5.
  # https://openssl-library.org/post/2025-04-08-openssl-35-final-release/
  # Ruby OpenSSL >= 4.0 has useful methods in PQC use cases.
  # https://github.com/ruby/openssl/blob/v4.0.0/History.md?plain=1#L25-L35
  # And fixed the following bug related to PQC.
  # https://github.com/ruby/openssl/pull/898
  # However, we don't check OpenSSL and Ruby OpenSSL versions here
  # for a flexible check for other SSL libraries such as LibreSSL and AWS-LC.
  def without_pqc_support(&block)
    # Even with a new enough OpenSSL, the runtime may keep PQC groups and
    # signature algorithms out of its default negotiation lists (for example
    # RHEL's system-wide crypto policies). The PQC server forces both, while
    # the gem fetcher connects with the default client configuration, so a
    # real loopback handshake is the only reliable way to tell whether this
    # environment can negotiate PQC at all.
    unless Gem::PQCUtilities.support_pqc_handshake?
      yield "OpenSSL or Ruby OpenSSL is too old to support PQC, "\
            "or PQC handshake is not available in this OpenSSL configuration"
    end
  end

  ##
  # Returns whether the runtime OpenSSL can generate ML-DSA keys.
  # Unlike support_pqc_handshake?, this only probes key generation.
  # Gem::Security.create_key tests need it.
  # Handshake cannot be used to judge ML-DSA key availability on
  # OpenSSL >= 3.5 with Ruby OpenSSL < 4.0.0, where support_pqc_handshake? is
  # false due to Ruby OpenSSL's missing methods but
  # OpenSSL::PKey.generate_key succeeds.

  def self.support_ml_dsa_key?
    return @support_ml_dsa_key unless @support_ml_dsa_key.nil?

    @support_ml_dsa_key =
      begin
        OpenSSL::PKey.generate_key("ML-DSA-65")
        true
      # NoMethodError: JRuby 10.1.0.0's Ruby OpenSSL lacks generate_key.
      rescue OpenSSL::PKey::PKeyError, NoMethodError
        false
      end
  end

  ##
  # Returns whether the runtime can sign an X.509 certificate with an ML-DSA
  # key. Ruby OpenSSL rejects the nil digest that needs before 3.3, so
  # support_ml_dsa_key? alone does not cover certificate building.

  def self.support_ml_dsa_cert?
    return @support_ml_dsa_cert unless @support_ml_dsa_cert.nil?

    @support_ml_dsa_cert =
      begin
        key = OpenSSL::PKey.generate_key("ML-DSA-65")
        cert = OpenSSL::X509::Certificate.new
        cert.subject = cert.issuer = OpenSSL::X509::Name.new([["CN", "probe"]])
        cert.public_key = OpenSSL::PKey.read(key.public_to_pem)
        cert.not_before = Time.now
        cert.not_after = Time.now + 60
        cert.sign(key, nil)
        true
      # NoMethodError: JRuby's Ruby OpenSSL lacks generate_key.
      # TypeError: Ruby OpenSSL < 3.3 rejects a nil digest here.
      rescue OpenSSL::PKey::PKeyError, OpenSSL::X509::CertificateError,
             NoMethodError, TypeError
        false
      end
  end

  ##
  # Returns the algorithm named in the SubjectPublicKeyInfo of +key+, such as
  # "ML-DSA-65". OpenSSL::PKey::PKey#inspect only names the algorithm on Ruby
  # OpenSSL >= 4.0, and #oid raises for the provider-backed keys ML-DSA uses.

  def self.key_algorithm_name(key)
    OpenSSL::ASN1.decode(key.public_to_der).value.first.value.first.ln
  end

  # Probe an actual PQC handshake between a forced-PQC server and a
  # default-configured client, mirroring what the integration tests exercise.
  # Memoized so the probe runs at most once per process.
  def self.support_pqc_handshake?
    return @support_pqc_handshake unless @support_pqc_handshake.nil?

    @support_pqc_handshake = probe_pqc_handshake
  end

  def self.probe_pqc_handshake
    server = TCPServer.new("127.0.0.1", 0)
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.cert = Gem::PEMUtilities::MLDSA65_SSL_CERT
    ctx.key = Gem::PEMUtilities::MLDSA65_SSL_KEY
    # ctx.key is nil when unsupported ML-DSA-65 algorithm's file is read with
    # old OpenSSL versions.
    return false unless ctx.key

    # ctx.groups (OpenSSL::SSL::SSLContext#groups) requires Ruby OpenSSL >= 4.0.
    return false unless ctx.respond_to?(:groups=)

    ctx.groups = "X25519MLKEM768"
    ssl_server = OpenSSL::SSL::SSLServer.new(server, ctx)

    port = server.addr[1]
    server_thread = Thread.new do
      client = ssl_server.accept
      client.close
    rescue OpenSSL::OpenSSLError
      nil
    end

    client_ctx = OpenSSL::SSL::SSLContext.new
    client_ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
    socket = TCPSocket.new("127.0.0.1", port)
    ssl = OpenSSL::SSL::SSLSocket.new(socket, client_ctx)
    ssl.connect
    ssl.close
    true
  rescue OpenSSL::OpenSSLError, SystemCallError
    false
  ensure
    server_thread&.join(5)
    server_thread&.kill if server_thread&.alive?
    ssl_server&.close
    server&.close
  end
end

# frozen_string_literal: true

# This file can be loaded by RubyGems test-unit files and Bundler rspec files.
# Don't add test-unit or rspec dependent logic in this file.

require "socket"
require "openssl"

module Gem::PQCUtilities
  CERTS_DIR = __dir__

  def without_pqc_support(&block)
    # PQC algorithms ML-KEM and ML-DSA require OpenSSL >= 3.5.
    # https://openssl-library.org/post/2025-04-08-openssl-35-final-release/
    unless OpenSSL::OPENSSL_VERSION_NUMBER >= 0x30500000
      yield "PQC algorithms require OpenSSL >= 3.5"
      return
    end
    # Ruby OpenSSL >= 4.0 has useful methods in PQC use cases.
    # https://github.com/ruby/openssl/blob/v4.0.0/History.md?plain=1#L25-L35
    # And fixed the following bug related to PQC.
    # https://github.com/ruby/openssl/pull/898
    unless Gem::Version.new(OpenSSL::VERSION) >= Gem::Version.new("4.0")
      yield "PQC test requires Ruby OpenSSL >= 4.0"
      return
    end
    # Even with a new enough OpenSSL, the runtime may keep PQC groups and
    # signature algorithms out of its default negotiation lists (for example
    # RHEL's system-wide crypto policies). The PQC server forces both, while
    # the gem fetcher connects with the default client configuration, so a
    # real loopback handshake is the only reliable way to tell whether this
    # environment can negotiate PQC at all.
    unless Gem::PQCUtilities.support_pqc_handshake?
      yield "PQC handshake is not available in this OpenSSL configuration"
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

# frozen_string_literal: true

# This file can be loaded by RubyGems test-unit files and Bundler rspec files.
# Don't add test-unit or rspec dependent logic in this file.

require "socket"
require "openssl"

module Gem::LocalSSLServerUtilities
  CERTS_DIR = __dir__

  def certs_dir
    CERTS_DIR
  end

  def initialize_ssl_server
    @ssl_server_thread = nil
    @ssl_server = nil
  end

  def stop_ssl_server
    if @ssl_server_thread
      @ssl_server_thread.kill.join
      @ssl_server_thread = nil
    end
    if @ssl_server
      @ssl_server.close
      @ssl_server = nil
    end
  end

  # mode:
  #   :non_pqc - Run single server with PQC-unsupported RSA (default)
  #   :pqc     - Run single server with PQC-supported key exchange,
  #              X25519MLKEM768, and PQC-supported certificate, ML-DSA-65
  def start_ssl_server(config = {})
    mode = config.fetch(:mode, :non_pqc)
    server = TCPServer.new(0)
    ctx = OpenSSL::SSL::SSLContext.new

    case mode
    when :non_pqc
      ctx.cert = cert("ssl_cert.pem")
      ctx.key = key("ssl_key.pem")
      ctx.ca_file = File.join(certs_dir, "ca_cert.pem")
    when :pqc
      ctx.cert = cert("mldsa65_ssl_cert.pem")
      ctx.key = key("mldsa65_ssl_key.pem")
      ctx.ca_file = File.join(certs_dir, "mldsa65_ca_cert.pem")
      ctx.groups = "X25519MLKEM768"
    end

    ctx.verify_mode = config[:verify_mode] if config[:verify_mode]
    @ssl_server = OpenSSL::SSL::SSLServer.new(server, ctx)
    @ssl_server_thread = Thread.new do
      loop do
        ssl_client = @ssl_server.accept
        Thread.new(ssl_client) do |client|
          handle_request(client)
        ensure
          client.close
        end
      rescue OpenSSL::SSL::SSLError
        # Ignore SSL errors because we're testing them implicitly
      end
    end
    @ssl_server
  end

  def handle_request(client)
    request = client.gets
    if request&.start_with?("GET /yaml")
      client.print "HTTP/1.1 200 OK\r\nContent-Type: text/yaml\r\n\r\n--- true\n"
    elsif request&.start_with?("GET /insecure_redirect")
      location = request.match(/to=([^ ]+)/)[1]
      client.print "HTTP/1.1 301 Moved Permanently\r\nLocation: #{location}\r\n\r\n"
    else
      client.print "HTTP/1.1 404 Not Found\r\n\r\n"
    end
  end

  def cert(filename)
    OpenSSL::X509::Certificate.new(File.read(File.join(certs_dir, filename)))
  end

  def key(filename)
    OpenSSL::PKey.read(File.read(File.join(certs_dir, filename)))
  end

  def without_pqc_support(&block)
    # PQC algorithms ML-KEM and ML-DSA require OpenSSL >= 3.5.
    # https://openssl-library.org/post/2025-04-08-openssl-35-final-release/
    unless OpenSSL::OPENSSL_VERSION_NUMBER >= 0x30500000
      yield "PQC algorithms require OpenSSL >= 3.5"
      return
    end
    # ctx.groups (OpenSSL::SSL::SSLContext#groups) used in start_ssl_server
    # mode :pqc requires Ruby OpenSSL >= 4.0.
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
    unless Gem::LocalSSLServerUtilities.support_pqc_handshake?
      yield "PQC handshake is not available in this OpenSSL configuration"
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
    ctx.cert = OpenSSL::X509::Certificate.new(File.read(File.join(CERTS_DIR, "mldsa65_ssl_cert.pem")))
    ctx.key = OpenSSL::PKey.read(File.read(File.join(CERTS_DIR, "mldsa65_ssl_key.pem")))
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

# frozen_string_literal: true

# This file can be loaded by RubyGems test-unit files and Bundler rspec files.
# Don't add test-unit or rspec dependent logic in this file.

require "socket"
require "openssl"
require_relative "pem_utilities"
require_relative "pqc_utilities"

module Gem::LocalSSLServerUtilities
  include Gem::PEMUtilities
  include Gem::PQCUtilities

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
      ctx.cert = SSL_CERT
      ctx.key = SSL_KEY
      ctx.ca_file = CA_CERT_FILE
    when :pqc
      ctx.cert = MLDSA65_SSL_CERT
      ctx.key = MLDSA65_SSL_KEY
      ctx.ca_file = MLDSA65_CA_CERT_FILE
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
end

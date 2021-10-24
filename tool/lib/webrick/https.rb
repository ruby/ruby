# frozen_string_literal: false
#
# https.rb -- SSL/TLS enhancement for HTTPServer
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2001 GOTOU Yuuzou
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: https.rb,v 1.15 2003/07/22 19:20:42 gotoyuzo Exp $

require_relative 'ssl'
require_relative 'httpserver'

module WEBrick
  module Config
    HTTP.update(SSL)
  end

  ##
  #--
  # Adds SSL functionality to WEBrick::HTTPRequest

  class HTTPRequest

    ##
    # HTTP request SSL cipher

    attr_reader :cipher

    ##
    # HTTP request server certificate

    attr_reader :server_cert

    ##
    # HTTP request client certificate

    attr_reader :client_cert

    # :stopdoc:

    alias orig_parse parse

    def parse(socket=nil)
      if socket.respond_to?(:cert)
        @server_cert = socket.cert || @config[:SSLCertificate]
        @client_cert = socket.peer_cert
        @client_cert_chain = socket.peer_cert_chain
        @cipher      = socket.cipher
      end
      orig_parse(socket)
    end

    alias orig_parse_uri parse_uri

    def parse_uri(str, scheme="https")
      if server_cert
        return orig_parse_uri(str, scheme)
      end
      return orig_parse_uri(str)
    end
    private :parse_uri

    alias orig_meta_vars meta_vars

    def meta_vars
      meta = orig_meta_vars
      if server_cert
        meta["HTTPS"] = "on"
        meta["SSL_SERVER_CERT"] = @server_cert.to_pem
        meta["SSL_CLIENT_CERT"] = @client_cert ? @client_cert.to_pem : ""
        if @client_cert_chain
          @client_cert_chain.each_with_index{|cert, i|
            meta["SSL_CLIENT_CERT_CHAIN_#{i}"] = cert.to_pem
          }
        end
        meta["SSL_CIPHER"] = @cipher[0]
        meta["SSL_PROTOCOL"] = @cipher[1]
        meta["SSL_CIPHER_USEKEYSIZE"] = @cipher[2].to_s
        meta["SSL_CIPHER_ALGKEYSIZE"] = @cipher[3].to_s
      end
      meta
    end

    # :startdoc:
  end

  ##
  #--
  # Fake WEBrick::HTTPRequest for lookup_server

  class SNIRequest

    ##
    # The SNI hostname

    attr_reader :host

    ##
    # The socket address of the server

    attr_reader :addr

    ##
    # The port this request is for

    attr_reader :port

    ##
    # Creates a new SNIRequest.

    def initialize(sslsocket, hostname)
      @host = hostname
      @addr = sslsocket.addr
      @port = @addr[1]
    end
  end


  ##
  #--
  # Adds SSL functionality to WEBrick::HTTPServer

  class HTTPServer < ::WEBrick::GenericServer
    ##
    # ServerNameIndication callback

    def ssl_servername_callback(sslsocket, hostname = nil)
      req = SNIRequest.new(sslsocket, hostname)
      server = lookup_server(req)
      server ? server.ssl_context : nil
    end

    # :stopdoc:

    ##
    # Check whether +server+ is also SSL server.
    # Also +server+'s SSL context will be created.

    alias orig_virtual_host virtual_host

    def virtual_host(server)
      if @config[:SSLEnable] && !server.ssl_context
        raise ArgumentError, "virtual host must set SSLEnable to true"
      end
      orig_virtual_host(server)
    end

    # :startdoc:
  end
end

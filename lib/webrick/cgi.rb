#
# cgi.rb -- Yet another CGI library
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2003 Internet Programming with Ruby writers. All rights
# reserved.
#
# $Id$

require "webrick/httprequest"
require "webrick/httpresponse"
require "webrick/config"
require "stringio"

module WEBrick
  module Config
    CGI = HTTP.dup.update(
      :ServerSoftware => ENV["SERVER_SOFTWARE"],
      :RunOnCGI       => true,   # to detect if it runs on CGI.
      :NPH            => false   # set true to run as NPH script.
    )
  end

  class CGI
    def initialize(*args)
      config = args.shift || Hash.new
      @config = default_config.dup.update(config)
      @logger = @config[:Logger] || WEBrick::Log.new($stderr)
      @options = args
    end

    def default_config
      WEBrick::Config::CGI
    end

    def start(env=ENV, stdin=$stdin, stdout=$stdout)
      sock = WEBrick::CGI::Socket.new(@config, env, stdin, stdout)
      req = HTTPRequest.new(@config)
      res = HTTPResponse.new(@config)
      unless @config[:NPH]
        def res.setup_header
          @header["status"] ||= @status
          super
        end
        def res.status_line
          ""
        end
      end

      begin
        req.parse(sock)
        req.script_name = (env["SCRIPT_NAME"] || "").dup
        if env["PATH_INFO"].nil? || env["PATH_INFO"].empty?
          req.path_info = nil
        else
          req.path_info = env["PATH_INFO"].dup
        end
        res.request_method = req.request_method
        res.request_uri = req.request_uri
        res.request_http_version = req.http_version
        res.keep_alive = req.keep_alive?
        self.service(req, res)
      rescue HTTPStatus::Error => ex
        res.set_error(ex)
      rescue HTTPStatus::Status => ex
        res.status = ex.code
      rescue Exception => ex 
        @logger.error(ex)
        res.set_error(ex, true)
      ensure
        req.fixup
        res.send_response(sock)
      end
    end

    def service(req, res)
      method_name = "do_" + req.request_method.gsub(/-/, "_")
      if respond_to?(method_name)
        __send__(method_name, req, res)
      else
        raise HTTPStatus::MethodNotAllowed,
              "unsupported method `#{req.request_method}'."
      end
    end

    class Socket
      include Enumerable

      private
  
      def initialize(config, env, stdin, stdout)
        @env = env
        @header_part = StringIO.new
        @body_part = stdin
        @out_port = stdout
  
        @server_addr = @env["SERVER_ADDR"] || "0.0.0.0"
        @server_name = @env["SERVER_NAME"]
        @server_port = @env["SERVER_PORT"]
        @remote_addr = @env["REMOTE_ADDR"]
        @remote_host = @env["REMOTE_HOST"] || @remote_addr
        @remote_port = @env["REMOTE_PORT"] || 0

        begin
          setup_header
        rescue Exception => ex
          raise Errno::EPIPE, "invalid CGI environment"
        end
        @header_part << CRLF
        @header_part.rewind
      end
  
      def setup_header
        req_line = ""
        req_line << @env["REQUEST_METHOD"] << " "
        req_line << @env["SCRIPT_NAME"]
        req_line << @env["PATH_INFO"] if @env["PATH_INFO"]
        if @env["QUERY_STRING"]
          req_line << "?" << @env["QUERY_STRING"]
        end
        req_line << " " << @env["SERVER_PROTOCOL"]
        @header_part << req_line << CRLF
        add_header("CONTENT_TYPE", "Content-Type")
        add_header("CONTENT_LENGTH", "Content-length")
        @env.each_key do |name|
          if /^HTTP_(.*)/ =~ name
            add_header(name, $1.gsub(/_/, "-"))
          end
        end
      end
  
      def add_header(envname, hdrname)
        if @env[envname] && !@env[envname].empty?
          @header_part << hdrname << ": " << @env[envname] << CRLF
        end
      end

      def input
        @header_part.eof? ? @body_part : @header_part
      end
  
      public
  
      def peeraddr
        [nil, @remote_port, @remote_host, @remote_addr]
      end
  
      def addr
        [nil, @server_port, @server_name, @server_addr]
      end
  
      def gets(eol=LF)
        input.gets(eol)
      end
  
      def read(size=nil)
        input.read(size)
      end

      def each
        input.each{|line| yield(line) }
      end
  
      def <<(data)
        @out_port << data
      end

      def cert
        if pem = @env["SSL_SERVER_CERT"]
          OpenSSL::X509::Certificate.new(pem) unless pem.empty?
        end
      end

      def peer_cert
        if pem = @env["SSL_CLIENT_CERT"]
          OpenSSL::X509::Certificate.new(pem) unless pem.empty?
        end
      end

      def peer_cert_chain
        if @env["SSL_CLIENT_CERT_CHAIN_0"]
          keys = @env.keys
          certs = keys.sort.collect{|k|
            if /^SSL_CLIENT_CERT_CHAIN_\d+$/ =~ k
              if pem = @env[k]
                OpenSSL::X509::Certificate.new(pem) unless pem.empty?
              end
            end
          }
          certs.compact
        end
      end

      def cipher
        if cipher = @env["SSL_CIPHER"]
          [ cipher ]
        end
      end
    end
  end 
end  

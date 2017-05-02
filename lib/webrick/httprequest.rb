# frozen_string_literal: false
#
# httprequest.rb -- HTTPRequest Class
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2000, 2001 TAKAHASHI Masayoshi, GOTOU Yuuzou
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: httprequest.rb,v 1.64 2003/07/13 17:18:22 gotoyuzo Exp $

require 'uri'
require 'webrick/httpversion'
require 'webrick/httpstatus'
require 'webrick/httputils'
require 'webrick/cookie'

module WEBrick

  ##
  # An HTTP request.  This is consumed by service and do_* methods in
  # WEBrick servlets

  class HTTPRequest

    BODY_CONTAINABLE_METHODS = [ "POST", "PUT" ] # :nodoc:

    # :section: Request line

    ##
    # The complete request line such as:
    #
    #   GET / HTTP/1.1

    attr_reader :request_line

    ##
    # The request method, GET, POST, PUT, etc.

    attr_reader :request_method

    ##
    # The unparsed URI of the request

    attr_reader :unparsed_uri

    ##
    # The HTTP version of the request

    attr_reader :http_version

    # :section: Request-URI

    ##
    # The parsed URI of the request

    attr_reader :request_uri

    ##
    # The request path

    attr_reader :path

    ##
    # The script name (CGI variable)

    attr_accessor :script_name

    ##
    # The path info (CGI variable)

    attr_accessor :path_info

    ##
    # The query from the URI of the request

    attr_accessor :query_string

    # :section: Header and entity body

    ##
    # The raw header of the request

    attr_reader :raw_header

    ##
    # The parsed header of the request

    attr_reader :header

    ##
    # The parsed request cookies

    attr_reader :cookies

    ##
    # The Accept header value

    attr_reader :accept

    ##
    # The Accept-Charset header value

    attr_reader :accept_charset

    ##
    # The Accept-Encoding header value

    attr_reader :accept_encoding

    ##
    # The Accept-Language header value

    attr_reader :accept_language

    # :section:

    ##
    # The remote user (CGI variable)

    attr_accessor :user

    ##
    # The socket address of the server

    attr_reader :addr

    ##
    # The socket address of the client

    attr_reader :peeraddr

    ##
    # Hash of request attributes

    attr_reader :attributes

    ##
    # Is this a keep-alive connection?

    attr_reader :keep_alive

    ##
    # The local time this request was received

    attr_reader :request_time

    ##
    # Creates a new HTTP request.  WEBrick::Config::HTTP is the default
    # configuration.

    def initialize(config)
      @config = config
      @buffer_size = @config[:InputBufferSize]
      @logger = config[:Logger]

      @request_line = @request_method =
        @unparsed_uri = @http_version = nil

      @request_uri = @host = @port = @path = nil
      @script_name = @path_info = nil
      @query_string = nil
      @query = nil
      @form_data = nil

      @raw_header = Array.new
      @header = nil
      @cookies = []
      @accept = []
      @accept_charset = []
      @accept_encoding = []
      @accept_language = []
      @body = ""

      @addr = @peeraddr = nil
      @attributes = {}
      @user = nil
      @keep_alive = false
      @request_time = nil

      @remaining_size = nil
      @socket = nil

      @forwarded_proto = @forwarded_host = @forwarded_port =
        @forwarded_server = @forwarded_for = nil
    end

    ##
    # Parses a request from +socket+.  This is called internally by
    # WEBrick::HTTPServer.

    def parse(socket=nil)
      @socket = socket
      begin
        @peeraddr = socket.respond_to?(:peeraddr) ? socket.peeraddr : []
        @addr = socket.respond_to?(:addr) ? socket.addr : []
      rescue Errno::ENOTCONN
        raise HTTPStatus::EOFError
      end

      read_request_line(socket)
      if @http_version.major > 0
        read_header(socket)
        @header['cookie'].each{|cookie|
          @cookies += Cookie::parse(cookie)
        }
        @accept = HTTPUtils.parse_qvalues(self['accept'])
        @accept_charset = HTTPUtils.parse_qvalues(self['accept-charset'])
        @accept_encoding = HTTPUtils.parse_qvalues(self['accept-encoding'])
        @accept_language = HTTPUtils.parse_qvalues(self['accept-language'])
      end
      return if @request_method == "CONNECT"
      return if @unparsed_uri == "*"

      begin
        setup_forwarded_info
        @request_uri = parse_uri(@unparsed_uri)
        @path = HTTPUtils::unescape(@request_uri.path)
        @path = HTTPUtils::normalize_path(@path)
        @host = @request_uri.host
        @port = @request_uri.port
        @query_string = @request_uri.query
        @script_name = ""
        @path_info = @path.dup
      rescue
        raise HTTPStatus::BadRequest, "bad URI `#{@unparsed_uri}'."
      end

      if /close/io =~ self["connection"]
        @keep_alive = false
      elsif /keep-alive/io =~ self["connection"]
        @keep_alive = true
      elsif @http_version < "1.1"
        @keep_alive = false
      else
        @keep_alive = true
      end
    end

    ##
    # Generate HTTP/1.1 100 continue response if the client expects it,
    # otherwise does nothing.

    def continue # :nodoc:
      if self['expect'] == '100-continue' && @config[:HTTPVersion] >= "1.1"
        @socket << "HTTP/#{@config[:HTTPVersion]} 100 continue#{CRLF}#{CRLF}"
        @header.delete('expect')
      end
    end

    ##
    # Returns the request body.

    def body(&block) # :yields: body_chunk
      block ||= Proc.new{|chunk| @body << chunk }
      read_body(@socket, block)
      @body.empty? ? nil : @body
    end

    ##
    # Request query as a Hash

    def query
      unless @query
        parse_query()
      end
      @query
    end

    ##
    # The content-length header

    def content_length
      return Integer(self['content-length'])
    end

    ##
    # The content-type header

    def content_type
      return self['content-type']
    end

    ##
    # Retrieves +header_name+

    def [](header_name)
      if @header
        value = @header[header_name.downcase]
        value.empty? ? nil : value.join(", ")
      end
    end

    ##
    # Iterates over the request headers

    def each
      if @header
        @header.each{|k, v|
          value = @header[k]
          yield(k, value.empty? ? nil : value.join(", "))
        }
      end
    end

    ##
    # The host this request is for

    def host
      return @forwarded_host || @host
    end

    ##
    # The port this request is for

    def port
      return @forwarded_port || @port
    end

    ##
    # The server name this request is for

    def server_name
      return @forwarded_server || @config[:ServerName]
    end

    ##
    # The client's IP address

    def remote_ip
      return self["client-ip"] || @forwarded_for || @peeraddr[3]
    end

    ##
    # Is this an SSL request?

    def ssl?
      return @request_uri.scheme == "https"
    end

    ##
    # Should the connection this request was made on be kept alive?

    def keep_alive?
      @keep_alive
    end

    def to_s # :nodoc:
      ret = @request_line.dup
      @raw_header.each{|line| ret << line }
      ret << CRLF
      ret << body if body
      ret
    end

    ##
    # Consumes any remaining body and updates keep-alive status

    def fixup() # :nodoc:
      begin
        body{|chunk| }   # read remaining body
      rescue HTTPStatus::Error => ex
        @logger.error("HTTPRequest#fixup: #{ex.class} occurred.")
        @keep_alive = false
      rescue => ex
        @logger.error(ex)
        @keep_alive = false
      end
    end

    # This method provides the metavariables defined by the revision 3
    # of "The WWW Common Gateway Interface Version 1.1"
    # To browse the current document of CGI Version 1.1, see below:
    # http://tools.ietf.org/html/rfc3875

    def meta_vars
      meta = Hash.new

      cl = self["Content-Length"]
      ct = self["Content-Type"]
      meta["CONTENT_LENGTH"]    = cl if cl.to_i > 0
      meta["CONTENT_TYPE"]      = ct.dup if ct
      meta["GATEWAY_INTERFACE"] = "CGI/1.1"
      meta["PATH_INFO"]         = @path_info ? @path_info.dup : ""
     #meta["PATH_TRANSLATED"]   = nil      # no plan to be provided
      meta["QUERY_STRING"]      = @query_string ? @query_string.dup : ""
      meta["REMOTE_ADDR"]       = @peeraddr[3]
      meta["REMOTE_HOST"]       = @peeraddr[2]
     #meta["REMOTE_IDENT"]      = nil      # no plan to be provided
      meta["REMOTE_USER"]       = @user
      meta["REQUEST_METHOD"]    = @request_method.dup
      meta["REQUEST_URI"]       = @request_uri.to_s
      meta["SCRIPT_NAME"]       = @script_name.dup
      meta["SERVER_NAME"]       = @host
      meta["SERVER_PORT"]       = @port.to_s
      meta["SERVER_PROTOCOL"]   = "HTTP/" + @config[:HTTPVersion].to_s
      meta["SERVER_SOFTWARE"]   = @config[:ServerSoftware].dup

      self.each{|key, val|
        next if /^content-type$/i =~ key
        next if /^content-length$/i =~ key
        name = "HTTP_" + key
        name.gsub!(/-/o, "_")
        name.upcase!
        meta[name] = val
      }

      meta
    end

    private

    # :stopdoc:

    MAX_URI_LENGTH = 2083 # :nodoc:

    def read_request_line(socket)
      @request_line = read_line(socket, MAX_URI_LENGTH) if socket
      if @request_line.bytesize >= MAX_URI_LENGTH and @request_line[-1, 1] != LF
        raise HTTPStatus::RequestURITooLarge
      end
      @request_time = Time.now
      raise HTTPStatus::EOFError unless @request_line
      if /^(\S+)\s+(\S++)(?:\s+HTTP\/(\d+\.\d+))?\r?\n/mo =~ @request_line
        @request_method = $1
        @unparsed_uri   = $2
        @http_version   = HTTPVersion.new($3 ? $3 : "0.9")
      else
        rl = @request_line.sub(/\x0d?\x0a\z/o, '')
        raise HTTPStatus::BadRequest, "bad Request-Line `#{rl}'."
      end
    end

    def read_header(socket)
      if socket
        while line = read_line(socket)
          break if /\A(#{CRLF}|#{LF})\z/om =~ line
          @raw_header << line
        end
      end
      @header = HTTPUtils::parse_header(@raw_header.join)
    end

    def parse_uri(str, scheme="http")
      if @config[:Escape8bitURI]
        str = HTTPUtils::escape8bit(str)
      end
      str.sub!(%r{\A/+}o, '/')
      uri = URI::parse(str)
      return uri if uri.absolute?
      if @forwarded_host
        host, port = @forwarded_host, @forwarded_port
      elsif self["host"]
        pattern = /\A(#{URI::REGEXP::PATTERN::HOST})(?::(\d+))?\z/n
        host, port = *self['host'].scan(pattern)[0]
      elsif @addr.size > 0
        host, port = @addr[2], @addr[1]
      else
        host, port = @config[:ServerName], @config[:Port]
      end
      uri.scheme = @forwarded_proto || scheme
      uri.host = host
      uri.port = port ? port.to_i : nil
      return URI::parse(uri.to_s)
    end

    def read_body(socket, block)
      return unless socket
      if tc = self['transfer-encoding']
        case tc
        when /chunked/io then read_chunked(socket, block)
        else raise HTTPStatus::NotImplemented, "Transfer-Encoding: #{tc}."
        end
      elsif self['content-length'] || @remaining_size
        @remaining_size ||= self['content-length'].to_i
        while @remaining_size > 0
          sz = [@buffer_size, @remaining_size].min
          break unless buf = read_data(socket, sz)
          @remaining_size -= buf.bytesize
          block.call(buf)
        end
        if @remaining_size > 0 && @socket.eof?
          raise HTTPStatus::BadRequest, "invalid body size."
        end
      elsif BODY_CONTAINABLE_METHODS.member?(@request_method)
        raise HTTPStatus::LengthRequired
      end
      return @body
    end

    def read_chunk_size(socket)
      line = read_line(socket)
      if /^([0-9a-fA-F]+)(?:;(\S+))?/ =~ line
        chunk_size = $1.hex
        chunk_ext = $2
        [ chunk_size, chunk_ext ]
      else
        raise HTTPStatus::BadRequest, "bad chunk `#{line}'."
      end
    end

    def read_chunked(socket, block)
      chunk_size, = read_chunk_size(socket)
      while chunk_size > 0
        data = read_data(socket, chunk_size) # read chunk-data
        if data.nil? || data.bytesize != chunk_size
          raise BadRequest, "bad chunk data size."
        end
        read_line(socket)                    # skip CRLF
        block.call(data)
        chunk_size, = read_chunk_size(socket)
      end
      read_header(socket)                    # trailer + CRLF
      @header.delete("transfer-encoding")
      @remaining_size = 0
    end

    def _read_data(io, method, *arg)
      begin
        WEBrick::Utils.timeout(@config[:RequestTimeout]){
          return io.__send__(method, *arg)
        }
      rescue Errno::ECONNRESET
        return nil
      rescue Timeout::Error
        raise HTTPStatus::RequestTimeout
      end
    end

    def read_line(io, size=4096)
      _read_data(io, :gets, LF, size)
    end

    def read_data(io, size)
      _read_data(io, :read, size)
    end

    def parse_query()
      begin
        if @request_method == "GET" || @request_method == "HEAD"
          @query = HTTPUtils::parse_query(@query_string)
        elsif self['content-type'] =~ /^application\/x-www-form-urlencoded/
          @query = HTTPUtils::parse_query(body)
        elsif self['content-type'] =~ /^multipart\/form-data; boundary=(.+)/
          boundary = HTTPUtils::dequote($1)
          @query = HTTPUtils::parse_form_data(body, boundary)
        else
          @query = Hash.new
        end
      rescue => ex
        raise HTTPStatus::BadRequest, ex.message
      end
    end

    PrivateNetworkRegexp = /
      ^unknown$|
      ^((::ffff:)?127.0.0.1|::1)$|
      ^(::ffff:)?(10|172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.
    /ixo

    ForwardedInfo = Struct.new(:for, :server, :proto, :host, :port)

    # Setup the first non-private network from Forwaded header.
    # If Forwaded header does not exist, then try X-Forwaded-* headers.
    # It's said that all X-Forwarded-* headers will contain more than one
    # (comma-separated) value if the original request already contained one of
    # these headers. Since we could use these values as Host header, we choose
    # the initial(first) value. (apr_table_mergen() adds new value after the
    # existing value with ", " prefix)
    def setup_forwarded_info
      if forwarded = self["forwarded"]
        forwarded = forwarded.split(/\s*,\s*/).map do |s|
          info = ForwardedInfo.new
          s.scan(/\G\s*(for|server|proto|host)=([^;]*)(?:;|\z)/i) do |n, v|
            info[n.downcase] = v
          end
          info.host, info.port = forwarded_host_port(info.host, info.proto)
          info.freeze
        end
        @forwarded = forwarded
        forwarded.find do |info|
          next if PrivateNetworkRegexp =~ info.for
          @forwarded_server = info.server
          @forwarded_proto = info.proto
          @forwarded_host = info.host
          @forwarded_port = info.port
          @forwarded_for = info.for
          true
        end
        return
      end
      if @forwarded_server = self["x-forwarded-server"]
        @forwarded_server = @forwarded_server.split(",", 2).first
      end
      if @forwarded_proto = self["x-forwarded-proto"]
        @forwarded_proto = @forwarded_proto.split(",", 2).first
      end
      if host_port = self["x-forwarded-host"]
        @forwarded_host, @forwarded_port =
                         forwarded_host_port(host_port.split(",", 2).first,
                                             @forwarded_proto)
      end
      if addrs = self["x-forwarded-for"]
        addrs = addrs.split(",").collect(&:strip)
        addrs.reject!{|ip| PrivateNetworkRegexp =~ ip }
        @forwarded_for = addrs.first
      end
    end

    def forwarded_host_port(host, proto)
      host, port = host.split(":", 2) if host
      return host, (port ? port.to_i : (proto == "https" ? 443 : 80))
    end

    # :startdoc:
  end
end

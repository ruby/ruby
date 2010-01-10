#
# httprequest.rb -- HTTPRequest Class
#
# Author: IPR -- Internet Programming with Ruby -- writers
# Copyright (c) 2000, 2001 TAKAHASHI Masayoshi, GOTOU Yuuzou
# Copyright (c) 2002 Internet Programming with Ruby writers. All rights
# reserved.
#
# $IPR: httprequest.rb,v 1.64 2003/07/13 17:18:22 gotoyuzo Exp $

require 'timeout'
require 'uri'

require 'webrick/httpversion'
require 'webrick/httpstatus'
require 'webrick/httputils'
require 'webrick/cookie'

module WEBrick

  class HTTPRequest
    BODY_CONTAINABLE_METHODS = [ "POST", "PUT" ]
    BUFSIZE = 1024*4

    # Request line
    attr_reader :request_line
    attr_reader :request_method, :unparsed_uri, :http_version

    # Request-URI
    attr_reader :request_uri, :host, :port, :path
    attr_accessor :script_name, :path_info, :query_string

    # Header and entity body
    attr_reader :raw_header, :header, :cookies
    attr_reader :accept, :accept_charset
    attr_reader :accept_encoding, :accept_language

    # Misc
    attr_accessor :user
    attr_reader :addr, :peeraddr
    attr_reader :attributes
    attr_reader :keep_alive
    attr_reader :request_time

    def initialize(config)
      @config = config
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
    end

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

    def body(&block)
      block ||= Proc.new{|chunk| @body << chunk }
      read_body(@socket, block)
      @body.empty? ? nil : @body
    end

    def query
      unless @query
        parse_query()
      end
      @query
    end

    def content_length
      return Integer(self['content-length'])
    end

    def content_type
      return self['content-type']
    end

    def [](header_name)
      if @header
        value = @header[header_name.downcase]
        value.empty? ? nil : value.join(", ")
      end
    end

    def each
      @header.each{|k, v|
        value = @header[k]
        yield(k, value.empty? ? nil : value.join(", "))
      }
    end

    def keep_alive?
      @keep_alive
    end

    def to_s
      ret = @request_line.dup
      @raw_header.each{|line| ret << line }
      ret << CRLF
      ret << body if body
      ret
    end

    def fixup()
      begin
        body{|chunk| }   # read remaining body
      rescue HTTPStatus::Error => ex
        @logger.error("HTTPRequest#fixup: #{ex.class} occured.")
        @keep_alive = false
      rescue => ex
        @logger.error(ex)
        @keep_alive = false
      end
    end

    def meta_vars
      # This method provides the metavariables defined by the revision 3
      # of ``The WWW Common Gateway Interface Version 1.1''.
      # (http://Web.Golux.Com/coar/cgi/)

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

    def read_request_line(socket)
      @request_line = read_line(socket) if socket
      @request_time = Time.now
      raise HTTPStatus::EOFError unless @request_line
      if /^(\S+)\s+(\S+?)(?:\s+HTTP\/(\d+\.\d+))?\r?\n/mo =~ @request_line
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
      uri = URI::parse(str)
      return uri if uri.absolute?
      if self["host"]
        pattern = /\A(#{URI::REGEXP::PATTERN::HOST})(?::(\d+))?\z/n
        host, port = *self['host'].scan(pattern)[0]
      elsif @addr.size > 0
        host, port = @addr[2], @addr[1]
      else
        host, port = @config[:ServerName], @config[:Port]
      end
      uri.scheme = scheme
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
          sz = BUFSIZE < @remaining_size ? BUFSIZE : @remaining_size
          break unless buf = read_data(socket, sz)
          @remaining_size -= buf.size
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
        data = ""
        while data.size < chunk_size
          tmp = read_data(socket, chunk_size-data.size) # read chunk-data
          break unless tmp
          data << tmp
        end
        if data.nil? || data.size != chunk_size
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

    def _read_data(io, method, arg)
      begin
        timeout(@config[:RequestTimeout]){
          return io.__send__(method, arg)
        }
      rescue Errno::ECONNRESET
        return nil
      rescue TimeoutError
        raise HTTPStatus::RequestTimeout
      end
    end

    def read_line(io)
      _read_data(io, :gets, LF)
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
  end
end

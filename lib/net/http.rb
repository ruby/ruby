=begin

= net/http.rb version 1.1.34

written by Minero Aoki <aamine@dp.u-netsurf.ne.jp>

This file is derived from "http-access.rb".

This program is free software.
You can distribute/modify this program under
the terms of the Ruby Distribute License.

Japanese version of this document is in "net" full package.
You can get it from RAA
(Ruby Application Archive: http://www.ruby-lang.org/en/raa.html).


== http.rb version 1.2 features

You can use 1.2 features by calling HTTP.version_1_2. And
calling Net::HTTP.version_1_1 allows to use 1.1 features.

  # example
  HTTP.start {|http1| ...(http1 has 1.1 features)... }

  HTTP.version_1_2
  HTTP.start {|http2| ...(http2 has 1.2 features)... }

  HTTP.version_1_1
  HTTP.start {|http3| ...(http3 has 1.1 features)... }

Changes are:

  * HTTP#get, head, post does not raise ProtocolError
  * HTTP#get, head, post returns only one object, a HTTPResponse object
  * HTTPResponseReceiver is joined into HTTPResponse
  * request object: HTTP::Get, Head, Post; and HTTP#request(req)

WARNING: These features are not definite yet.
They will change without notice!


== class HTTP

=== Class Methods

: new( address = 'localhost', port = 80, proxy_addr = nil, proxy_port = nil )
  creates a new Net::HTTP object.
  If proxy_addr is given, this method is equals to
  Net::HTTP::Proxy(proxy_addr,proxy_port).

: start( address = 'localhost', port = 80, proxy_addr = nil, proxy_port = nil )
: start( address = 'localhost', port = 80, proxy_addr = nil, proxy_port = nil ) {|http| .... }
  is equals to
    Net::HTTP.new( address, port, proxy_addr, proxy_port ).start(&block)

: Proxy( address, port )
  creates a HTTP proxy class.
  Arguments are address/port of proxy host.
  You can replace HTTP class by this proxy class.

    # example
    proxy_http = HTTP::Proxy( 'proxy.foo.org', 8080 )
      :
    proxy_http.start( 'www.ruby-lang.org' ) do |http|
      # connecting proxy.foo.org:8080
      :
    end

: proxy_class?
  If self is HTTP, false.
  If self is a class which was created by HTTP::Proxy(), true.

: port
  HTTP default port (80).


=== Methods

: start
: start {|http| .... }
  creates a new Net::HTTP object and starts HTTP session.

  When this method is called with block, gives a HTTP object to block
  and close HTTP session after returning from the block.

: proxy?
  true if self is a HTTP proxy class

: proxy_address
  address of proxy host. If self is not a proxy, nil.

: proxy_port
  port number of proxy host. If self is not a proxy, nil.

: get( path, header = nil, dest = '' )
: get( path, header = nil ) {|str| .... }
  get data from "path" on connecting host.
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  Data is written to "dest" by using "<<" method.
  This method returns HTTPResponse object, and "dest".

    # example
    response, body = http.get( '/index.html' )

  If called with block, give a part String of entity body.

  Note:
  If status is not 2xx(success), ProtocolError exception is
  raised. At that time, you can get HTTPResponse object from 
  exception object. (same in head/post)

    # example
    begin
      response, body = http.get( '/index.html' )
    rescue Net::ProtoRetriableError => err
      response = err.data
      ...
    end

: head( path, header = nil )
  gets only header from "path" on connecting host.
  "header" is a Hash like { 'Accept' => '*/*', ... }.
  This method returns a HTTPResponse object.
  You can http header from this object like:

    response['content-length']   #-> '2554'
    response['content-type']     #-> 'text/html'
    response['Content-Type']     #-> 'text/html'
    response['CoNtEnT-tYpe']     #-> 'text/html'

: post( path, data, header = nil, dest = '' )
: post( path, data, header = nil ) {|str| .... }
  posts "data" (must be String now) to "path".
  If the body exists, also gets entity body.
  Data is written to "dest" by using "<<" method.
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  This method returns HTTPResponse object and "dest".

  If called with block, gives a part of entity body string.

: get2( path, header = nil )
: get2( path, header = nil ) {|recv| .... }
  send GET request for "path".
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  If this method is called with block, one gives
  a HTTPResponseReceiver object to block.

    # example
    http.get2( '/index.html' ) do |recv|
      # "recv" is a HTTPResponseReceiver object
      recv.header
      recv.body
    end

    # another way
    response = http.get2( '/index.html' )
    response['content-type']
    response.body

    # this is wrong
    http.get2( '/index.html' ) do |recv|
      print recv.response.body   # body is not read yet!!!
    end

    # but this is ok
    http.get2( '/index.html' ) do |recv|
      recv.body                  # read body and set recv.response.body
      print recv.response.body   # ref
    end

: head2( path, header = nil )
: head2( path, header = nil ) {|recv| .... }
  send HEAD request for "path".
  "header" must be a Hash like { 'Accept' => 'text/html', ... }.
  The difference between "head" method is that
  "head2" does not raise exceptions.

  If this method is called with block, one gives
  a HTTPResponseReceiver object to block.

    # example
    response = http.head2( '/index.html' )

    # another way
    http.head2( '/index.html' ) do |recv|
      recv.response
    end

: post2( path, data, header = nil )
: post2( path, data, header = nil ) {|recv| .... }
  posts "data" (must be String now) to "path".
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  If this method is called with block, one gives
  a HTTPResponseReceiver object to block.

    # example
    http.post2( '/anycgi.rb', 'data data data...' ) do |recv|
      # "recv" is a HTTPResponseReceiver object
      recv.header
      recv.body
    end

    # another way
    response = http.post2( '/anycgi.rb', 'important data' )
    response['content-type']
    response.body


== class HTTPResponse

HTTP response object.
All "key" is case-insensitive.

=== Methods

: body
  the entity body (String).

: self[ key ]
  returns header field for "key".
  for HTTP, value is a string like 'text/plain'(for Content-Type),
  '2045'(for Content-Length), 'bytes 0-1023/10024'(for Content-Range).
  If there's some fields which has same name, they are joined with ','.

: self[ key ] = val
  set field value for "key".

: key?( key )
  true if key exists

: each {|name,value| .... }
  iterates for each field name and value pair.

: code
  HTTP result code string. For example, '302'.

: message
  HTTP result message. For example, 'Not Found'.


== class HTTPResponseReceiver

=== Methods

: header
: response
  HTTPResponse object

: read_body( dest = '' )
  reads entity body into DEST by calling "<<" method and
  returns DEST.

: read_body {|string| ... }
  reads entity body little by little and gives it to block
  until entity ends.

: body
: entity
  entity body. If #read_body is called already, returns its
  argument DEST. Else returns entity body as String.

  Calling this method any times causes returning same
  object (does not read entity again).

=end

require 'net/protocol'


module Net

  class HTTPBadResponse < StandardError; end
  class HTTPHeaderSyntaxError < StandardError; end


  class HTTP < Protocol

    HTTPVersion = '1.1'

    #
    # connection
    #

    protocol_param :port, '80'


    def initialize( addr = nil, port = nil )
      super

      @proxy_address = nil
      @proxy_port = nil

      @curr_http_version = HTTPVersion
      @seems_1_0_server = false
    end


    private

    def conn_command( sock )
    end

    def do_finish
    end


    #
    # proxy
    #

    public


    class << self

      def Proxy( p_addr, p_port = nil )
        ProxyMod.create_proxy_class( p_addr, p_port || self.port )
      end

      alias orig_new new

      def new( address = nil, port = nil, p_addr = nil, p_port = nil )
        c = p_addr ? self::Proxy(p_addr, p_port) : self
        i = c.orig_new( address, port )
        setvar i
        i
      end

      def start( address = nil, port = nil, p_addr = nil, p_port = nil, &block )
        new( address, port, p_addr, p_port ).start( &block )
      end

      def proxy_class?
        false
      end

      def proxy_address
        nil
      end

      def proxy_port
        nil
      end

    end

    def proxy?
      false
    end

    def proxy_address
      nil
    end

    def proxy_port
      nil
    end

    def edit_path( path )
      path
    end


    module ProxyMod

      class << self

        def create_proxy_class( p_addr, p_port )
          mod = self
          klass = Class.new( HTTP )
          klass.module_eval {
            include mod
            @proxy_address = p_addr
            @proxy_port    = p_port
          }
          def klass.proxy_class?
            true
          end

          def klass.proxy_address
            @proxy_address
          end

          def klass.proxy_port
            @proxy_port
          end

          klass
        end

      end

      def initialize( addr, port )
        super
        @proxy_address = type.proxy_address
        @proxy_port    = type.proxy_port
      end
    
      attr_reader :proxy_address, :proxy_port

      alias proxyaddr proxy_address
      alias proxyport proxy_port

      def proxy?
        true
      end
    
      private
    
      def conn_socket( addr, port )
        super @proxy_address, @proxy_port
      end

      def edit_path( path )
        'http://' + addr_port + path
      end
    
    end   # module ProxyMod


    #
    # for backward compatibility
    #

    @@newimpl = false

    class << self

      def version_1_2
        @@newimpl = true
      end

      def version_1_1
        @@newimpl = false
      end

      private

      def setvar( obj )
        f = @@newimpl
        obj.instance_eval { @newimpl = f }
      end

    end


    #
    # http operations
    #

    public

    def self.def_http_method( nm, hasdest, hasdata )
      name = nm.id2name.downcase
      cname = nm.id2name
      lineno = __LINE__ + 2
      src = <<"      ----"

        def #{name}( path, #{hasdata ? 'data,' : ''}
                     u_header = nil #{hasdest ? ',dest = nil, &block' : ''} )
          resp = nil
          request(
              #{cname}.new( path, u_header ) #{hasdata ? ',data' : ''}
          ) do |resp|
            resp.read_body( #{hasdest ? 'dest, &block' : ''} )
          end
          if @newimpl then
            resp
          else
            resp.value
            #{hasdest ? 'return resp, resp.body' : 'resp'}
          end
        end

        def #{name}2( path, #{hasdata ? 'data,' : ''}
                      u_header = nil, &block )
          request( #{cname}.new(path, u_header),
                   #{hasdata ? 'data,' : ''} &block )
        end
      ----
      module_eval src, __FILE__, lineno
    end

    def_http_method :Get,  true,  false
    def_http_method :Head, false, false
    def_http_method :Post, true,  true
    def_http_method :Put,  false, true

    def request( req, *args )
      common_oper( req ) {
        req.__send__( :exec,
                @socket, @curr_http_version, edit_path(req.path), *args )
        yield req.response if block_given?
      }
      req.response
    end


    private


    def common_oper( req )
      req['connection'] ||= 'keep-alive'
      if not @socket then
        start
        req['connection'] = 'close'
      elsif @socket.closed? then
        re_connect
      end
      if not req.body_exist? or @seems_1_0_server then
        req['connection'] = 'close'
      end
      req['host'] = addr_port

      yield req
      req.response.__send__ :terminate
      @curr_http_version = req.response.http_version

      if not req.response.body then
        @socket.close
      elsif keep_alive? req, req.response then
        D 'Conn keep-alive'
        if @socket.closed? then   # (only) read stream had been closed
          D 'Conn (but seems 1.0 server)'
          @seems_1_0_server = true
          @socket.close
        end
      else
        D 'Conn close'
        @socket.close
      end

      req.response
    end

    def keep_alive?( req, res )
      /close/i === req['connection'].to_s            and return false
      @seems_1_0_server                              and return false

      /keep-alive/i === res['connection'].to_s       and return true
      /close/i      === res['connection'].to_s       and return false
      /keep-alive/i === res['proxy-connection'].to_s and return true
      /close/i      === res['proxy-connection'].to_s and return false

      @curr_http_version == '1.1'                    and return true
      false
    end


    #
    # utils
    #

    public

    def self.get( addr, path, port = nil )
      req = Get.new( path )
      resp = nil
      new( addr, port || HTTP.port ).start {|http|
        resp = http.request( req )
      }
      resp.body
    end

    def self.get_print( addr, path, port = nil )
      print get( addr, path, port )
    end


    private

    def addr_port
      address + (port == HTTP.port ? '' : ":#{port}")
    end

    def D( msg )
      if @dout then
        @dout << msg
        @dout << "\n"
      end
    end

  end

  HTTPSession = HTTP



  class Code

    def http_mkchild( bodyexist = nil )
      c = mkchild(nil)
      be = if bodyexist.nil? then @body_exist else bodyexist end
      c.instance_eval { @body_exist = be }
      c
    end

    def body_exist?
      @body_exist
    end
  
  end

  HTTPInformationCode               = InformationCode.http_mkchild( false )
  HTTPSuccessCode                   = SuccessCode    .http_mkchild( true )
  HTTPRedirectionCode               = RetriableCode  .http_mkchild( true )
  HTTPRetriableCode = HTTPRedirectionCode
  HTTPClientErrorCode               = FatalErrorCode .http_mkchild( true )
  HTTPFatalErrorCode = HTTPClientErrorCode
  HTTPServerErrorCode               = ServerErrorCode.http_mkchild( true )


  HTTPSwitchProtocol                = HTTPInformationCode.http_mkchild

  HTTPOK                            = HTTPSuccessCode.http_mkchild
  HTTPCreated                       = HTTPSuccessCode.http_mkchild
  HTTPAccepted                      = HTTPSuccessCode.http_mkchild
  HTTPNonAuthoritativeInformation   = HTTPSuccessCode.http_mkchild
  HTTPNoContent                     = HTTPSuccessCode.http_mkchild( false )
  HTTPResetContent                  = HTTPSuccessCode.http_mkchild( false )
  HTTPPartialContent                = HTTPSuccessCode.http_mkchild

  HTTPMultipleChoice                = HTTPRedirectionCode.http_mkchild
  HTTPMovedPermanently              = HTTPRedirectionCode.http_mkchild
  HTTPMovedTemporarily              = HTTPRedirectionCode.http_mkchild
  HTTPNotModified                   = HTTPRedirectionCode.http_mkchild( false )
  HTTPUseProxy                      = HTTPRedirectionCode.http_mkchild( false )
  
  HTTPBadRequest                    = HTTPClientErrorCode.http_mkchild
  HTTPUnauthorized                  = HTTPClientErrorCode.http_mkchild
  HTTPPaymentRequired               = HTTPClientErrorCode.http_mkchild
  HTTPForbidden                     = HTTPClientErrorCode.http_mkchild
  HTTPNotFound                      = HTTPClientErrorCode.http_mkchild
  HTTPMethodNotAllowed              = HTTPClientErrorCode.http_mkchild
  HTTPNotAcceptable                 = HTTPClientErrorCode.http_mkchild
  HTTPProxyAuthenticationRequired   = HTTPClientErrorCode.http_mkchild
  HTTPRequestTimeOut                = HTTPClientErrorCode.http_mkchild
  HTTPConflict                      = HTTPClientErrorCode.http_mkchild
  HTTPGone                          = HTTPClientErrorCode.http_mkchild
  HTTPLengthRequired                = HTTPClientErrorCode.http_mkchild
  HTTPPreconditionFailed            = HTTPClientErrorCode.http_mkchild
  HTTPRequestEntityTooLarge         = HTTPClientErrorCode.http_mkchild
  HTTPRequestURITooLarge            = HTTPClientErrorCode.http_mkchild
  HTTPUnsupportedMediaType          = HTTPClientErrorCode.http_mkchild

  HTTPNotImplemented                = HTTPServerErrorCode.http_mkchild
  HTTPBadGateway                    = HTTPServerErrorCode.http_mkchild
  HTTPServiceUnavailable            = HTTPServerErrorCode.http_mkchild
  HTTPGatewayTimeOut                = HTTPServerErrorCode.http_mkchild
  HTTPVersionNotSupported           = HTTPServerErrorCode.http_mkchild



  ###
  ### header
  ###

  net_private {

  module HTTPHeader

    def size
      @header.size
    end

    alias length size

    def []( key )
      @header[ key.downcase ]
    end

    def []=( key, val )
      @header[ key.downcase ] = val
    end

    def each( &block )
      @header.each( &block )
    end

    def each_key( &block )
      @header.each_key( &block )
    end

    def each_value( &block )
      @header.each_value( &block )
    end

    def delete( key )
      @header.delete key.downcase
    end

    def key?( key )
      @header.key? key.downcase
    end

    def to_hash
      @header.dup
    end

    def canonical_each
      @header.each do |k,v|
        yield canonical(k), v
      end
    end

    def canonical( k )
      k.split('-').collect {|i| i.capitalize }.join('-')
    end

    def range
      s = @header['range']
      s or return nil

      arr = []
      s.split(',').each do |spec|
        m = /bytes\s*=\s*(\d+)?\s*-\s*(\d+)?/i.match( spec )
        m or raise HTTPHeaderSyntaxError, "wrong Range: #{spec}"

        d1 = m[1].to_i
        d2 = m[2].to_i
        if    m[1] and m[2] then arr.push d1 .. d2
        elsif m[1]          then arr.push d1 .. -1
        elsif          m[2] then arr.push -d2 .. -1
        else
          raise HTTPHeaderSyntaxError, 'range is not specified'
        end
      end

      return *arr
    end

    def range=( r, fin = nil )
      if fin then
        r = r ... r+fin
      end

      case r
      when Numeric
        s = r > 0 ? "0-#{r - 1}" : "-#{-r}"
      when Range
        first = r.first
        last = r.last
        if r.exclude_end? then
          last -= 1
        end

        if last == -1 then
          s = first > 0 ? "#{first}-" : "-#{-first}"
        else
          first >= 0 or raise HTTPHeaderSyntaxError, 'range.first is negative' 
          last > 0  or raise HTTPHeaderSyntaxError, 'range.last is negative' 
          first < last or raise HTTPHeaderSyntaxError, 'must be .first < .last'
          s = "#{first}-#{last}"
        end
      else
        raise TypeError, 'Range/Integer is required'
      end

      @header['range'] = "bytes=#{s}"
      r
    end

    alias set_range range=

    def content_length
      s = @header['content-length']
      s or return nil

      m = /\d+/.match(s)
      m or raise HTTPHeaderSyntaxError, 'wrong Content-Length format'
      m[0].to_i
    end

    def chunked?
      s = @header['transfer-encoding']
      (s and /(?:\A|[^\-\w])chunked(?:[^\-\w]|\z)/i === s) ? true : false
    end

    def content_range
      s = @header['content-range']
      s or return nil

      m = %r<bytes\s+(\d+)-(\d+)/(?:\d+|\*)>i.match( s )
      m or raise HTTPHeaderSyntaxError, 'wrong Content-Range format'

      m[1].to_i .. m[2].to_i + 1
    end

    def range_length
      r = content_range
      r and r.length
    end

    def basic_auth( acc, pass )
      @header['authorization'] = ["#{acc}:#{pass}"].pack('m').gsub(/\s+/, '')
    end

  end

  }


  ###
  ### request
  ###

  net_private {

  class HTTPRequest

    include ::Net::NetPrivate::HTTPHeader

    def initialize( path, uhead = nil )
      @path = path
      @header = tmp = {}
      return unless uhead
      uhead.each do |k,v|
        key = k.downcase
        if tmp.key? key then
          $stderr.puts "WARNING: duplicated HTTP header: #{k}" if $VERBOSE
        end
        tmp[ key ] = v.strip
      end
      tmp['accept'] ||= '*/*'

      @socket = nil
      @response = nil
    end

    attr_reader :path
    attr_reader :response

    def inspect
      "\#<#{type}>"
    end

    def body_exist?
      type::HAS_BODY
    end


    private

    #
    # write
    #

    def exec( sock, ver, path )
      ready( sock ) {
        request ver, path
      }
      @response
    end

    def ready( sock )
      @response = nil
      @socket = sock
      yield
      @response = get_response
      @socket = nil
    end

    def request( ver, path )
      @socket.writeline sprintf('%s %s HTTP/%s', type::METHOD, path, ver)
      canonical_each do |k,v|
        @socket.writeline k + ': ' + v
      end
      @socket.writeline ''
    end

    #
    # read
    #

    def get_response
      begin
        resp = read_response
      end while ContinueCode === resp
      resp
    end

    def read_response
      resp = get_resline

      while true do
        line = @socket.readuntil( "\n", true )   # ignore EOF
        line.sub!( /\s+\z/, '' )                 # don't use chop!
        break if line.empty?

        m = /\A([^:]+):\s*/.match( line )
        m or raise HTTPBadResponse, 'wrong header line format'
        nm = m[1]
        line = m.post_match
        if resp.key? nm then
          resp[nm] << ', ' << line
        else
          resp[nm] = line
        end
      end

      resp
    end

    def get_resline
      str = @socket.readline
      m = /\AHTTP(?:\/(\d+\.\d+))?\s+(\d\d\d)\s*(.*)\z/i.match( str )
      m or raise HTTPBadResponse, "wrong status line: #{str}"
      httpver = m[1]
      status  = m[2]
      discrip = m[3]
      
      ::Net::NetPrivate::HTTPResponse.new(
              status, discrip, @socket, type::HAS_BODY, httpver )
    end
  
  end


  class HTTPRequestWithBody < HTTPRequest
  
    private

    def exec( sock, ver, path, str = nil )
      check_arg str, block_given?

      if block_given? then
        ac = Accumulator.new
        yield ac              # must be yield, DO NOT USE block.call
        data = ac.terminate
      else
        data = str
      end
      @header['content-length'] = data.size.to_s
      @header.delete 'transfer-encoding'

      ready( sock ) {
        request ver, path
        @socket.write data
      }
      @response
    end

    def check_arg( data, blkp )
      if data and blkp then
        raise ArgumentError, 'both of data and block given'
      end
      unless data or blkp then
        raise ArgumentError, 'str or block required'
      end
    end
  
  end


  class Accumulator
  
    def initialize
      @buf = ''
    end

    def write( s )
      @buf.concat s
    end

    alias << write

    def terminate
      ret = @buf
      @buf = nil
      ret
    end
  
  end

  }


  class HTTP

    class Get < ::Net::NetPrivate::HTTPRequest
      HAS_BODY = true
      METHOD = 'GET'
    end

    class Head < ::Net::NetPrivate::HTTPRequest
      HAS_BODY = false
      METHOD = 'HEAD'
    end

    class Post < ::Net::NetPrivate::HTTPRequestWithBody
      HAS_BODY = true
      METHOD = 'POST'
    end

    class Put < ::Net::NetPrivate::HTTPRequestWithBody
      HAS_BODY = true
      METHOD = 'PUT'
    end

  end



  ###
  ### response
  ###

  net_private {

  class HTTPResponse < Response

    include ::Net::NetPrivate::HTTPHeader

    CODE_CLASS_TO_OBJ = {
      '1' => HTTPInformationCode,
      '2' => HTTPSuccessCode,
      '3' => HTTPRedirectionCode,
      '4' => HTTPClientErrorCode,
      '5' => HTTPServerErrorCode
    }

    CODE_TO_OBJ = {
      '100' => ContinueCode,
      '101' => HTTPSwitchProtocol,

      '200' => HTTPOK,
      '201' => HTTPCreated,
      '202' => HTTPAccepted,
      '203' => HTTPNonAuthoritativeInformation,
      '204' => HTTPNoContent,
      '205' => HTTPResetContent,
      '206' => HTTPPartialContent,

      '300' => HTTPMultipleChoice,
      '301' => HTTPMovedPermanently,
      '302' => HTTPMovedTemporarily,
      '303' => HTTPMovedPermanently,
      '304' => HTTPNotModified,
      '305' => HTTPUseProxy,

      '400' => HTTPBadRequest,
      '401' => HTTPUnauthorized,
      '402' => HTTPPaymentRequired,
      '403' => HTTPForbidden,
      '404' => HTTPNotFound,
      '405' => HTTPMethodNotAllowed,
      '406' => HTTPNotAcceptable,
      '407' => HTTPProxyAuthenticationRequired,
      '408' => HTTPRequestTimeOut,
      '409' => HTTPConflict,
      '410' => HTTPGone,
      '411' => HTTPFatalErrorCode,
      '412' => HTTPPreconditionFailed,
      '413' => HTTPRequestEntityTooLarge,
      '414' => HTTPRequestURITooLarge,
      '415' => HTTPUnsupportedMediaType,

      '500' => HTTPFatalErrorCode,
      '501' => HTTPNotImplemented,
      '502' => HTTPBadGateway,
      '503' => HTTPServiceUnavailable,
      '504' => HTTPGatewayTimeOut,
      '505' => HTTPVersionNotSupported
    }

    def initialize( stat, msg, sock, be, hv )
      code = CODE_TO_OBJ[stat] ||
             CODE_CLASS_TO_OBJ[stat[0,1]] ||
             UnknownCode
      super code, stat, msg
      @socket = sock
      @body_exist = be
      @http_version = hv

      @header = {}
      @body = nil
      @read = false
    end

    attr_reader :http_version

    def inspect
      "#<#{type} #{code}>"
    end

    def value
      SuccessCode === self or error! self
    end


    #
    # header (for backward compatibility)
    #

    def read_header
      self
    end

    alias header read_header
    alias response read_header

    #
    # body
    #

    def read_body( dest = nil, &block )
      if @read and (dest or block) then
        raise IOError, "#{type}\#read_body called twice with argument"
      end

      unless @read then
        to = procdest( dest, block )
        stream_check

        if @body_exist and code_type.body_exist? then
          read_body_0 to
          @body = to
        else
          @body = nil
        end
        @read = true
      end

      @body
    end

    alias body read_body
    alias entity read_body


    private


    def terminate
      read_body
    end

    def read_body_0( dest )
      if chunked? then
        read_chunked dest
      else
        clen = content_length
        if clen then
          @socket.read clen, dest, true   # ignore EOF
        else
          clen = range_length
          if clen then
            @socket.read clen, dest
          else
            @socket.read_all dest
          end
        end
      end
    end

    def read_chunked( dest )
      len = nil
      total = 0

      while true do
        line = @socket.readline
        m = /[0-9a-fA-F]+/.match( line )
        m or raise HTTPBadResponse, "wrong chunk size line: #{line}"
        len = m[0].hex
        break if len == 0
        @socket.read( len, dest ); total += len
        @socket.read 2   # \r\n
      end
      until @socket.readline.empty? do
        ;
      end
    end

    def stream_check
      @socket.closed? and raise IOError, 'try to read body out of block'
    end

    def procdest( dest, block )
      if dest and block then
        raise ArgumentError, 'both of arg and block are given for HTTP method'
      end
      if block then
        ::Net::NetPrivate::ReadAdapter.new block
      else
        dest || ''
      end
    end

  end

  }


  HTTPResponse         = NetPrivate::HTTPResponse
  HTTPResponseReceiver = NetPrivate::HTTPResponse

end   # module Net

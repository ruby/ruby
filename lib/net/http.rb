=begin

= net/http.rb version 1.2.0

  maintained by Minero Aoki <aamine@dp.u-netsurf.ne.jp>
  This file is derived from "http-access.rb".

  This program is free software.
  You can distribute/modify this program under
  the terms of the Ruby Distribute License.

  Japanese version of this document is in "net" full package.
  You can get it from RAA
  (Ruby Application Archive: http://www.ruby-lang.org/en/raa.html).


= class HTTP

== Class Methods

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


== Methods

: start
: start {|http| .... }
  creates a new Net::HTTP object and starts HTTP session.

  When this method is called with block, gives HTTP object to block
  and close HTTP session after block call finished.

: proxy?
  true if self is a HTTP proxy class

: proxy_address
  address of proxy host. If self is not a proxy, nil.

: proxy_port
  port number of proxy host. If self is not a proxy, nil.

: get( path, header = nil, dest = '' )
: get( path, header = nil ) {|str| .... }
  gets data from "path" on connecting host.
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  Response body is written into "dest" by using "<<" method.
  This method returns Net::HTTPResponse object.

    # example
    response = http.get( '/index.html' )

  If called with block, give a part String of entity body.

: head( path, header = nil )
  gets only header from "path" on connecting host.
  "header" is a Hash like { 'Accept' => '*/*', ... }.
  This method returns a Net::HTTPResponse object.
  You can http header from this object like:

    response['content-length']   #-> '2554'
    response['content-type']     #-> 'text/html'
    response['Content-Type']     #-> 'text/html'
    response['CoNtEnT-tYpe']     #-> 'text/html'

: post( path, data, header = nil, dest = '' )
: post( path, data, header = nil ) {|str| .... }
  posts "data" (must be String) to "path".
  If the body exists, also gets entity body.
  Response body is written into "dest" by using "<<" method.
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  This method returns Net::HTTPResponse object.

  If called with block, gives a part of entity body string.

: new_get( path, header = nil ) {|req| .... }
  creates a new GET request object and gives it to the block.
  see also for Get class reference.

    # example
    http.new_get( '/~foo/bar.html' ) do |req|
      req['accept'] = 'text/html'
      response = req.dispatch
      p response['Content-Type']
      puts response.read_header
    end

: new_head( path, header = nil ) {|req| .... }
  creates a new HEAD request object and gives it to the block.
  see also Head class reference.

: new_post( path, header = nil ) {|req| .... }
  creates a new POST request object and gives it to the block.
  see also Post class reference.


= class Get, Head, Post

HTTP request class. This class wraps request header and entity path.
All "key" is case-insensitive.

== Methods

: self[ key ]
  returns header field for "key".

: dispatch   [only Get, Head]
  dispatches request.
  This method returns HTTPResponse object.

: dispatch( data = '' )        [only Post]
: dispatch {|adapter| .... }   [only Post]
  dispatches request. "data" is 

= class HTTPResponse

HTTP response class. This class wraps response header and entity.
All "key" is case-insensitive.

== Methods

: body
  the entity body. ("dest" argument for HTTP#get, post, put)

: self[ key ]
  returns header field for "key".
  for HTTP, value is a string like 'text/plain'(for Content-Type),
  '2045'(for Content-Length), 'bytes 0-1024/10024'(for Content-Range).
  Multiple header had be joined by HTTP1.1 scheme.

: self[ key ] = val
  set field value for "key".

: key?( key )
  true if key exists

: each {|name,value| .... }
  iterates for each field name and value pair

: code
  HTTP result code string. For example, '302'

: message
  HTTP result message. For example, 'Not Found'

: read_body( dest = '' )
: body( dest = '' )
  gets response body.
  It is written into "dest" using "<<" method.
  If this method is called twice or more, nothing will be done and
  returns first "dest".

: read_body {|str| .... }
: body {|str| .... }
  gets response body with block.


= Swithing Net::HTTP versions

You can use Net::HTTP 1.1 features by calling HTTP.old_implementation.
And calling Net::HTTP.new_implementation allows you to use 1.2 features
again.

  # example
  HTTP.start {|http1| ...(http1 has 1.2 features)... }

  HTTP.version_1_1
  HTTP.start {|http2| ...(http2 has 1.1 features)... }

  HTTP.version_1_2
  HTTP.start {|http3| ...(http3 has 1.2 features)... }

=end

require 'net/protocol'


module Net

  class HTTPBadResponse < StandardError; end


  class HTTP < Protocol

    protocol_param :port,         '80'

    HTTPVersion = '1.1'


    ###
    ### proxy
    ###

    class << self

      def Proxy( p_addr, p_port = nil )
        ::Net::NetPrivate::HTTPProxy.create_proxy_class(
            p_addr, p_port || self.port )
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


    ###
    ### for compatibility
    ###

    @@newimpl = true

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


    ###
    ### http operations
    ###

    def self.defrequest( nm, hasdest, hasdata )
      name = nm.id2name.downcase
      cname = nm.id2name
      lineno = __LINE__ + 2
      src = <<S

        def #{name}( path, #{hasdata ? 'data,' : ''}
                     u_header = nil #{hasdest ? ',dest = nil, &block' : ''} )
          resp = #{name}2( path,
                           #{hasdata ? 'data,' : ''}
                           u_header ) {|resp|
            resp.read_body( #{hasdest ? 'dest, &block' : ''} )
          }
          if @newimpl then
            resp
          else
            resp.value
            #{hasdest ? 'return resp, resp.body' : 'resp'}
          end
        end

        def #{name}2( path, #{hasdata ? 'data,' : ''}
                      u_header = nil )
          new_#{name}( path, u_header ) do |req|
            resp = req.dispatch#{hasdata ? '(data)' : ''}
            yield resp if block_given?
          end
        end

        def new_#{name}( path, u_header = nil, &block )
          common_oper ::Net::NetPrivate::#{cname}, path, u_header, &block
        end
S
      # puts src
      module_eval src, __FILE__, lineno
    end


    defrequest :Get,  true,  false
    defrequest :Head, false, false
    defrequest :Post, true,  true
    defrequest :Put,  false, true


    private


    def initialize( addr = nil, port = nil )
      super
      @command = ::Net::NetPrivate::Switch.new
      @curr_http_version = HTTPVersion
    end

    def connect( addr = @address, port = @port )
      @socket = type.socket_type.open( addr, port, @pipe )
    end

    def disconnect
      if @socket and not @socket.closed? then
        @socket.close
      end
      @socket = nil
    end

    def do_finish
    end


    def common_oper( reqc, path, u_header )
      req = nil

      @command.on
      if not @socket then
        start
      elsif @socket.closed? then
        @socket.reopen
      end

      req = reqc.new( @curr_http_version,
                      @socket, inihead,
                      edit_path(path), u_header )
      yield req if block_given?
      req.terminate
      @curr_http_version = req.http_version

      unless keep_alive? req, req.response then
        @socket.close
      end
      @command.off

      req.response
    end

    def inihead
      h = {}
      h['Host']       = address +
                        ((port == HTTP.port) ? '' : ":#{port}")
      h['Connection'] = 'Keep-Alive'
      h['Accept']     = '*/*'
      h
    end

    def keep_alive?( request, response )
      if response.key? 'connection' then
        if /keep-alive/i === response['connection'] then
          return true
        end
      elsif response.key? 'proxy-connection' then
        if /keep-alive/i === response['proxy-connection'] then
          return true
        end
      elsif request.key? 'Connection' then
        if /keep-alive/i === request['Connection'] then
          return true
        end
      else
        if @curr_http_version == '1.1' then
          return true
        end
      end

      false
    end

  end

  HTTPSession = HTTP



  module NetPrivate

  class Switch
    def initialize
      @critical = false
    end

    def critical?
      @critical
    end

    def on
      @critical = true
    end

    def off
      @critical = false
    end
  end

  module HTTPProxy

    class << self

      def create_proxy_class( p_addr, p_port )
        klass = Class.new( HTTP )
        klass.module_eval {
          include HTTPProxy
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
  
    def connect( addr = nil, port = nil )
      super @proxy_address, @proxy_port
    end

    def edit_path( path )
      'http://' + address + (port == HTTP.port ? '' : ":#{port}") + path
    end
  
  end

  end   # net private


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



  module NetPrivate


  ###
  ### request
  ###

  class HTTPRequest

    def initialize( httpver, sock, inith, path, uhead )
      @http_version = httpver
      @socket = sock
      @path = path
      @response = nil

      @u_header = inith
      return unless uhead
      tmp = {}
      uhead.each do |k,v|
        key = canonical(k)
        if tmp.key? key then
          $stderr.puts "WARNING: duplicated HTTP header: #{k}" if $VERBOSE
          tmp[ key ] = v.strip
        end
      end
      @u_header.update tmp
    end

    attr_reader :http_version

    attr_reader :path
    attr_reader :response

    def inspect
      "\#<#{type}>"
    end

    def []( key )
      @u_header[ canonical key ]
    end

    def []=( key, val )
      @u_header[ canonical key ] = val
    end

    def key?( key )
      @u_header.key? canonical(key)
    end

    def delete( key )
      @u_header.delete canonical(key)
    end

    def each( &block )
      @u_header.each( &block )
    end

    def each_key( &block )
      @u_header.each_key( &block )
    end

    def each_value( &block )
      @u_header.each_value( &block )
    end


    def terminate
      @response.terminate
    end


    private

    def canonical( k )
      k.split('-').collect {|i| i.capitalize }.join('-')
    end


    # write request & header

    def do_dispatch
      if @response then
        raise IOError, "#{type}\#dispatch called twice"
      end
      yield
      @response = read_response
    end

    def request( req )
      @socket.writeline req
      @u_header.each do |n,v|
        @socket.writeline n + ': ' + v
      end
      @socket.writeline ''
    end

    # read response & header

    def read_response
      resp = rdresp0
      resp = rdresp0 while ContinueCode === resp
      resp
    end

    def rdresp0
      resp = get_resline

      while true do
        line = @socket.readline
        break if line.empty?

        m = /\A([^:]+):\s*/.match( line )
        unless m then
          raise HTTPBadResponse, 'wrong header line format'
        end
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
      m = /\AHTTP\/(\d+\.\d+)?\s+(\d\d\d)\s*(.*)\z/i.match( str )
      unless m then
        raise HTTPBadResponse, "wrong status line: #{str}"
      end
      @http_version = m[1]
      status  = m[2]
      discrip = m[3]
      
      HTTPResponse.new( status, discrip, @socket, type::HAS_BODY )
    end

  end

  class Get < HTTPRequest

    HAS_BODY = true

    def dispatch
      do_dispatch {
        request sprintf('GET %s HTTP/%s', @path, @http_version)
      }
    end

  end

  class Head < HTTPRequest

    HAS_BODY = false

    def dispatch
      do_dispatch {
        request sprintf('HEAD %s HTTP/%s', @path, @http_version)
      }
    end
  
  end

  class HTTPRequestWithData < HTTPRequest

    def dispatch( str = nil )
      check_arg str, block_given?

      if block_given? then
        ac = Accumulator.new
        yield ac              # must be yield, not block.call
        data = ac.terminate
      else
        data = str
      end

      do_dispatch {
        @u_header['Content-Length'] = data.size.to_s
        @u_header.delete 'Transfer-Encoding'
        request sprintf('%s %s HTTP/%s', type::METHOD, @path, @http_version)
        @socket.write data
      }
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

  class Post < HTTPRequestWithData

    HAS_BODY = true

    METHOD = 'POST'
  
  end

  class Put < HTTPRequestWithData

    HAS_BODY = true

    METHOD = 'PUT'
  
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



  ###
  ### response
  ###

  class HTTPResponse < Response

    HTTPCODE_CLASS_TO_OBJ = {
      '1' => HTTPInformationCode,
      '2' => HTTPSuccessCode,
      '3' => HTTPRedirectionCode,
      '4' => HTTPClientErrorCode,
      '5' => HTTPServerErrorCode
    }

    HTTPCODE_TO_OBJ = {
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


    def initialize( status, msg, sock, be )
      code = HTTPCODE_TO_OBJ[status] ||
             HTTPCODE_CLASS_TO_OBJ[status[0,1]] ||
             UnknownCode
      super code, status, msg
      @socket = sock
      @body_exist = be

      @header = {}
      @body = nil
      @read = false
    end

    def inspect
      "#<#{type} #{code}>"
    end

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

    def value
      unless SuccessCode === self then
        error! self
      end
    end


    # header (for backward compatibility)

    def read_header
      self
    end

    alias header read_header
    alias response read_header


    # body

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


    # internal use only
    def terminate
      read_body
    end


    private


    def read_body_0( dest )
      if chunked? then
        read_chunked dest
      else
        clen = content_length
        if clen then
          @socket.read clen, dest
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
        unless m then
          raise HTTPBadResponse, "wrong chunk size line: #{line}"
        end
        len = m[0].hex
        break if len == 0
        @socket.read( len, dest ); total += len
        @socket.read 2   # \r\n
      end
      until @socket.readline.empty? do
        ;
      end
    end

    def content_length
      if @header.key? 'content-length' then
        m = /\d+/.match( @header['content-length'] )
        unless m then
          raise HTTPBadResponse, 'wrong Content-Length format'
        end
        m[0].to_i
      else
        nil
      end
    end

    def chunked?
      tmp = @header['transfer-encoding']
      tmp and /\bchunked\b/i === tmp
     end

    def range_length
      if @header.key? 'content-range' then
        m = %r<bytes\s+(\d+)-(\d+)/\d+>.match( @header['content-range'] )
        unless m then
          raise HTTPBadResponse, 'wrong Content-Range format'
        end
        l = m[2].to_i
        u = m[1].to_i
        if l > u then
          nil
        else
          u - l
        end
      else
        nil
      end
    end

    def stream_check
      if @socket.closed? then
        raise IOError, 'try to read body out of block'
      end
    end

    def procdest( dest, block )
      if dest and block then
        raise ArgumentError,
              'both of arg and block are given for HTTP method'
      end
      if block then
        ReadAdapter.new block
      else
        dest or ''
      end
    end

  end


  end   # module Net::NetPrivate

end   # module Net

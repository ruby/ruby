=begin

= net/http.rb version 1.1.33

maintained by Minero Aoki <aamine@dp.u-netsurf.ne.jp>
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
  This method returns Net::HTTPResponse object, and "dest".

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
  This method returns a Net::HTTPResponse object.
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
  This method returns Net::HTTPResponse object and "dest".

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
  Net::HTTPResponse object

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


  class HTTP < Protocol

    protocol_param :port,         '80'
    protocol_param :command_type, '::Net::NetPrivate::HTTPCommand'


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
        setimplv i
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
    ### 1.2 implementation
    ###

    @@newimpl = false

    #class << self

      def self.version_1_2
        @@newimpl = true
      end

      def self.version_1_1
        @@newimpl = false
      end

      #private

      def self.setimplv( obj )
        f = @@newimpl
        obj.instance_eval { @newimpl = f }
      end

    #end


    ###
    ### http operations
    ###

    def get( path, u_header = nil, dest = nil, &block )
      resp = get2( path, u_header ) {|f| f.body( dest, &block ) }
      if @newimpl then
        resp
      else
        resp.value
        return resp, resp.body
      end
    end

    def get2( path, u_header = nil, &block )
      common_oper( u_header, true, block ) {|uh|
        @command.get edit_path(path), uh
      }
    end


    def head( path, u_header = nil )
      resp = head2( path, u_header )
      unless @newimpl then
        resp.value
      end
      resp
    end

    def head2( path, u_header = nil, &block )
      common_oper( u_header, false, block ) {|uh|
        @command.head edit_path(path), uh
      }
    end


    def post( path, data, u_header = nil, dest = nil, &block )
      resp = post2( path, data, u_header ) {|f| f.body( dest, &block ) }
      if @newimpl then
        resp
      else
        resp.value
        return resp, resp.body
      end
    end

    def post2( path, data, u_header = nil, &block )
      common_oper( u_header, true, block ) {|uh|
        @command.post edit_path(path), uh, data
      }
    end


    # not tested because I could not setup apache  (__;;;
    def put( path, src, u_header = nil )
      resp = put2( path, src, u_header ) {|f| f.body }
      if @newimpl then
        resp
      else
        resp.value
        return resp, resp.body
      end
    end

    def put2( path, src, u_header = nil, &block )
      common_oper( u_header, true, block ) {|uh|
        @command.put path, uh, src
      }
    end


    private


    def do_start
      @seems_1_0 = false
    end

    def do_finish
    end


    def common_oper( u_header, body_exist, block )
      header = procheader( u_header )
      recv = err = nil

      connecting( header ) {
        recv = HTTPResponseReceiver.new( @command, body_exist )
        yield header
        begin
          block.call recv if block
        rescue Exception => err
          ;
        end
        recv.terminate

        recv.response
      }
      raise err if err

      recv.response
    end

    def connecting( header )
      if not @socket then
        header['Connection'] = 'close'
        start
      elsif @socket.closed? then
        @socket.reopen
      end
      if @seems_1_0 then
        header['Connection'] = 'close'
      end

      resp = yield
      if @command.http_version == '1.0' then
        @seems_1_0 = true
      end

      unless keep_alive? resp then
        if @socket.closed? then
          @seems_1_0 = true
        else
          @socket.close
        end
      end
    end

    def keep_alive?( resp )
      /close/i === resp['connection'].to_s            and return false
      /close/i === resp['proxy-connection'].to_s      and return false
      @seems_1_0                                      and return false

      /keep-alive/i === resp['connection'].to_s       and return true
      /keep-alive/i === resp['proxy-connection'].to_s and return true
      @command.http_version == '1.1'                  and return true

      false
    end

    def procheader( h )
      ret = {}
      ret[ 'Host' ]       = address + ((port == HTTP.port) ? '' : ":#{port}")
      ret[ 'Accept' ]     = '*/*'

      return ret unless h
      tmp = {}
      h.each do |k,v|
        key = k.split('-').collect {|i| i.capitalize }.join('-')
        if tmp[key] then
          $stderr.puts "'#{key}' http header appered twice" if $VERBOSE
        end
        tmp[key] = v
      end
      ret.update tmp

      ret
    end

  end

  HTTPSession = HTTP


  module NetPrivate

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
      'http://' + address + (port == type.port ? '' : ":#{port}") + path
    end
  
  end

  end   # net private



  class HTTPResponseReceiver

    def initialize( command, body_exist )
      @command = command
      @body_exist = body_exist
      @header = @body = nil
    end

    def inspect
      "#<#{type}>"
    end

    def read_header
      unless @header then
        stream_check
        @header = @command.get_response
      end
      @header
    end

    alias header read_header
    alias response read_header

    def read_body( dest = nil, &block )
      unless @body then
        read_header

        to = procdest( dest, block )
        stream_check

        if @body_exist and @header.code_type.body_exist? then
          @command.get_body @header, to
          @header.body = @body = to
        else
          @command.no_body
          @header.body = nil
          @body = 1
        end
      end
      @body == 1 ? nil : @body
    end

    alias body read_body
    alias entity read_body

    def terminate
      read_header
      read_body
      @command = nil
    end


    private

    def stream_check
      unless @command then
        raise IOError, 'receiver was used out of block'
      end
    end

    def procdest( dest, block )
      if dest and block then
        raise ArgumentError,
          'both of arg and block are given for HTTP method'
      end
      if block then
        NetPrivate::ReadAdapter.new block
      else
        dest or ''
      end
    end

  end

  HTTPReadAdapter = HTTPResponseReceiver


  class HTTPResponse < Response

    def initialize( code_type, code, msg )
      super
      @data = {}
      @body = nil
    end

    attr_accessor :body

    def inspect
      "#<#{type.name} #{code}>"
    end

    def []( key )
      @data[ key.downcase ]
    end

    def []=( key, val )
      @data[ key.downcase ] = val
    end

    def each( &block )
      @data.each( &block )
    end

    def each_key( &block )
      @data.each_key( &block )
    end

    def each_value( &block )
      @data.each_value( &block )
    end

    def delete( key )
      @data.delete key.downcase
    end

    def key?( key )
      @data.key? key.downcase
    end

    def to_hash
      @data.dup
    end

    def value
      unless SuccessCode === self then
        error! self
      end
    end

  end


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


  class HTTPCommand < Command

    HTTPVersion = '1.1'

    def initialize( sock )
      @http_version = HTTPVersion
      super sock
    end

    attr_reader :http_version

    def inspect
      "#<Net::HTTPCommand>"
    end


    ###
    ### request
    ###

    public

    def get( path, u_header )
      return unless begin_critical
      request sprintf('GET %s HTTP/%s', path, HTTPVersion), u_header
    end
      
    def head( path, u_header )
      return unless begin_critical
      request sprintf('HEAD %s HTTP/%s', path, HTTPVersion), u_header
    end

    def post( path, u_header, data )
      return unless begin_critical
      u_header[ 'Content-Length' ] = data.size.to_s
      request sprintf('POST %s HTTP/%s', path, HTTPVersion), u_header
      @socket.write data
    end

    def put( path, u_header, src )
      return unless begin_critical
      request sprintf('PUT %s HTTP/%s', path, HTTPVersion), u_header
      @socket.write_bin src
    end

    # def delete

    # def trace

    # def options

    def quit
    end


    private

    def request( req, u_header )
      @socket.writeline req
      u_header.each do |n,v|
        @socket.writeline n + ': ' + v
      end
      @socket.writeline ''
    end


    ###
    ### response line & header
    ###

    public

    def get_response
      resp = get_resp0
      resp = get_resp0 while ContinueCode === resp
      resp
    end


    private

    def get_resp0
      resp = get_reply

      while true do
        line = @socket.readuntil( "\n", true )   # ignore EOF
        line.sub!( /\s+\z/, '' )                 # don't use chop!
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

    def get_reply
      str = @socket.readline
      m = /\AHTTP\/(\d+\.\d+)?\s+(\d\d\d)\s*(.*)\z/i.match( str )
      unless m then
        raise HTTPBadResponse, "wrong status line: #{str}"
      end
      @http_version = m[1]
      status  = m[2]
      discrip = m[3]
      
      code = HTTPCODE_TO_OBJ[status] ||
             HTTPCODE_CLASS_TO_OBJ[status[0,1]] ||
             UnknownCode
      HTTPResponse.new( code, status, discrip )
    end

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


    ###
    ### body
    ###

    public

    def get_body( resp, dest )
      if chunked? resp then
        read_chunked dest
      else
        clen = content_length( resp )
        if clen then
          @socket.read clen, dest, true
        else
          clen = range_length( resp )
          if clen then
            @socket.read clen, dest
          else
            @socket.read_all dest
          end
        end
      end
      end_critical
    end

    def no_body
      end_critical
    end


    private

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

    def content_length( resp )
      if resp.key? 'content-length' then
        m = /\d+/.match( resp['content-length'] )
        unless m then
          raise HTTPBadResponse, 'wrong Content-Length format'
        end
        m[0].to_i
      else
        nil
      end
    end

    def chunked?( resp )
      tmp = resp['transfer-encoding']
      tmp and /(?:\A|\s+)chunked(?:\s+|\z)/i === tmp
     end

    def range_length( resp )
      if resp.key? 'content-range' then
        m = %r<bytes\s+(\d+)-(\d+)/\d+>.match( resp['content-range'] )
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

  end


  end   # module Net::NetPrivate

end   # module Net

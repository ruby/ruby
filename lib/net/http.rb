=begin

= net/http.rb version 1.1.29

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
  if proxy_addr is given, this method is equals to
  Net::HTTP::Proxy(proxy_addr,proxy_port).

: start( address = 'localhost', port = 80, proxy_addr = nil, proxy_port = nil )
: start( address = 'localhost', port = 80, proxy_addr = nil, proxy_port = nil ) {|http| .... }
  is equals to Net::HTTP.new( address, port, proxy_addr, proxy_port ).start(&block)

: port
  HTTP default port, 80


== Methods

: start
: start {|http| .... }
  creates a new Net::HTTP object and starts HTTP session.

  When this method is called with block, gives HTTP object to block
  and close HTTP session after block call finished.

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
    rescue Net::ProtoRetriableError
      response = $!.data
      ...
    end

: head( path, header = nil )
  get only header from "path" on connecting host.
  "header" is a Hash like { 'Accept' => '*/*', ... }.
  This method returns Net::HTTPResponse object.
  You can http header from this object like:

    response['content-length']   #-> '2554'
    response['content-type']     #-> 'text/html'
    response['Content-Type']     #-> 'text/html'
    response['CoNtEnT-tYpe']     #-> 'text/html'

: post( path, data, header = nil, dest = '' )
: post( path, data, header = nil ) {|str| .... }
  post "data"(must be String now) to "path".
  If body exists, also get entity body.
  It is written to "dest" by using "<<" method.
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  This method returns Net::HTTPResponse object and "dest".

  If called with block, gives a part String of entity body.

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
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
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
  post "data"(must be String now) to "path".
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


= class HTTPResponse

HTTP response object.
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
  true if key is exist

: each {|name,value| .... }
  iterate for each field name and value pair

: code
  HTTP result code string. For example, '302'

: message
  HTTP result message. For example, 'Not Found'


= class HTTPResponseReceiver

== Methods

: header
: response
  Net::HTTPResponse object

: body( dest = '' )
: entity( dest = '' )
  entity body. A body is written to "dest" using "<<" method.

: body {|str| ... }
  gets entity body with block.
  If this method is called twice, block is not executed and
  returns first "dest".


= http.rb version 1.2 features

You can use these 1.2 features by calling method
Net::HTTP.new_implementation. Or you want to use 1.1 feature,
call Net::HTTP.old_implementation.

Now old_impl is default and if new_impl was called then Net::HTTP
changes self into new implementation.  In 1.2, new_impl is default
and if old_impl was called then changes self into old implementation.

== Warning!!!

You can call new_implementation/old_implementation any times
but CANNOT call both of them at the same time.
You must use one implementation in one application (process).

== Method

: get( path, u_header = nil )
: get( path, u_header = nil ) {|str| .... }
get document from "path" and returns HTTPResponse object.

: head( path, u_header = nil )
get only document header from "path" and returns HTTPResponse object.

: post( path, data, u_header = nil )
: post( path, data, u_header = nil ) {|str| .... }
post "data" to "path" entity and get document,
then returns HTTPResponse object.

=end

require 'net/protocol'


module Net

  class HTTPBadResponse < StandardError; end


  class HTTP < Protocol

    protocol_param :port,         '80'
    protocol_param :command_type, '::Net::NetPrivate::HTTPCommand'

    class << self

      alias orig_new new

      def new( address = nil, port = nil, p_addr = nil, p_port = nil )
        (p_addr ? self::Proxy(p_addr, p_port) : self).orig_new( address, port )
      end

      def start( address = nil, port = nil, p_addr = nil, p_port = nil, &block )
        new( address, port, p_addr, p_port ).start( &block )
      end

    end

    @new_impl = false

    def HTTP.new_implementation
      return if @new_impl
      @new_impl = true
      module_eval %^

      undef head
      alias head head2

      undef get

      def get( path, u_header = nil, dest = nil, &block )
        get2( path, u_header ) {|f| f.body( dest, &block ) }
      end

      undef post

      def post( path, data, u_header = nil, dest = nil, &block )
        post2( path, data, u_header ) {|f| f.body( dest, &block ) }
      end

      undef put

      def put( path, src, u_header = nil )
        put2( path, src, u_header ) {|f| f.body }
      end

      ^
    end

    def HTTP.old_implementation
      if @new_impl then
        raise RuntimeError, "http.rb is already switched to new implementation"
      end
    end
      

    def get( path, u_header = nil, dest = nil, &block )
      resp = get2( path, u_header ) {|f| dest = f.body( dest, &block ) }
      resp.value
      return resp, dest
    end

    def get2( path, u_header = nil, &block )
      connecting( u_header ) {|uh|
        @command.get edit_path(path), uh
        receive true, block
      }
    end


    def head( path, u_header = nil )
      resp = head2( path, u_header )
      resp.value
      resp
    end

    def head2( path, u_header = nil, &block )
      connecting( u_header ) {|uh|
        @command.head edit_path(path), uh
        receive false, block
      }
    end


    def post( path, data, u_header = nil, dest = nil, &block )
      resp = post2( path, data, u_header ) {|f|
                    dest = f.body( dest, &block ) }
      resp.value
      return resp, dest
    end

    def post2( path, data, u_header = nil, &block )
      connecting( u_header ) {|uh|
        @command.post edit_path(path), uh, data
        receive true, block
      }
    end


    # not tested because I could not setup apache  (__;;;
    def put( path, src, u_header = nil )
      resp = put2( path, src, u_header ) {|f| f.body }
      resp.value
      return resp, resp.body
    end

    def put2( path, src, u_header = nil, &block )
      connecting( u_header ) {|uh|
        @command.put path, uh, src
        receive true, block
      }
    end


    private


    def connecting( u_header )
      u_header = procheader( u_header )
      if not @socket then
        u_header['Connection'] = 'close'
        start
      elsif @socket.closed? then
        @socket.reopen
      end

      resp = yield( u_header )

      unless keep_alive? u_header, resp then
        @socket.close
      end

      resp
    end

    def keep_alive?( header, resp )
      if resp.key? 'connection' then
        if /keep-alive/i === resp['connection'] then
          return true
        end
      elsif resp.key? 'proxy-connection' then
        if /keep-alive/i === resp['proxy-connection'] then
          return true
        end
      elsif header.key? 'Connection' then
        if /keep-alive/i === header['Connection'] then
          return true
        end
      else
        if @command.http_version == '1.1' then
          return true
        end
      end

      false
    end

    def procheader( h )
      return( {} ) unless h
      new = {}
      h.each do |k,v|
        arr = k.split('-')
        arr.each{|i| i.capitalize! }
        new[ arr.join('-') ] = v
      end
    end


    def receive( body_exist, block )
      recv = HTTPResponseReceiver.new( @command, body_exist )
      block.call recv if block
      recv.terminate
      recv.header
    end


    # called when connecting
    def do_finish
      unless @socket.closed? then
        head2 '/', { 'Connection' => 'close' }
      end
    end

    
    def edit_path( path )
      path
    end

    def HTTP.Proxy( p_addr, p_port = nil )
      klass = super
      klass.module_eval( <<'SRC', 'http.rb', __LINE__ + 1 )
        def edit_path( path )
          'http://' + address +
              (@port == HTTP.port ? '' : ":#{@port}") +
              path
        end
SRC
      klass
    end

  end

  HTTPSession = HTTP


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

    def body( dest = nil, &block )
      unless @body then
        self.read_header

        to = procdest( dest, block )
        stream_check
        if @body_exist and header.code_type.body_exist? then
          @command.get_body header, to
          header.body = @body = to
        else
          @command.no_body
          header.body = nil
          @body = 1
        end
      end
      @body == 1 ? nil : @body
    end

    alias entity body

    def terminate
      header
      body
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

      @in_header = {}
      @in_header[ 'Host' ] = sock.addr +
                             ((sock.port == HTTP.port) ? '' : ":#{sock.port}")
      @in_header[ 'Connection' ] = 'Keep-Alive'
      @in_header[ 'Accept' ]     = '*/*'

      super sock
    end

    attr_reader :http_version

    def inspect
      "#<Net::HTTPCommand>"
    end


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


    def get_response
      resp = get_reply
      resp = get_reply while ContinueCode === resp

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


    def get_body( resp, dest )
      if chunked? resp then
        read_chunked( dest, resp )
      else
        clen = content_length( resp )
        if clen then
          @socket.read clen, dest
        else
          clen = range_length( resp )
          if clen then
            @socket.read clen, dest
          else
            tmp = resp['connection']
            if tmp and /close/i === tmp then
              @socket.read_all dest
            else
              tmp = resp['proxy-connection']
              if tmp and /close/i === tmp then
                @socket.read_all dest
              end
            end
          end
        end
      end
      end_critical
    end

    def no_body
      end_critical
    end


    private


    def request( req, u_header )
      @socket.writeline req
      if u_header then
        header = @in_header.dup.update( u_header )
      else
        header = @in_header
      end
      header.each do |n,v|
        @socket.writeline n + ': ' + v
      end
      @socket.writeline ''
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

    def read_chunked( ret, header )
      len = nil
      total = 0

      while true do
        line = @socket.readline
        m = /[0-9a-hA-H]+/.match( line )
        unless m then
          raise HTTPBadResponse, "wrong chunk size line: #{line}"
        end
        len = m[0].hex
        break if len == 0
        @socket.read( len, ret ); total += len
        @socket.read 2   # \r\n
      end
      until @socket.readline.empty? do
        ;
      end
    end

    
    def content_length( header )
      if header.key? 'content-length' then
        m = /\d+/.match( header['content-length'] )
        unless m then
          raise HTTPBadResponse, 'wrong Content-Length format'
        end
        m[0].to_i
      else
        nil
      end
    end

    def chunked?( header )
      str = header[ 'transfer-encoding' ]
      str and /(?:\A|\s+)chunked(?:\s+|\z)/i === str
    end

    def range_length( header )
      if header.key? 'content-range' then
        m = %r<bytes\s+(\d+)-(\d+)/\d+>.match( header['content-range'] )
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

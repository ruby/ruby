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
  execption object. (same in head/post)

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
      recv.body                  # read body and set recv.header.body
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

      def procdest( dest, block )
        if block then
          return NetPrivate::ReadAdapter.new( block ), nil
        else
          dest ||= ''
          return dest, dest
        end
      end

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
      klass.module_eval( <<SRC, 'http.rb', __LINE__ + 1 )
        def edit_path( path )
          'http://' + address +
              (@port == HTTP.port ? '' : ':' + @port.to_s) +
              path
        end
SRC
      klass
    end

  end

  HTTPSession = HTTP


  class HTTPResponse < Response

    def initialize( code_type, bexist, code, msg )
      super( code_type, code, msg )
      @data = {}
      @http_body_exist = bexist
      @body = nil
    end

    attr_reader :http_body_exist
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


  HTTPSuccessCode                   = SuccessCode.mkchild
  HTTPRetriableCode                 = RetriableCode.mkchild
  HTTPFatalErrorCode                = FatalErrorCode.mkchild


  HTTPSwitchProtocol                = HTTPSuccessCode.mkchild

  HTTPOK                            = HTTPSuccessCode.mkchild
  HTTPCreated                       = HTTPSuccessCode.mkchild
  HTTPAccepted                      = HTTPSuccessCode.mkchild
  HTTPNonAuthoritativeInformation   = HTTPSuccessCode.mkchild
  HTTPNoContent                     = HTTPSuccessCode.mkchild
  HTTPResetContent                  = HTTPSuccessCode.mkchild
  HTTPPartialContent                = HTTPSuccessCode.mkchild

  HTTPMultipleChoice                = HTTPRetriableCode.mkchild
  HTTPMovedPermanently              = HTTPRetriableCode.mkchild
  HTTPMovedTemporarily              = HTTPRetriableCode.mkchild
  HTTPNotModified                   = HTTPRetriableCode.mkchild
  HTTPUseProxy                      = HTTPRetriableCode.mkchild
  
  HTTPBadRequest                    = HTTPRetriableCode.mkchild
  HTTPUnauthorized                  = HTTPRetriableCode.mkchild
  HTTPPaymentRequired               = HTTPRetriableCode.mkchild
  HTTPForbidden                     = HTTPFatalErrorCode.mkchild
  HTTPNotFound                      = HTTPFatalErrorCode.mkchild
  HTTPMethodNotAllowed              = HTTPFatalErrorCode.mkchild
  HTTPNotAcceptable                 = HTTPFatalErrorCode.mkchild
  HTTPProxyAuthenticationRequired   = HTTPRetriableCode.mkchild
  HTTPRequestTimeOut                = HTTPFatalErrorCode.mkchild
  HTTPConflict                      = HTTPFatalErrorCode.mkchild
  HTTPGone                          = HTTPFatalErrorCode.mkchild
  HTTPLengthRequired                = HTTPFatalErrorCode.mkchild
  HTTPPreconditionFailed            = HTTPFatalErrorCode.mkchild
  HTTPRequestEntityTooLarge         = HTTPFatalErrorCode.mkchild
  HTTPRequestURITooLarge            = HTTPFatalErrorCode.mkchild
  HTTPUnsupportedMediaType          = HTTPFatalErrorCode.mkchild

  HTTPNotImplemented                = HTTPFatalErrorCode.mkchild
  HTTPBadGateway                    = HTTPFatalErrorCode.mkchild
  HTTPServiceUnavailable            = HTTPFatalErrorCode.mkchild
  HTTPGatewayTimeOut                = HTTPFatalErrorCode.mkchild
  HTTPVersionNotSupported           = HTTPFatalErrorCode.mkchild


  class HTTPResponseReceiver

    def initialize( command, body_exist )
      @command = command
      @body_exist = body_exist
      @header = @body = nil
    end

    def inspect
      "#<#{type}>"
    end

    def header
      unless @header then
        stream_check
        @header = @body_exist ? @command.get_response :
                                @command.get_response_no_body
      end
      @header
    end
    alias response header

    def body( dest = nil, &block )
      dest, ret = HTTP.procdest( dest, block )
      unless @body then
        stream_check
        @body = @command.get_body( header, dest )
      end
      @body
    end
    alias entity body

    def terminate
      header
      body if @body_exist
      @command = nil
    end

    private

    def stream_check
      unless @command then
        raise IOError, 'receiver was used out of block'
      end
    end
  
  end

  HTTPReadAdapter = HTTPResponseReceiver



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
      resp.body = dest

      if resp.http_body_exist then
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
      end
      end_critical

      dest
    end

    def get_response_no_body
      resp = get_response
      end_critical
      resp
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


    HTTPCODE_TO_OBJ = {
      '100' => [ContinueCode,                        false],
      '100' => [HTTPSwitchProtocol,                  false],

      '200' => [HTTPOK,                              true],
      '201' => [HTTPCreated,                         true],
      '202' => [HTTPAccepted,                        true],
      '203' => [HTTPNonAuthoritativeInformation,     true],
      '204' => [HTTPNoContent,                       false],
      '205' => [HTTPResetContent,                    false],
      '206' => [HTTPPartialContent,                  true],

      '300' => [HTTPMultipleChoice,                  true],
      '301' => [HTTPMovedPermanently,                true],
      '302' => [HTTPMovedTemporarily,                true],
      '303' => [HTTPMovedPermanently,                true],
      '304' => [HTTPNotModified,                     false],
      '305' => [HTTPUseProxy,                        false],

      '400' => [HTTPBadRequest,                      true],
      '401' => [HTTPUnauthorized,                    true],
      '402' => [HTTPPaymentRequired,                 true],
      '403' => [HTTPForbidden,                       true],
      '404' => [HTTPNotFound,                        true],
      '405' => [HTTPMethodNotAllowed,                true],
      '406' => [HTTPNotAcceptable,                   true],
      '407' => [HTTPProxyAuthenticationRequired,     true],
      '408' => [HTTPRequestTimeOut,                  true],
      '409' => [HTTPConflict,                        true],
      '410' => [HTTPGone,                            true],
      '411' => [HTTPFatalErrorCode,                  true],
      '412' => [HTTPPreconditionFailed,              true],
      '413' => [HTTPRequestEntityTooLarge,           true],
      '414' => [HTTPRequestURITooLarge,              true],
      '415' => [HTTPUnsupportedMediaType,            true],

      '500' => [HTTPFatalErrorCode,                  true],
      '501' => [HTTPNotImplemented,                  true],
      '502' => [HTTPBadGateway,                      true],
      '503' => [HTTPServiceUnavailable,              true],
      '504' => [HTTPGatewayTimeOut,                  true],
      '505' => [HTTPVersionNotSupported,             true]
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
      
      klass, bodyexist = HTTPCODE_TO_OBJ[status] || [UnknownCode, true]
      HTTPResponse.new( klass, bodyexist, status, discrip )
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
      if str and /(?:\A|\s+)chunked(?:\s+|\z)/i === str then
        true
      else
        false
      end
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

=begin

= net/http.rb

maintained by Minero Aoki <aamine@dp.u-netsurf.ne.jp>
This file is derived from "http-access.rb".

This library is distributed under the terms of the Ruby license.
You can freely distribute/modify this library.

=end

require 'net/protocol'


module Net

  class HTTPBadResponse < StandardError; end

=begin

= class HTTP

== Class Methods

: new( address = 'localhost', port = 80 )
  creates a new Net::HTTP object.

: start( address = 'localhost', port = 80 )
: start( address = 'localhost', port = 80 ) {|http| .... }
  equals to Net::HTTP.new( address, port ).start

: port
  HTTP default port, 80

: command_type
  Command class for Net::HTTP, HTTPCommand

== Methods

: start
: start {|http| .... }
  creates a new Net::HTTP object and starts HTTP session.

  When this method is called as iterator, gives HTTP object to block
  and close HTTP session after block call finished.

: get( path, header = nil, dest = '' )
: get( path, header = nil ) {|str| .... }
  get data from "path" on connecting host.
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  Data is written to "dest" by using "<<" method.
  This method returns Net::HTTPResponse object and "dest".

  If called as iterator, give a part String of entity body.

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

  If called as iterator, gives a part String of entity body.

: get2( path, header = nil ) {|adapter| .... }
  send GET request for "path".
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  This method gives HTTPReadAdapter object to block.

: head2( path, header = nil )
  send HEAD request for "path".
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  The difference between "head" method is that
  "head2" does not raise exceptions.

: post2( path, data, header = nil ) {|adapter| .... }
  post "data"(must be String now) to "path".
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  This method gives HTTPReadAdapter object to block.


= class HTTPResponse

== Methods

HTTP response object.
All "key" is case-insensitive.

: code
  HTTP result code. For example, '302'

: message
  HTTP result message. For example, 'Not Found'

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


= class HTTPReadAdapter

== Methods

: header
: response
  Net::HTTPResponse object

: body( dest = '' )
: entity( dest = '' )
  entity body. A body is written to "dest" using "<<" method.

: body {|str| ... }
  get entity body by using iterator.
  If this method is called twice, block is not called and
  returns first "dest".

=end

  class HTTP < Protocol

    protocol_param :port,         '80'
    protocol_param :command_type, '::Net::HTTPCommand'

    def HTTP.procdest( dest, block )
      if block then
        return ReadAdapter.new( block ), nil
      else
        dest ||= ''
        return dest, dest
      end
    end


    def get( path, u_header = nil, dest = nil, &block )
      resp = get2( path, u_header ) {|f| dest = f.body( dest, &block ) }
      resp.value
      return resp, dest
    end

    def get2( path, u_header = nil, &block )
      connecting( u_header, block ) {|uh|
        @command.get edit_path(path), uh
      }
    end


    def head( path, u_header = nil )
      resp = head2( path, u_header )
      resp.value
      resp
    end

    def head2( path, u_header = nil )
      connecting( u_header, nil ) {|uh|
        @command.head edit_path(path), uh
        @command.get_response_no_body
      }
    end


    def post( path, data, u_header = nil, dest = nil, &block )
      resp = post2( path, data, u_header ) {|f|
                    dest = f.body( dest, &block ) }
      resp.value
      return resp, dest
    end

    def post2( path, data, u_header = nil, &block )
      connecting( u_header, block ) {|uh|
        @command.post edit_path(path), uh, data
      }
    end


    # not tested because I could not setup apache  (__;;;
    def put( path, src, u_header = nil )
      ret = nil
      resp = put2( path, src, u_header ) {|f| ret = f.body }
      resp.value
      return resp, ret
    end

    def put2( path, src, u_header = nil, &block )
      connecting( u_header, block ) {|uh|
        @command.put path, uh, src
      }
    end


    private


    # called when connecting
    def do_finish
      unless @socket.closed? then
        head2 '/', { 'Connection' => 'close' }
      end
    end

    def connecting( u_header, ublock )
      u_header = procheader( u_header )
      if not @socket then
        u_header['Connection'] = 'close'
        start
      elsif @socket.closed? then
        @socket.reopen
      end

      resp = yield( u_header )
      if ublock then
        adapter = HTTPReadAdapter.new( @command )
        ublock.call adapter
        resp = adapter.off
      end
      
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

    
    def edit_path( path )
      path
    end

    class << self
      def Proxy( p_addr, p_port )
        klass = super
        klass.module_eval %-
          def edit_path( path )
            'http://' + address +
              (@port == #{self.port} ? '' : ':' + @port.to_s) + path
          end
        -
        klass
      end
    end

  end

  HTTPSession = HTTP


  class HTTPReadAdapter

    def initialize( command )
      @command = command
      @header = @body = nil
    end

    def header
      unless @header then
        @header = @command.get_response
      end
      @header
    end
    alias response header

    def body( dest = nil, &block )
      dest, ret = HTTP.procdest( dest, block )
      unless @body then
        @body = @command.get_body( response, dest )
      end
      @body
    end
    alias entity body

    def off
      body
      @command = nil
      @header
    end
  
  end


  class HTTPResponse < Response

    def initialize( code_type, bexist, code, msg )
      super( code_type, code, msg )
      @data = {}
      @http_body_exist = bexist
    end

    attr_reader :http_body_exist

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
      error! unless SuccessCode === self
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


  class HTTPCommand < Command

    HTTPVersion = '1.1'

    def initialize( sock )
      @http_version = HTTPVersion

      @in_header = {}
      if sock.port == HTTP.port
        @in_header[ 'Host' ] = sock.addr
      else
        @in_header[ 'Host' ] = sock.addr + ':' + sock.port
      end
      @in_header[ 'Connection' ] = 'Keep-Alive'
      @in_header[ 'Accept' ]     = '*/*'

      super sock
    end


    attr_reader :http_version

      
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


end   # module Net

=begin

= net/http.rb

maintained by Minero Aoki <aamine@dp.u-netsurf.ne.jp>
This file is derived from "http-access.rb".

This library is distributed under the terms of the Ruby license.
You can freely distribute/modify this library.

=end

require 'net/protocol'


module Net


class HTTPError < ProtocolError; end
class HTTPBadResponse < HTTPError; end


=begin

= class HTTP

== Class Methods

: new( address, port = 80 )
  create new HTTP object.

: port
  returns HTTP default port, 80

: command_type
  returns Command class, HTTPCommand


== Methods

: get( path, header = nil, dest = '' )
: get( path, header = nil ) {|str| .... }
  get data from "path" on connecting host.
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  Data is written to "dest" by using "<<" method.
  This method returns response header (Hash) and "dest".

  If called as iterator, give a part String of entity body.

: head( path, header = nil )
  get only header from "path" on connecting host.
  "header" is a Hash like { 'Accept' => '*/*', ... }.
  This method returns header as a Hash like

    { 'content-length' => 'Content-Length: 2554',
      'content-type'   => 'Content-Type: text/html',
      ... }

: post( path, data, header = nil, dest = '' )
: post( path, data, header = nil ) {|str| .... }
  post "data"(must be String now) to "path".
  If body exists, also get entity body.
  It is written to "dest" by using "<<" method.
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  This method returns response header (Hash) and "dest".

  If called as iterator, gives a part String of entity body.

: get2( path, header = nil ) {|writer| .... }
  send GET request for "path".
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  This method gives HTTPWriter object to block.

: get_body( dest = '' )
: get_body {|str| .... }
  gets entity body of forwarded 'get2' or 'post2' methods.
  Data is written in "dest" by using "<<" method.
  This method returns "dest".

  If called as iterator, gives a part String of entity body.

: post2( path, data, header = nil ) {|writer| .... }
  post "data"(must be String now) to "path".
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  This method gives HTTPWriter object to block.


= class HTTPWriter

== Methods

: header
  HTTP header.

: response
  ReplyCode object.

: entity( dest = '' )
: body( dest = '' )
  entity body.

: entity {|str| ... }
  get entity body by using iterator.
  If this method is called twice, block is not called.

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
      u_header = procheader( u_header )
      dest, ret = HTTP.procdest( dest, block )
      resp = nil
      connecting( u_header ) {
        @command.get edit_path(path), u_header
        resp = @command.get_response
        @command.get_body( resp, dest )
      }

      return resp['http-header'], ret
    end

    def get2( path, u_header = nil )
      u_header = procheader( u_header )
      connecting( u_header ) {
        @command.get edit_path(path), u_header
        tmp = HTTPWriter.new( @command )
        yield tmp
        tmp.off
      }
    end

=begin c
    def get_body( dest = '', &block )
      if block then
        dest = ReadAdapter.new( block )
      end
      @command.get_body @response, dest
      ensure_termination @u_header

      dest
    end
=end

    def head( path, u_header = nil )
      u_header = procheader( u_header )
      resp = nil
      connecting( u_header ) {
        @command.head( edit_path(path), u_header )
        resp = @command.get_response_no_body
      }

      resp['http-header']
    end

    def post( path, data, u_header = nil, dest = nil, &block )
      u_header = procheader( u_header )
      dest, ret = HTTP.procdest( dest, block )
      resp = nil
      connecting( u_header ) {
        @command.post edit_path(path), u_header, data
        resp = @command.get_response
        @command.get_body( resp, dest )
      }

      return resp['http-header'], ret
    end

    def post2( path, data, u_header = nil )
      u_header = procheader( u_header )
      connecting( u_header ) {
        @command.post edit_path(path), u_header, data
        tmp = HTTPWriter.new( @command )
        yield tmp
        tmp.off
      }
    end

    # not tested because I could not setup apache  (__;;;
    def put( path, src, u_header = nil )
      u_header = procheader( u_header )
      ret = ''
      connecting( u_header ) {
        @command.put path, u_header, src, dest
        resp = @comman.get_response
        @command.get_body( resp, ret )
      }

      return header, ret
    end


    private


=begin c
    def only_header( mid, path, u_header, data = nil )
      @u_header = u_header
      @response = nil
      connecting u_header
      if data then
        @command.send mid, edit_path(path), u_header, data
      else
        @command.send mid, edit_path(path), u_header
      end
      @response = @command.get_response
      @response['http-header']
    end
=end


    # called when connecting
    def do_finish
      unless @socket.closed? then
        begin
          @command.head '/', { 'Connection' => 'Close' }
        rescue EOFError
        end
      end
    end

    def connecting( u_header )
      if not @socket then
        u_header['Connection'] = 'Close'
        start
      elsif @socket.closed? then
        @socket.reopen
      end

      if iterator? then
        ret = yield
        ensure_termination u_header
        ret
      end
    end

    def ensure_termination( u_header )
      unless keep_alive? u_header and not @socket.closed? then
        @socket.close
      end
      @u_header = @response = nil
    end

    def keep_alive?( header )
      if str = header['Connection'] then
        if /\A\s*keep-alive/i === str then
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


  class HTTPWriter

    def initialize( command )
      @command = command
      @response = @header = @entity = nil
    end

    def response
      unless @resp then
        @resp = @command.get_response
      end
      @resp
    end

    def header
      unless @header then
        @header = response['http-header']
      end
      @header
    end

    def entity( dest = nil, &block )
      dest, ret = HTTP.procdest( dest, block )
      unless @entity then
        @entity = @command.get_body( response, dest )
      end
      @entity
    end
    alias body entity

    def off
      entity
      @command = nil
    end
  
  end


  class HTTPSwitchProtocol                < SuccessCode; end

  class HTTPOK                            < SuccessCode; end
  class HTTPCreated                       < SuccessCode; end
  class HTTPAccepted                      < SuccessCode; end
  class HTTPNonAuthoritativeInformation   < SuccessCode; end
  class HTTPNoContent                     < SuccessCode; end
  class HTTPResetContent                  < SuccessCode; end
  class HTTPPartialContent                < SuccessCode; end

  class HTTPMultipleChoice                < RetryCode; end
  class HTTPMovedPermanently              < RetryCode; end
  class HTTPMovedTemporarily              < RetryCode; end
  class HTTPNotModified                   < RetryCode; end
  class HTTPUseProxy                      < RetryCode; end
  
  class HTTPBadRequest                    < RetryCode; end
  class HTTPUnauthorized                  < RetryCode; end
  class HTTPPaymentRequired               < RetryCode; end
  class HTTPForbidden                     < FatalErrorCode; end
  class HTTPNotFound                      < FatalErrorCode; end
  class HTTPMethodNotAllowed              < FatalErrorCode; end
  class HTTPNotAcceptable                 < FatalErrorCode; end
  class HTTPProxyAuthenticationRequired   < RetryCode; end
  class HTTPRequestTimeOut                < FatalErrorCode; end
  class HTTPConflict                      < FatalErrorCode; end
  class HTTPGone                          < FatalErrorCode; end
  class HTTPLengthRequired                < FatalErrorCode; end
  class HTTPPreconditionFailed            < FatalErrorCode; end
  class HTTPRequestEntityTooLarge         < FatalErrorCode; end
  class HTTPRequestURITooLarge            < FatalErrorCode; end
  class HTTPUnsupportedMediaType          < FatalErrorCode; end

  class HTTPNotImplemented                < FatalErrorCode; end
  class HTTPBadGateway                    < FatalErrorCode; end
  class HTTPServiceUnavailable            < FatalErrorCode; end
  class HTTPGatewayTimeOut                < FatalErrorCode; end
  class HTTPVersionNotSupported           < FatalErrorCode; end


  class HTTPCommand < Command

    HTTPVersion = '1.1'

    def initialize( sock )
      @http_version = HTTPVersion

      @in_header = {}
      @in_header[ 'Host' ]       = sock.addr
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
      rep = get_reply
      rep = get_reply while ContinueCode === rep
      header = {}
      while true do
        line = @socket.readline
        break if line.empty?
        nm = /\A[^:]+/.match( line )[0].strip.downcase
        header[nm] = line
      end
      rep['http-header'] = header

      rep
    end

    def check_response( resp )
      reply_must resp, SuccessCode
    end

    def get_body( rep, dest )
      header = rep['http-header']

      if rep['body-exist'] then
        if chunked? header then
          read_chunked( dest, header )
        else
          if clen = content_length( header ) then
            @socket.read clen, dest
          else
            if false then # "multipart/byteranges" check should be done
            else
              if header['Connection'] and
                 /connection:\s*close/i === header['Connection'] then
                @socket.read_all dest
                @socket.close
              end
            end
          end
        end
      end
      end_critical
      reply_must rep, SuccessCode

      dest
    end

    def get_response_no_body
      resp = get_response
      end_critical
      reply_must resp, SuccessCode
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


    CODE_TO_CLASS = {
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
      '411' => [FatalErrorCode,                      true],
      '412' => [HTTPPreconditionFailed,              true],
      '413' => [HTTPRequestEntityTooLarge,           true],
      '414' => [HTTPRequestURITooLarge,              true],
      '415' => [HTTPUnsupportedMediaType,            true],

      '500' => [FatalErrorCode,                      true],
      '501' => [HTTPNotImplemented,                  true],
      '502' => [HTTPBadGateway,                      true],
      '503' => [HTTPServiceUnavailable,              true],
      '504' => [HTTPGatewayTimeOut,                  true],
      '505' => [HTTPVersionNotSupported,             true]
    }

    def get_reply
      str = @socket.readline
      unless /\AHTTP\/(\d+\.\d+)?\s+(\d\d\d)\s*(.*)\z/i === str then
        raise HTTPBadResponse, "wrong status line format: #{str}"
      end
      @http_version = $1
      status  = $2
      discrip = $3
      
      klass, bodyexist = CODE_TO_CLASS[status] || [UnknownCode, true]
      code = klass.new( status, discrip )
      code['body-exist'] = bodyexist
      code
    end

    def read_chunked( ret, header )
      line = nil
      len = nil
      total = 0

      while true do
        line = @socket.readline
        unless /[0-9a-hA-H]+/ === line then
          raise HTTPBadResponse, "chunk size not given"
        end
        len = $&.hex
        break if len == 0
        @socket.read( len, ret ); total += len
        @socket.read 2   # \r\n
      end
      while true do
        line = @socket.readline
        break if line.empty?
      end

      header.delete 'transfer-encoding'
      header[ 'content-length' ] = "Content-Length: #{total}"
    end

    
    def content_length( header )
      unless str = header[ 'content-length' ] then
        return nil
      end
      unless /\Acontent-length:\s*(\d+)/i === str then
        raise HTTPBadResponse, "content-length format error"
      end
      $1.to_i
    end

    def chunked?( header )
      if str = header[ 'transfer-encoding' ] then
        if /\Atransfer-encoding:\s*chunked/i === str then
          return true
        end
      end

      false
    end

  end


end   # module Net

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
  post "data"(must be String now) to "path" (and get entity body).
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  Data is written to "dest" by using "<<" method.
  This method returns response header (Hash) and "dest".

  If called as iterator, give a part String of entity body.

  ATTENTION: entity body could be empty

: get2( path, header = nil )
  send GET request for "path".
  "header" must be a Hash like { 'Accept' => '*/*', ... }.
  This method returns response header (Hash).

: get_body( dest = '' )
: get_body {|str| .... }
  gets entity body of forwarded 'get2' or 'post2' methods.
  Data is written in "dest" by using "<<" method.
  This method returns "dest".

  If called as iterator, give a part String of entity body.

=end

  class HTTP < Protocol

    protocol_param :port,         '80'
    protocol_param :command_type, '::Net::HTTPCommand'


    def get( path, u_header = nil, dest = nil, &block )
      u_header ||= {}
      if block then
        dest = ReadAdapter.new( block )
        ret = nil
      else
        dest = ret =  ''
      end
      resp = nil
      connecting( u_header ) {
        @command.get edit_path(path), u_header
        resp = @command.get_response
        @command.try_get_body( resp, dest )
      }

      return resp['http-header'], ret
    end

    def get2( path, u_header = {} )
      only_header( :get, path, u_header )
    end

    def get_body( dest = '', &block )
      if block then
        dest = ReadAdapter.new( block )
      end
      @command.try_get_body @response, dest
      ensure_termination @u_header

      dest
    end

    def head( path, u_header = {} )
      ret = only_header( :head, path, u_header )['http-header']
      ensure_termination u_header
      ret
    end

    def post( path, data, u_header = nil, dest = nil, &block )
      u_header ||= {}
      if block then
        dest = ReadAdapter.new( block )
        ret = nil
      else
        dest = ret = ''
      end
      resp = nil
      connecting( u_header, true ) {
        @command.post path, u_header, data
        resp = @command.get_response
        @command.try_get_body( resp, dest )
      }

      return resp['http-header'], ret
    end

    def post2( path, data, u_header = {} )
      only_header :post, path, u_header, data
    end

    # not tested because I could not setup apache  (__;;;
    def put( path, src = nil, u_header = {}, &block )
      u_header ||= u_header
      connecting( u_header, true ) {
        @command.put path, u_header, src, dest
      }

      header
    end


    private


    def only_header( mid, path, u_header, data = nil )
      @u_header = u_header ?  procheader(u_header) : {}
      @response = nil
      ensure_connection @u_header
      if data then
        @command.send mid, edit_path(path), @u_header, data
      else
        @command.send mid, edit_path(path), @u_header
      end
      @response = @command.get_response
      @response['http-header']
    end


    # called when connecting
    def do_finish
      unless @socket.closed? then
        begin
          @command.head '/', { 'Connection' => 'Close' }
        rescue EOFError
        end
      end
    end

    def connecting( u_header, putp = false )
      u_header = procheader( u_header )
      ensure_connection u_header
      yield
      ensure_termination u_header
    end

    def ensure_connection( u_header )
      if not @socket then
        u_header['Connection'] = 'Close'
        start
      elsif @socket.closed? then
        @socket.reopen
      end
    end

    def ensure_termination( u_header )
      unless keep_alive? u_header then
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


  class HTTPSuccessCode < SuccessCode; end
  class HTTPCreatedCode < SuccessCode; end
  class HTTPAcceptedCode < SuccessCode; end
  class HTTPNoContentCode < SuccessCode; end
  class HTTPResetContentCode < SuccessCode; end
  class HTTPPartialContentCode < SuccessCode; end

  class HTTPMultipleChoiceCode < RetryCode; end
  class HTTPMovedPermanentlyCode < RetryCode; end
  class HTTPMovedTemporarilyCode < RetryCode; end
  class HTTPNotModifiedCode < RetryCode; end
  class HTTPUseProxyCode < RetryCode; end


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
      request sprintf('GET %s HTTP/%s', path, HTTPVersion), u_header
    end
      
    def head( path, u_header )
      request sprintf('HEAD %s HTTP/%s', path, HTTPVersion), u_header
    end

    def post( path, u_header, data )
      request sprintf('POST %s HTTP/%s', path, HTTPVersion), u_header
      @socket.write data
    end

    def put( path, u_header, src )
      request sprintf('PUT %s HTTP/%s', path, HTTPVersion), u_header
      @socket.write_bin src
    end


    # def delete

    # def trace

    # def options


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
      reply_must rep, SuccessCode

      rep
    end

    def get_body( rep, dest )
      header = rep['http-header']
      if chunked? header then
        read_chunked( dest, header )
      else
        if clen = content_length( header ) then
          @socket.read clen, dest
        else
          ###
          ### "multipart/bytelenges" check should be done here ...
          ###
          @socket.read_all dest
        end
      end
    end

    def try_get_body( rep, dest )
      rep = get_reply while ContinueCode === rep
      return nil unless rep['body-exist']

      get_body rep, dest
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


    def get_reply
      str = @socket.readline
      unless /\AHTTP\/(\d+\.\d+)?\s+(\d\d\d)\s*(.*)\z/i === str then
        raise HTTPBadResponse, "wrong status line format: #{str}"
      end
      @http_version = $1
      status  = $2
      discrip = $3
      
      be = false
      klass = case status[0]
              when ?1 then
                case status[2]
                when ?0 then ContinueCode
                when ?1 then HTTPSuccessCode
                else         UnknownCode
                end
              when ?2 then
                case status[2]
                when ?0 then be = true;  HTTPSuccessCode
                when ?1 then be = false; HTTPSuccessCode
                when ?2 then be = true;  HTTPSuccessCode
                when ?3 then be = true;  HTTPSuccessCode
                when ?4 then be = false; HTTPNoContentCode
                when ?5 then be = false; HTTPResetContentCode
                when ?6 then be = true;  HTTPPartialContentCode
                else         UnknownCode
                end
              when ?3 then
                case status[2]
                when ?0 then be = true;  HTTPMultipleChoiceCode
                when ?1 then be = true;  HTTPMovedPermanentryCode
                when ?2 then be = true;  HTTPMovedTemporarilyCode
                when ?3 then be = true;  HTTPMovedPermanentryCode
                when ?4 then be = false; HTTPNotModifiedCode
                when ?5 then be = false; HTTPUseProxyCode
                else         UnknownCode
                end
              when ?4 then ServerBusyCode
              when ?5 then FatalErrorCode
              else         UnknownCode
              end
      code = klass.new( status, discrip )
      code['body-exist'] = be
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

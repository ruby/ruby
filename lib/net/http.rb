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

: get( path, header = nil, ret = '' )
  get data from "path" on connecting host.
  "header" is a Hash like { 'Accept' => '*/*', ... }.
  The data will be written to "ret" using "<<" method.
  This method returns response header (Hash) and "ret".

: head( path, header = nil )
  get only header from "path" on connecting host.
  "header" is a Hash like { 'Accept' => '*/*', ... }.
  This method returns header as a Hash like

    { 'content-length' => 'Content-Length: 2554',
      'content-type'   => 'Content-Type: text/html',
      ... }

=end

  class HTTP < Protocol

    protocol_param :port,         '80'
    protocol_param :command_type, '::Net::HTTPCommand'


    def get( path, u_header = nil, ret = '' )
      u_header ||= {}
      header = connecting( u_header ) {
        @command.get ret, edit_path(path), u_header
      }

      return header, ret
    end

    def head( path, u_header = nil )
      u_header ||= {}
      header = connecting( u_header ) {
        @command.head edit_path(path), u_header
      }

      header
    end


    private


    # called when connecting
    def do_finish
      unless @socket.closed? then
        @command.head '/', { 'Connection' => 'Close' }
      end
    end

    def connecting( u_header )
      u_header = procheader( u_header )

      if not @socket then
        u_header['Connection'] = 'Close'
        start
      elsif @socket.closed? then
        @socket.reopen
      end

      header = yield

      unless keep_alive? u_header then
        @socket.close
      end

      header
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

    def get( ret, path, u_header = nil )
      header = get_response(
        sprintf( 'GET %s HTTP/%s', path, HTTPVersion ), u_header )
      
      if chunked? header then
        clen = read_chunked_body( ret )
        header.delete 'transfer-encoding'
        header[ 'content-length' ] = "Content-Length: #{clen}"
      else
        if clen = content_length( header ) then
          @socket.read clen, ret
        else
          @socket.read_all ret
        end
      end

      header
    end


    def head( path, u_header = nil )
      get_response sprintf( 'HEAD %s HTTP/%s', path, HTTPVersion ), u_header
    end


    # not work
    def post( path, u_header = nil )
      get_response sprintf( 'POST %s HTTP/%s', path, HTTPVersion ), u_header
    end

    # not work
    def put( path, u_header = nil )
      get_response sprintf( 'PUT %s HTTP/%s', path, HTTPVersion ), u_header
    end

    # def delete

    # def trace

    # def options


    private


    def get_response( line, u_header )
      @socket.writeline line
      write_header u_header
      rep = get_reply
      header = read_header
      reply_must rep, SuccessCode

      header
    end

    def get_reply
      str = @socket.readline
      unless /\AHTTP\/(\d+\.\d+)?\s+(\d\d\d)\s*(.*)\z/i === str then
        raise HTTPBadResponse, "wrong status line format: #{str}"
      end
      @http_version = $1
      status  = $2
      discrip = $3
      
      klass = case status[0]
              when ?1 then
                case status[2]
                when ?0 then ContinueCode
                when ?1 then SuccessCode
                else         UnknownCode
                end
              when ?2 then SuccessCode
              when ?3 then RetryCode
              when ?4 then ServerBusyCode
              when ?5 then FatalErrorCode
              else         UnknownCode
              end
      klass.new( status, discrip )
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


    def read_header
      header = {}
      while true do
        line = @socket.readline
        break if line.empty?
        /\A[^:]+/ === line
        nm = $&
        nm.strip!
        nm.downcase!
        header[ nm ] = line
      end

      header
    end

    def write_header( user )
      if user then
        header = @in_header.dup.update user
      else
        header = @in_header
      end
      header.each do |n,v|
        @socket.writeline n + ': ' + v
      end
      @socket.writeline ''

      if tmp = header['Connection'] then
        /close/i === tmp
      else
        false
      end
    end

    def read_chunked_body( ret )
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

      total
    end

  end


end   # module Net

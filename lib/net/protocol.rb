=begin

= net/protocol.rb

written by Minero Aoki <aamine@dp.u-netsurf.ne.jp>

This library is distributed under the terms of the Ruby license.
You can freely distribute/modify this library.

=end


require 'socket'


module Net

  Version = '1.1.9'

=begin

== Net::Protocol

the abstruct class for Internet protocol

=== Super Class

Object

=== Class Methods

: new( address = 'localhost', port = nil )
  This method Creates a new protocol object.

: start( address = 'localhost', port = nil, *args )
: start( address = 'localhost', port = nil, *args ){|proto| .... }
  This method creates a new Protocol object and start session.
  If you call this method with block, Protocol object give itself
  to block and finish session when block returns.

: Proxy( address, port )
  This method creates a proxy class of its protocol.
  Arguments are address/port of proxy host.


=== Methods

: address
  the address of connecting server (FQDN).

: port
  connecting port number

: start( *args )
  This method start protocol. If you call this method when the protocol
  is already started, this only returns false without doing anything.

  '*args' are specified in subclasses.

: finish
  This method ends protocol. If you call this method before protocol starts,
  it only return false without doing anything.

: active?
  true if session have been started

=end

  class Protocol

    Version = ::Net::Version

    class << self

      def start( address = 'localhost', port = nil, *args )
        instance = new( address, port )

        if iterator? then
          instance.start( *args ) { yield instance }
        else
          instance.start *args
          instance
        end
      end

      def Proxy( p_addr, p_port )
        klass = Class.new( self )
        klass.module_eval %-

          def initialize( addr, port )
            @proxyaddr = '#{p_addr}'
            @proxyport = '#{p_port}'
            super @proxyaddr, @proxyport
            @address = addr
            @port    = port
          end

          def connect( addr, port )
            super @proxyaddr, @proxyport
          end
          private :connect
            
          attr_reader :proxyaddr, :proxyport
        -
        def klass.proxy?
          true
        end

        klass
      end

      def proxy?
        false
      end
            

      private

      def protocol_param( name, val )
        module_eval %-
          def self.#{name.id2name}
            #{val}
          end
        -
      end
        
    end


    #
    # sub-class requirements
    #
    # protocol_param command_type
    # protocol_param port
    #
    # private method do_start  (optional)
    # private method do_finish (optional)
    #

    protocol_param :port,         'nil'
    protocol_param :command_type, 'nil'
    protocol_param :socket_type,  '::Net::Socket'


    def initialize( addr = nil, port = nil )
      @address = addr || 'localhost'
      @port    = port || self.type.port

      @active  = false
      @pipe    = nil

      @command = nil
      @socket  = nil
    end


    attr_reader :address, :port,
                :command, :socket


    def start( *args )
      return false if active?
      @active = true

      begin
        connect @address, @port
        do_start *args
        yield if iterator?
      ensure
        finish if iterator?
      end
    end

    def finish
      ret = active?

      do_finish if @command
      disconnect
      @active = false

      ret
    end

    def active?
      @active
    end

    def set_pipe( arg )   # un-documented
      @pipe = arg
    end


    private


    def do_start
    end

    def do_finish
      @command.quit
    end


    def connect( addr, port )
      @socket  = self.type.socket_type.open( addr, port, @pipe )
      @command = self.type.command_type.new( @socket )
    end

    def disconnect
      @command = nil
      if @socket and not @socket.closed? then
        @socket.close
      end
      @socket  = nil
    end

  end

  Session = Protocol



  class Command

    def initialize( sock )
      @socket = sock
      @error_occured = false
      @last_reply = nil
    end

    attr_reader :socket, :error_occured, :last_reply
    attr_writer :socket

    def quit
      if @socket and not @socket.closed? then
        do_quit
        @error_occured = false
      end
    end


    private

    def do_quit
    end

    # abstract get_reply()

    def check_reply( *oks )
      @last_reply = get_reply
      reply_must( @last_reply, *oks )
    end

    def reply_must( rep, *oks )
      oks.each do |i|
        if i === rep then
          return rep
        end
      end

      @error_occured = true
      rep.error! @socket.sending
    end

    def getok( line, ok = SuccessCode )
      @socket.writeline line
      check_reply ok
    end
    
  end


  class ProtocolError        < StandardError   ; end
  class   ProtoSyntaxError   <   ProtocolError ; end
  class   ProtoFatalError    <   ProtocolError ; end
  class   ProtoUnknownError  <   ProtocolError ; end
  class   ProtoServerError   <   ProtocolError ; end
  class   ProtoAuthError     <   ProtocolError ; end
  class   ProtoCommandError  <   ProtocolError ; end
  class   ProtoRetryError    <   ProtocolError ; end

  class ReplyCode

    class << self

      def error_type( err )
        @err = err
      end

      def error!( mes )
        raise @err, mes
      end

    end
        
    def initialize( cod, mes )
      @code = cod
      @msg  = mes
      @data = nil
    end

    attr_reader :code, :msg

    def []( key )
      if @data then
        @data[key]
      else
        nil
      end
    end

    def []=( key, val )
      unless h = @data then
        @data = h = {}
      end
      h[key] = val
    end


    def error!( sending )
      mes = <<MES

status %s
writing string is:
%s

error message from server is:
%s
MES
      type.error! sprintf( mes, @code, Net.quote(sending), Net.quote(@msg) )
    end

  end

  class SuccessCode < ReplyCode
    error_type ProtoUnknownError
  end

  class ContinueCode < SuccessCode
    error_type ProtoUnknownError
  end

  class ErrorCode < ReplyCode
    error_type ProtocolError
  end

  class SyntaxErrorCode < ErrorCode
    error_type ProtoSyntaxError
  end

  class FatalErrorCode < ErrorCode
    error_type ProtoFatalError
  end

  class ServerBusyCode < ErrorCode
    error_type ProtoServerError
  end

  class RetryCode < ReplyCode
    error_type ProtoRetryError
  end

  class UnknownCode < ReplyCode
    error_type ProtoUnknownError
  end



  class WriteAdapter

    def initialize( sock, mid )
      @sock = sock
      @mid = mid
    end

    def write( str )
      @sock.__send__ @mid, str
    end
    alias << write
  
  end

  class ReadAdapter

    def initialize( block )
      @block = block
    end

    def <<( str )
      @block.call str
    end
  
  end


  class Socket

    def initialize( addr, port, pipe = nil )
      @addr = addr
      @port = port
      @pipe = pipe

      @closed  = true
      @ipaddr  = ''
      @sending = ''
      @buffer  = ''

      @socket = TCPsocket.new( addr, port )
      @closed = false
      @ipaddr = @socket.addr[3]
    end

    attr :pipe, true

    class << self
      alias open new
    end

    def reopen
      unless closed? then
        @socket.close
        @buffer = ''
      end
      @socket = TCPsocket.new( @addr, @port )
    end

    attr :socket, true

    def close
      @socket.close
      @closed = true
    end

    def closed?
      @closed
    end

    def address
      @addr.dup
    end
    alias addr address

    attr_reader :port

    def ip_address
      @ipaddr.dup
    end
    alias ipaddr ip_address

    attr_reader :sending


    CRLF    = "\r\n"
    D_CRLF  = ".\r\n"
    TERMEXP = /\n|\r\n|\r/o


    def read( len, ret = '' )
      @pipe << "reading #{len} bytes...\n" if pre = @pipe ; @pipe = nil

      rsize = 0
      while rsize + @buffer.size < len do
        rsize += writeinto( ret, @buffer.size )
        fill_rbuf
      end
      writeinto( ret, len - rsize )

      @pipe << "read #{len} bytes\n" if @pipe = pre
      ret
    end


    def read_all( ret = '' )
      @pipe << "reading all...\n" if pre = @pipe; @pipe = nil

      rsize = 0
      begin
        while true do
          rsize += writeinto( ret, @buffer.size )
          fill_rbuf
        end
      rescue EOFError
        ;
      end

      @pipe << "read #{rsize} bytes\n" if @pipe = pre
      ret
    end


    def readuntil( target )
      until idx = @buffer.index( target ) do
        fill_rbuf
      end

      ret = ''
      writeinto( ret, idx + target.size )
      ret
    end

        
    def readline
      ret = readuntil( CRLF )
      ret.chop!
      ret
    end


    def read_pendstr( dest = '' )
      @pipe << "reading text...\n" if pre = @pipe ; @pipe = nil

      rsize = 0

      while (str = readuntil( CRLF )) != D_CRLF do
        rsize += str.size
        str.gsub!( /\A\./o, '' )
        dest << str
      end

      @pipe << "read #{rsize} bytes\n" if @pipe = pre
      dest
    end


    def read_pendlist
      @pipe << "reading list...\n" if pre = @pipe ; @pipe = nil

      arr = []
      str = nil
      call = iterator?

      while (str = readuntil( CRLF )) != D_CRLF do
        str.chop!
        arr.push str
        yield str if iterator?
      end

      @pipe << "read #{arr.size} lines\n" if @pipe = pre
      arr
    end


    private


    READ_BLOCK = 1024 * 8

    def fill_rbuf
      @buffer << @socket.sysread( READ_BLOCK )
    end

    def writeinto( ret, len )
      bsi = @buffer.size
      ret << @buffer[ 0, len ]
      @buffer = @buffer[ len, bsi - len ]

      @pipe << %{read  "#{Net.quote ret}"\n} if @pipe
      len
    end


    public


    def write( str )
      do_write_beg
      do_write_do str
      do_write_fin
    end


    def writeline( str )
      do_write_beg
      do_write_do str
      do_write_do CRLF
      do_write_fin
    end


    def write_bin( src, block = nil )
      do_write_beg
      if block then
        block.call WriteAdapter.new( self, :do_write_do )
      else
        src.each do |bin|
          do_write_do bin
        end
      end
      do_write_fin
    end


    def write_pendstr( src )
      @pipe << "writing text from #{src.type}\n" if pre = @pipe ; @pipe = nil

      do_write_beg
      if iterator? then
        yield WriteAdapter.new( self, :write_pendstr_inner )
      else
        write_pendstr_inner src
      end
      each_crlf_line2( :i_w_pend )
      do_write_do D_CRLF
      wsize = do_write_fin

      @pipe << "wrote #{wsize} bytes text" if @pipe = pre
      wsize
    end


    private


    def write_inner( src )
      each_crlf_line( src, :do_write_do )
    end


    def write_pendstr_inner( src )
      each_crlf_line src, :i_w_pend
    end

    def i_w_pend( line )
      do_write_do '.' if line[0] == ?.
      do_write_do line
    end


    def each_crlf_line( src, mid )
      beg = 0
      buf = pos = s = bin = nil

      adding( src ) do
        beg = 0
        buf = @wbuf
        while pos = buf.index( TERMEXP, beg ) do
          s = $&.size
          break if pos + s == buf.size - 1 and buf[-1] == ?\r

          send mid, buf[ beg, pos - beg ] << CRLF
          beg = pos + s
        end
        @wbuf = buf[ beg, buf.size - beg ] if beg != 0
      end
    end

    def adding( src )
      i = nil

      case src
      when String
        0.step( src.size, 512 ) do |i|
          @wbuf << src[ i, 512 ]
          yield
        end

      when File
        while i = src.read( 512 ) do
          @wbuf << i
          yield
        end

      else
        src.each do |bin|
          @wbuf << bin
          yield if @wbuf.size > 512
        end
      end
    end

    def each_crlf_line2( mid )
      buf = @wbuf
      beg = pos = nil

      buf << "\n" unless /\n|\r/o === buf[-1,1]

      beg = 0
      while pos = buf.index( TERMEXP, beg ) do
        send mid, buf[ beg, pos - beg ] << CRLF
        beg = pos + $&.size
      end
    end


    def do_write_beg
      @writtensize = 0
      @sending = ''
      @wbuf = ''
    end

    def do_write_do( arg )
      if @pipe or @sending.size < 128 then
        @sending << Net.quote( arg )
      else
        @sending << '...' unless @sending[-1] == ?.
      end

      s = @socket.write( arg )
      @writtensize += s
      s
    end

    def do_write_fin
      if @pipe then
        @pipe << 'write "'
        @pipe << @sending
        @pipe << "\"\n"
      end

      @socket.flush
      @writtensize
    end

  end


  def Net.quote( str )
    str = str.gsub( "\n", '\\n' )
    str.gsub!( "\r", '\\r' )
    str.gsub!( "\t", '\\t' )
    str
  end

end   # module Net

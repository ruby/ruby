=begin

= net/session.rb

written by Minero Aoki <aamine@dp.u-netsurf.ne.jp>

This library is distributed under the terms of the Ruby license.
You can freely distribute/modify this library.

=end


require 'socket'


module Net

  Version = '1.1.4'

=begin

== Net::Protocol

the abstruct class for Internet protocol

=== Super Class

Object

=== Constants

: Version
  The version of Session class. It is a string like "1.1.4".


=== Class Methods

: new( address = 'localhost', port = nil )
  This method Creates a new Session object.

: start( address = 'localhost', port = nil, *args )
: start( address = 'localhost', port = nil, *args ){|session| .... }
  This method creates a new Session object and start session.
  If you call this method with block, Session object give itself
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
            
          attr :proxyaddr
          attr :proxyport
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
    protocol_param :socket_type,  '::Net::ProtocolSocket'


    def initialize( addr = nil, port = nil )
      @address = addr || 'localhost'
      @port    = port || self.type.port

      @active  = false
      @pipe    = nil

      @command = nil
      @socket  = nil
    end


    attr :address
    attr :port

    attr :command
    attr :socket


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
      if @command then
        do_finish
        disconnect
      end

      if @socket and not @socket.closed? then
        @socket.close
        @socket = nil
      end

      if active? then
        @active = false

        return true
      else
        return false
      end
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
    end


    def connect( addr, port )
      @socket  = self.type.socket_type.open( addr, port, @pipe )
      @command = self.type.command_type.new( @socket )
    end

    def disconnect
      @command.quit
      @command = nil
      @socket  = nil
    end

  end

  Session = Protocol


=begin

== Net::Command

=== Super Class

Object

=== Class Methods

: new( socket )
  This method create new Command object. 'socket' must be ProtocolSocket.
  This method is abstract class.


=== Methods

: quit
  This method dispatch command which ends the protocol.

=end

  class Command

    def initialize( sock )
      @socket = sock
      @error_occured = false
    end

    attr :socket, true
    attr :error_occured

    def quit
      if @socket and not @socket.closed? then
        begin
          do_quit
        ensure
          @socket.close unless @socket.closed?
          @socket = nil
        end
        @error_occured = false
      end
    end

    private

    def check_reply( *oks )
      reply_must( get_reply, *oks )
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

    def initialize( cod, mes )
      @code = cod
      @msg  = mes
    end

    attr :code
    attr :msg

    def error!( sending )
      mes = <<MES

status %s
writing string is:
%s

error message from server is:
%s
MES
      raise self.type::Error,
        sprintf( mes, @code, Net.quote(sending), Net.quote(@msg) )
    end

  end

  class SuccessCode < ReplyCode
    Error = ProtoUnknownError
  end

  class ContinueCode < SuccessCode
    Error = ProtoUnknownError
  end

  class ErrorCode < ReplyCode
    Error = ProtocolError
  end

  class SyntaxErrorCode < ErrorCode
    Error = ProtoSyntaxError
  end

  class FatalErrorCode < ErrorCode
    Error = ProtoFatalError
  end

  class ServerBusyCode < ErrorCode
    Error = ProtoServerError
  end

  class RetryCode < ReplyCode
    Error = ProtoRetryError
  end

  class UnknownCode < ReplyCode
    Error = ProtoUnknownError
  end


=begin

== Net::ProtocolSocket

=== Super Class

Object

=== Class Methods

: new( address = 'localhost', port = nil )
  This create new ProtocolSocket object, and connect to server.


=== Methods

: close
  This method closes socket.

: address, addr
  a FQDN address of server

: ip_address, ipaddr
  an IP address of server

: port
  connecting port number.

: closed?
  true if ProtocolSokcet have been closed already


: read( length )
  This method read 'length' bytes and return the string.

: readuntil( target )
  This method read until find 'target'. Returns read string.

: readline
  read until "\r\n" and returns it without "\r\n".

: read_pendstr
  This method read until "\r\n.\r\n".
  At the same time, delete period at line head and final line ("\r\n.\r\n").

: read_pendlist
: read_pendlist{|line| .... }
  This method read until "\r\n.\r\n". This method resembles to 'read_pendstr',
  but 'read_pendlist' don't check period at line head, and returns array which
  each element is one line.

  When this method was called with block, evaluate it for each reading a line.


: write( src )
  This method send 'src'. ProtocolSocket read strings from 'src' by 'each'
  iterator. This method returns written bytes.

: writebin( src )
  This method send 'src'. ProtocolSokcet read string from 'src' by 'each'
  iterator. This method returns written bytes.

: writeline( str )
  This method writes 'str'. There has not to be bare "\r" or "\n" in 'str'.

: write_pendstr( src )
  This method writes 'src' as a mail.
  ProtocolSocket reads strings from 'src' by 'each' iterator.
  This returns written bytes.

=end

  class ProtocolSocket

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

    attr :port

    def ip_address
      @ipaddr.dup
    end
    alias ipaddr ip_address

    attr :sending


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


    def write( src )
      do_write_beg
      each_crlf_line( src ) do |line|
        do_write_do line
      end
      do_write_fin
    end


    def writebin( src )
      do_write_beg
      src.each do |bin|
        do_write_do bin
      end
      do_write_fin
    end


    def writeline( str )
      do_write_beg
      do_write_do str
      do_write_do CRLF
      do_write_fin
    end


    def write_pendstr( src )
      @pipe << "writing text from #{src.type}" if pre = @pipe ; @pipe = nil

      do_write_beg
      each_crlf_line( src ) do |line|
        do_write_do '.' if line[0] == ?.
        do_write_do line
      end
      do_write_do D_CRLF
      wsize = do_write_fin

      @pipe << "wrote #{wsize} bytes text" if @pipe = pre
      wsize
    end


    private


    def each_crlf_line( src )
      buf = ''
      beg = 0
      pos = s = bin = nil

      src.each do |bin|
        buf << bin

        beg = 0
        while pos = buf.index( TERMEXP, beg ) do
          s = $&.size
          break if pos + s == buf.size - 1 and buf[-1] == ?\r

          yield buf[ beg, pos - beg ] << CRLF
          beg = pos + s
        end
        buf = buf[ beg, buf.size - beg ] if beg != 0
      end

      buf << "\n" unless /\n|\r/o === buf[-1,1]

      beg = 0
      while pos = buf.index( TERMEXP, beg ) do
        yield buf[ beg, pos - beg ] << CRLF
        beg = pos + $&.size
      end
    end


    def do_write_beg
      @writtensize = 0
      @sending = ''
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

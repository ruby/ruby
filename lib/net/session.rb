=begin

= Net module version 1.0.2 reference manual

session.rb written by Minero Aoki <aamine@dp.u-netsurf.ne.jp>

This library is distributed under the terms of Ruby style license.
You can freely distribute/modify/copy this file.

=end


require 'socket'


class String

  def doquote
    str = self.gsub( "\n", '\\n' )
    str.gsub!( "\r", '\\r' )
    str.gsub!( "\t", '\\t' )
    return str
  end

end


=begin

== Net::Session

the abstruct class for Internet session

=== Super Class

Object

=== Constants

: Version

  The version of Session class. It is a string like "1.0.2".

=end


module Net

  class Session

    Version = '1.0.2'

=begin

=== Class Methods

: new( address = 'localhost', port = nil )

  This method Create a new Session object.

: start( address = 'localhost', port = nil, *args )
: start( address = 'localhost', port = nil, *args ){|session| .... }

  This method create a new Session object and start session.
  If you call this method with block, Session object give itself
  to block and finish session when block returns.

=end

    def initialize( addr = 'localhost', port = nil )
      proto_initialize
      @address = addr
      @port    = port if port
      @active  = false
    end

    class << self
      def start( address = 'localhost', port = nil, *args )
        inst = new( address, port )
        ret = inst.start( *args )

        if iterator? then
          ret = yield( inst )
          inst.finish
        end
        return ret
      end
    end

=begin

=== Methods

: address

  the address of connecting server (FQDN).

: port

  connecting port number

=end

    attr :address
    attr :port

    attr :socket

    attr :proto_type
    attr :proto, true

=begin

: start( *args )

  This method start session. If you call this method when the session
  is already started, this only returns false without doing anything.

  '*args' are specified in subclasses.

: finish

  This method finish session. If you call this method before session starts,
  it only return false without doing anything.

: active?

  true if session have been started

=end

    def start( *args )
      return false if active?
      @active = true

      if ProtocolSocket === args[0] then
        @socket = args.shift
        @socket.pipe = @pipe
      else
        @socket = ProtocolSocket.open( @address, @port, @pipe )
      end
      @pipe = nil

      @proto = @proto_type.new( @socket )
      do_start( *args )
    end

    def finish
      @active = false

      if @proto then
        do_finish
        @proto = nil

        return true
      else
        return false
      end
    end

    def active?() @active end

    def set_pipe( arg )
      @pipe = arg
    end

  end


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

  This method finishes protocol.

=end

  class Command

    def initialize( sock )
      @socket = sock
      check_reply( SuccessCode )
    end

    attr :socket, true

    def quit
      if @socket and not @socket.closed? then
        begin
          do_quit
        ensure
          @socket.close unless @socket.closed?
          @socket = nil
        end
      end
    end

    private

    def check_reply( *oks )
      rep = get_reply
      oks.each do |i|
        if i === rep then
          return rep
        end
      end

      rep.error! @socket.sending
    end
    
  end


  class ProtocolError        < StandardError   ; end
  class   ProtoSyntaxError   <   ProtocolError ; end
  class   ProtoFatalError    <   ProtocolError ; end
  class   ProtoUnknownError  <   ProtocolError ; end
  class   ProtoServerError   <   ProtocolError ; end
  class   ProtoAuthError     <   ProtocolError ; end
  class   ProtoCommandError  <   ProtocolError ; end

  class ReplyCode

    def initialize( cod, mes )
      @code = cod
      @msg  = mes
    end

    attr :code
    attr :msg

    def error!( sending )
      err, tag = Errors[ self.type ]
      mes = sprintf( <<MES, tag, @code, sending.doquote, @msg.doquote )

%s: status %s
writing string is:
%s

error message from server is:
%s
MES
      raise err, mes
    end

  end

  class SuccessCode     < ReplyCode ; end
  class ContinueCode    < SuccessCode ; end
  class ErrorCode       < ReplyCode ; end
  class SyntaxErrorCode < ErrorCode ; end
  class FatalErrorCode  < ErrorCode ; end
  class ServerBusyCode  < ErrorCode ; end
  class UnknownCode     < ReplyCode ; end

  class ReplyCode
    Errors = {
      SuccessCode     => [ ProtoUnknownError, 'unknown error' ],
      ContinueCode    => [ ProtoUnknownError, 'unknown error' ],
      ErrorCode       => [ ProtocolError, 'protocol error' ],
      SyntaxErrorCode => [ ProtoSyntaxError, 'syntax error' ],
      FatalErrorCode  => [ ProtoFatalError, 'fatal error' ],
      ServerBusyCode  => [ ProtoServerError, 'probably server busy' ],
      UnknownCode     => [ ProtoUnknownError, 'unknown error' ]
    }
  end


=begin

== Net::ProtocolSocket

=== Super Class

Object

=== Class Methods

: new( address = 'localhost', port = nil )

  This create new ProtocolSocket object, and connect to server.

=end

  class ProtocolSocket

    def initialize( addr, port, pipe = nil )
      @address = addr
      @port    = port
      @pipe    = pipe

      @ipaddr  = ''
      @closed  = false
      @sending = ''
      @buffer  = ''

      @socket = TCPsocket.new( addr, port )
      @ipaddr = @socket.addr[3]
    end

    attr :pipe, true

    class << self
      alias open new
    end

=begin

=== Methods

: close

  This method closes socket.

: addr

  a FQDN address of server

: ipaddr

  an IP address of server

: port

  connecting port number.

: closed?

  true if ProtocolSokcet have been closed already

=end

    attr :socket, true

    def close
      @socket.close
      @closed = true
    end

    def closed?() @closed end

    def addr() @address.dup end
    def port() @port end
    def ipaddr() @ipaddr.dup end

    attr :sending


    CRLF    = "\r\n"
    D_CRLF  = ".\r\n"
    TERMEXP = /\n|\r\n|\r/o


=begin

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

=end

    def read( len, ret = '' )
      rsize = 0

      while rsize + @buffer.size < len do
        rsize += @buffer.size
        ret << fetch_rbuf( @buffer.size )
        fill_rbuf
      end
      ret << fetch_rbuf( len - rsize )

      return ret
    end


    def readuntil( target )
      until idx = @buffer.index( target ) do
        fill_rbuf
      end

      return fetch_rbuf( idx + target.size )
    end

        
    def readline
      ret = readuntil( CRLF )
      ret.chop!
      return ret
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
      return dest
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
      return arr
    end


    private


    READ_BLOCK = 1024 * 8

    def fill_rbuf
      @buffer << @socket.sysread( READ_BLOCK )
    end

    def fetch_rbuf( len )
      bsi = @buffer.size
      ret = @buffer[ 0, len ]
      @buffer = @buffer[ len, bsi - len ]

      @pipe << %{read  "#{debugstr ret}"\n} if @pipe
      return ret
    end


=begin

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

    public


    def write( src )
      do_write_beg
      each_crlf_line( src ) do |line|
        do_write_do line
      end
      return do_write_fin
    end


    def writebin( src )
      do_write_beg
      src.each do |bin|
        do_write_do bin
      end
      return do_write_fin
    end


    def writeline( str )
      do_write_beg
      do_write_do str
      do_write_do CRLF
      return do_write_fin
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
      return wsize
    end


    private


    def each_crlf_line( src )
      buf = ''
      beg = 0
      pos = nil

      src.each do |b|
        buf << b

        beg = 0
        while (pos = buf.index(TERMEXP, beg)) and (pos < buf.size - 2) do
          pos += $&.size
          tmp = buf[ beg, pos - beg ]
          tmp.chop!
          yield tmp << CRLF
          beg = pos
        end
        buf = buf[ beg, buf.size - beg ] if beg != 0
      end

      buf << "\n" unless /\n|\r/o === buf[-1,1]

      beg = 0
      while pos = buf.index( TERMEXP, beg ) do
        pos += $&.size
        tmp = buf[ beg, pos - beg ]
        tmp.chop!
        yield tmp << CRLF
        beg = pos
      end
    end


    def do_write_beg
      @wtmp = 'write "' if @pipe

      @writtensize = 0
      @sending = ''
    end

    def do_write_do( arg )
      @wtmp << debugstr( arg ) if @pipe

      if @sending.size < 128 then
        @sending << arg
      else
        @sending << '...' unless @sending[-1] == ?.
      end

      s = @socket.write( arg )
      @writtensize += s
      return s
    end

    def do_write_fin
      if @pipe then
        @wtmp << "\n"
        @pipe << @wtmp
        @wtmp = nil
      end

      @socket.flush
      return @writtensize
    end


    def debugstr( str )
      ret = ''
      while str and tmp = str[ 0, 50 ] do
        str = str[ 50, str.size - 50 ]
        tmp = tmp.inspect
        ret << tmp[ 1, tmp.size - 2 ]
      end
      ret
    end

  end

end

#
# session.rb  version 1.0.1
#
#   author: Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#

require 'socket'


class String

  def doquote
    str = self.gsub( "\n", '\\n' )
    str.gsub!( "\r", '\\r' )
    str.gsub!( "\t", '\\t' )
    return str
  end

end



module Net

  DEBUG = $DEBUG
  # DEBUG = false


  class Session

    Version = '1.0.1'

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


    attr :address
    attr :port

    attr :socket

    attr :proto_type
    attr :proto, true

    def start( *args )
      return false if active?

      if ProtocolSocket === args[0] then
        @socket = args.shift
      else
        @socket = ProtocolSocket.open( @address, @port )
      end
      @proto = @proto_type.new( @socket )
      do_start( *args )

      @active = true
    end

    def finish
      if @proto then
        do_finish
        @proto = nil

        return true
      else
        return false
      end
    end

    def active?() @active end

  end



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



  class ProtocolSocket

    def initialize( addr, port )
      @address = addr
      @port    = port

      @ipaddr  = ''
      @closed  = false
      @sending = ''
      @buffer  = ''

      @socket = TCPsocket.new( addr, port )
      @ipaddr = @socket.addr[3]

      @dout = Net::DEBUG
    end

    class << self
      alias open new
    end


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
      $stderr.puts "reading pendstr" if pre = @dout ; @dout = false

      rsize = 0

      while (str = readuntil( CRLF )) != D_CRLF do
        rsize += str.size
        str.gsub!( /\A\./o, '' )
        dest << str
      end

      $stderr.puts "read pendstr #{rsize} bytes" if @dout = pre
      return dest
    end


    def read_pendlist
      arr = []
      str = nil
      call = iterator?

      while (str = readuntil( CRLF )) != D_CRLF do
        str.chop!
        arr.push str
        yield str if iterator?
      end

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

      if @dout then
        $stderr.print 'read  "'
        debugout ret
        $stderr.print "\"\n"
      end
      return ret
    end


    ### write

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
      $stderr.puts "writing pendstr from #{src.type}" if pre = @dout
      @dout = false

      do_write_beg
      each_crlf_line( src ) do |line|
        do_write_do '.' if line[0] == ?.
        do_write_do line
      end
      do_write_do D_CRLF
      wsize = do_write_fin

      $stderr.puts "wrote pendstr #{wsize} bytes" if @dout = pre
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
      while pos = buf.index(TERMEXP, beg) do
        pos += $&.size
        tmp = buf[ beg, pos - beg ]
        tmp.chop!
        yield tmp << CRLF
        beg = pos
      end
    end


    def do_write_beg
      $stderr.print 'write "' if @dout

      @writtensize = 0
      @sending = ''
    end

    def do_write_do( arg )
      debugout arg if @dout

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
      $stderr.puts if @dout

      @socket.flush
      return @writtensize
    end


    def debugout( ret )
      while ret and tmp = ret[ 0, 50 ] do
        ret = ret[ 50, ret.size - 50 ]
        tmp = tmp.inspect
        $stderr.print tmp[ 1, tmp.size - 2 ]
      end
    end

  end

end

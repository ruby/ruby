=begin

= net/protocol.rb

written by Minero Aoki <aamine@dp.u-netsurf.ne.jp>

This library is distributed under the terms of the Ruby license.
You can freely distribute/modify this library.

=end


require 'socket'


module Net

=begin

== Net::Protocol

the abstruct class for Internet protocol

=== Super Class

Object

=== Class Methods

: new( address = 'localhost', port = nil )
  This method Creates a new protocol object.

: start( address = 'localhost', port = nil, *protoargs )
: start( address = 'localhost', port = nil, *protoargs ) {|proto| .... }
  This method creates a new Protocol object and opens a session.
  equals to Net::Protocol.new( address, port ).start( *protoargs )

: Proxy( address, port )
  This method creates a proxy class of its protocol.
  Arguments are address/port of proxy host.

=== Methods

: address
  the address of connecting server (FQDN).

: port
  connecting port number

: start( *args )
: start( *args ) {|proto| .... }
  This method starts protocol. If protocol was already started,
  do nothing and returns false.

  '*args' are specified in subclasses.

  When is called as iterator, gives Protocol object to block and
  close session when block finished.

: finish
  This method ends protocol. If you call this method before protocol starts,
  it only return false without doing anything.

: active?
  true if session have been started

=end

  class Protocol

    Version = '1.1.19'

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

          def connect( addr = nil, port = nil )
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
      @port    = port || type.port

      @active  = false
      @pipe    = nil

      @command = nil
      @socket  = nil
    end


    attr_reader :address, :port,
                :command, :socket


    def start( *args )
      return false if active?

      begin
        connect
        do_start *args
        @active = true
        yield self if iterator?
      ensure
        finish if iterator?
      end
    end

    def finish
      ret = active?

      do_finish
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


    def connect( addr = @address, port = @port )
      @socket  = type.socket_type.open( addr, port, @pipe )
      @command = type.command_type.new( @socket )
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
      @last_reply = nil
      @critical = false
    end

    attr_accessor :socket
    attr_reader :last_reply

    # abstract quit


    private

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
      rep.error!
    end

    def getok( line, ok = SuccessCode )
      @socket.writeline line
      check_reply ok
    end


    def critical
      return if @critical
      @critical = true
      r = yield
      @critical = false
      r
    end

    def critical?
      @critical
    end

    def begin_critical
      ret = @critical
      @critical = true
      not ret
    end

    def end_critical
      @critical = false
    end

  end


  class Response

    def initialize( ctype, cno, msg )
      @code_type = ctype
      @code      = cno
      @message   = msg
      super()
    end

    attr_reader :code_type, :code, :message
    alias msg message

    def error!
      raise @code_type.error_type, @code + ' ' + Net.quote(@message)
    end

  end


  class ProtocolError          < StandardError; end
  class ProtoSyntaxError       < ProtocolError; end
  class ProtoFatalError        < ProtocolError; end
  class ProtoUnknownError      < ProtocolError; end
  class ProtoServerError       < ProtocolError; end
  class ProtoAuthError         < ProtocolError; end
  class ProtoCommandError      < ProtocolError; end
  class ProtoRetriableError    < ProtocolError; end
  ProtocRetryError = ProtoRetriableError


  class Code

    def initialize( paren, err )
      @parents = paren
      @err = err

      @parents.push self
    end

    attr_reader :parents

    def error_type
      @err
    end

    def ===( response )
      response.code_type.parents.reverse_each {|i| return true if i == self }
      false
    end

    def mkchild( err = nil )
      type.new( @parents + [self], err || @err )
    end
  
  end
  
  ReplyCode       = Code.new( [], ProtoUnknownError )
  SuccessCode     = ReplyCode.mkchild( ProtoUnknownError )
  ContinueCode    = ReplyCode.mkchild( ProtoUnknownError )
  ErrorCode       = ReplyCode.mkchild( ProtocolError )
  SyntaxErrorCode = ErrorCode.mkchild( ProtoSyntaxError )
  FatalErrorCode  = ErrorCode.mkchild( ProtoFatalError )
  ServerErrorCode = ErrorCode.mkchild( ProtoServerError )
  AuthErrorCode   = ErrorCode.mkchild( ProtoAuthError )
  RetriableCode   = ReplyCode.mkchild( ProtoRetriableError )
  UnknownCode     = ReplyCode.mkchild( ProtoUnknownError )



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
      @prepipe = nil

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


    def read( len, dest = '' )
      @pipe << "reading #{len} bytes...\n" if @pipe; pipeoff

      rsize = 0
      while rsize + @buffer.size < len do
        rsize += writeinto( dest, @buffer.size )
        fill_rbuf
      end
      writeinto( dest, len - rsize )

      @pipe << "read #{len} bytes\n" if pipeon
      dest
    end


    def read_all( dest = '' )
      @pipe << "reading all...\n" if @pipe; pipeoff

      rsize = 0
      begin
        while true do
          rsize += writeinto( dest, @buffer.size )
          fill_rbuf
        end
      rescue EOFError
        ;
      end

      @pipe << "read #{rsize} bytes\n" if pipeon
      dest
    end


    def readuntil( target )
      while true do
        idx = @buffer.index( target )
        break if idx
        fill_rbuf
      end

      dest = ''
      writeinto( dest, idx + target.size )
      dest
    end

        
    def readline
      ret = readuntil( CRLF )
      ret.chop!
      ret
    end


    def read_pendstr( dest )
      @pipe << "reading text...\n" if @pipe; pipeoff

      rsize = 0

      while (str = readuntil( CRLF )) != D_CRLF do
        rsize += str.size
        str.gsub!( /\A\./o, '' )
        dest << str
      end

      @pipe << "read #{rsize} bytes\n" if pipeon
      dest
    end


    def read_pendlist
      @pipe << "reading list...\n" if @pipe; pipeoff

      arr = []
      str = nil

      while (str = readuntil( CRLF )) != D_CRLF do
        str.chop!
        arr.push str
        yield str if iterator?
      end

      @pipe << "read #{arr.size} lines\n" if pipeon
      arr
    end


    private


    READ_BLOCK = 1024 * 8

    def fill_rbuf
      @buffer << @socket.sysread( READ_BLOCK )
    end

    def writeinto( dest, len )
      bsi = @buffer.size
      dest << @buffer[ 0, len ]
      @buffer = @buffer[ len, bsi - len ]

      @pipe << %{read  "#{Net.quote dest}"\n} if @pipe
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


    def write_bin( src, block )
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


    def write_pendstr( src, block )
      @pipe << "writing text from #{src.type}\n" if @pipe; pipeoff

      do_write_beg
      if block then
        block.call WriteAdapter.new( self, :write_pendstr_inner )
      else
        write_pendstr_inner src
      end
      each_crlf_line2( :i_w_pend )
      do_write_do D_CRLF
      wsize = do_write_fin

      @pipe << "wrote #{wsize} bytes text\n" if pipeon
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
        while true do
          pos = buf.index( TERMEXP, beg )
          break unless pos
          s = $&.size
          break if pos + s == buf.size - 1 and buf[-1] == ?\r

          __send__ mid, buf[ beg, pos - beg ] << CRLF
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
        while true do
          i = src.read( 512 )
          break unless i
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
      while true do
        pos = buf.index( TERMEXP, beg )
        break unless pos
        __send__ mid, buf[ beg, pos - beg ] << CRLF
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


    def pipeoff
      @prepipe = @pipe
      @pipe = nil
      @prepipe
    end

    def pipeon
      @pipe = @prepipe
      @prepipe = nil
      @pipe
    end

  end


  def Net.quote( str )
    str = str.gsub( "\n", '\\n' )
    str.gsub!( "\r", '\\r' )
    str.gsub!( "\t", '\\t' )
    str
  end

end   # module Net

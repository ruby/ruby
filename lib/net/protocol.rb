=begin

= net/protocol.rb

written by Minero Aoki <aamine@dp.u-netsurf.ne.jp>

This library is distributed under the terms of the Ruby license.
You can freely distribute/modify this library.


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

require 'socket'


module Net

  class Protocol

    Version = '1.1.24'


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

      def Proxy( p_addr, p_port = nil )
        p_port ||= self.port
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

    def inspect
      "#<#{type} #{address}:#{port} open=#{active?}>"
    end


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

    def inspect
      "#<#{type}>"
    end

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

    def inspect
      "#<#{type} #{code}>"
    end

    def error!( data = nil )
      raise code_type.error_type.new( code + ' ' + Net.quote(msg), data )
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

  class ProtocolError
  
    def initialize( msg, data )
      super msg
      @data = data
    end

    attr :data

    def inspect
      "#<#{type}>"
    end
  
  end


  class Code

    def initialize( paren, err )
      @parents = paren
      @err = err

      @parents.push self
    end

    attr_reader :parents

    def inspect
      "#<#{type}>"
    end

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

    def inspect
      "#<#{type}>"
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

    def inspect
      "#<#{type}>"
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

    def inspect
      "#<#{type} open=#{!@closed}>"
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
      ret = readuntil( "\r\n" )
      ret.chop!
      ret
    end


    def read_pendstr( dest )
      @pipe << "reading text...\n" if @pipe; pipeoff

      rsize = 0

      while (str = readuntil( "\r\n" )) != ".\r\n" do
        rsize += str.size
        str.gsub!( /\A\./, '' )
        dest << str
      end

      @pipe << "read #{rsize} bytes\n" if pipeon
      dest
    end


    def read_pendlist
      @pipe << "reading list...\n" if @pipe; pipeoff

      arr = []
      str = nil

      while (str = readuntil( "\r\n" )) != ".\r\n" do
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
      writing {
        do_write str
      }
    end


    def writeline( str )
      writing {
        do_write str
        do_write "\r\n"
      }
    end


    def write_bin( src, block )
      writing {
        if block then
          block.call WriteAdapter.new( self, :do_write )
        else
          src.each do |bin|
            do_write bin
          end
        end
      }
    end


    def write_pendstr( src, block )
      @pipe << "writing text from #{src.type}\n" if @pipe; pipeoff

      wsize = use_each_crlf_line {
        if block then
          block.call WriteAdapter.new( self, :wpend_in )
        else
          wpend_in src
        end
      }

      @pipe << "wrote #{wsize} bytes text\n" if pipeon
      wsize
    end


    private


    def wpend_in( src )
      line = nil
      each_crlf_line( src ) do |line|
        do_write '.' if line[0] == ?.
        do_write line
      end
    end

    def use_each_crlf_line
      writing {
        @wbuf = ''

        yield

        if not @wbuf.empty? then       # un-terminated last line
          if @wbuf[-1] == ?\r then
            @wbuf.chop!
          end
          @wbuf.concat "\r\n"
          do_write @wbuf
        elsif @writtensize == 0 then   # empty src
          do_write "\r\n"
        end
        do_write ".\r\n"

        @wbuf = nil
      }
    end

    def each_crlf_line( src )
      str = m = nil
      beg = 0

      adding( src ) do
        buf = @wbuf
        while buf.index( /\n|\r\n|\r/, beg ) do
          m = $~
          if m.begin(0) == buf.size - 1 and buf[-1] == ?\r then
            # "...\r" : can follow "\n..."
            break
          end
          str = buf[ beg, m.begin(0) - beg ]
          str.concat "\r\n"
          yield str
          beg = m.end(0)
        end
        @wbuf = buf[ beg, buf.size - beg ]
      end
    end

    def adding( src )
      i = nil

      case src
      when String
        0.step( src.size - 1, 2048 ) do |i|
          @wbuf << src[i,2048]
          yield
        end

      when File
        while true do
          i = src.read( 2048 )
          break unless i
          i[0,0] = @wbuf
          @wbuf = i
          yield
        end

      else
        src.each do |i|
          @wbuf << i
          if @wbuf.size > 2048 then
            yield
          end
        end
      end
    end


    def writing
      @writtensize = 0
      @sending = ''

      yield

      if @pipe then
        @pipe << 'write "'
        @pipe << @sending
        @pipe << "\"\n"
      end
      @socket.flush
      @writtensize
    end

    def do_write( arg )
      if @pipe or @sending.size < 128 then
        @sending << Net.quote( arg )
      else
        @sending << '...' unless @sending[-1] == ?.
      end

      s = @socket.write( arg )
      @writtensize += s
      s
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

=begin

= net/protocol.rb version 1.1.33

written by Minero Aoki <aamine@dp.u-netsurf.ne.jp>

This program is free software.
You can distribute/modify this program under
the terms of the Ruby Distribute License.

Japanese version of this document is in "net" full package.
You can get it from RAA
(Ruby Application Archive: http://www.ruby-lang.org/en/raa.html).


== Net::Protocol

the abstract class for Internet protocol

=== Super Class

Object

=== Class Methods

: new( address = 'localhost', port = nil )
  This method Creates a new protocol object.

: start( address = 'localhost', port = nil, *protoargs )
: start( address = 'localhost', port = nil, *protoargs ) {|proto| .... }
  This method creates a new Protocol object and opens a session.
  equals to Net::Protocol.new( address, port ).start( *protoargs )

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

  When is called with block, gives Protocol object to block and
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

    Version = '1.1.33'


    class << self

      def start( address = 'localhost', port = nil, *args )
        instance = new( address, port )

        if block_given? then
          instance.start( *args ) { yield instance }
        else
          instance.start( *args )
          instance
        end
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
    protocol_param :socket_type,  '::Net::NetPrivate::Socket'


    def initialize( addr = nil, port = nil )
      @address = addr || 'localhost'
      @port    = port || type.port

      @command = nil
      @socket  = nil

      @active  = false
      @pipe    = nil
    end

    attr_reader :address
    attr_reader :port

    attr_reader :command
    attr_reader :socket

    def inspect
      "#<#{type} #{address}:#{port} open=#{active?}>"
    end


    def start( *args )
      return false if active?

      if block_given? then
        begin
          _start args
          yield self
        ensure
          finish
        end
      else
        _start args
      end
    end

    def _start( args )
      connect
      do_start( *args )
      @active = true
    end
    private :_start

    def finish
      return false unless active?

      do_finish unless @command.critical?
      disconnect
      @active = false
      true
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
  
    def initialize( msg, data = nil )
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
  InformationCode = ReplyCode.mkchild( ProtoUnknownError )
  SuccessCode     = ReplyCode.mkchild( ProtoUnknownError )
  ContinueCode    = ReplyCode.mkchild( ProtoUnknownError )
  ErrorCode       = ReplyCode.mkchild( ProtocolError )
  SyntaxErrorCode = ErrorCode.mkchild( ProtoSyntaxError )
  FatalErrorCode  = ErrorCode.mkchild( ProtoFatalError )
  ServerErrorCode = ErrorCode.mkchild( ProtoServerError )
  AuthErrorCode   = ErrorCode.mkchild( ProtoAuthError )
  RetriableCode   = ReplyCode.mkchild( ProtoRetriableError )
  UnknownCode     = ReplyCode.mkchild( ProtoUnknownError )



  module NetPrivate


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
      callblock( str, &@block ) if @block
    end

    private

    def callblock( str )
      begin
        user_break = true
        yield str
        user_break = false
      rescue Exception
        user_break = false
        raise
      ensure
        if user_break then
          @block = nil
          return   # stop break
        end
      end
    end
  
  end



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

    def getok( line, expect = SuccessCode )
      @socket.writeline line
      check_reply expect
    end


    #
    # error handle
    #

    public

    def critical?
      @critical
    end

    def error_ok
      @critical = false
    end

    private

    def critical
      @critical = true
      ret = yield
      @critical = false
      ret
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
        close
      end
      @buffer = ''
      @socket = TCPsocket.new( @addr, @port )
      @closed = false
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


    ###
    ### read
    ###

    CRLF = "\r\n"

    def read( len, dest = '', igneof = false )
      @pipe << "reading #{len} bytes...\n" if @pipe; pipeoff

      rsize = 0
      begin
        while rsize + @buffer.size < len do
          rsize += writeinto( dest, @buffer.size )
          fill_rbuf
        end
        writeinto( dest, len - rsize )
      rescue EOFError
        raise unless igneof
      end

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


    def readuntil( target, igneof = false )
      dest = ''
      begin
        while true do
          idx = @buffer.index( target )
          break if idx
          fill_rbuf
        end
        writeinto( dest, idx + target.size )
      rescue EOFError
        raise unless igneof
        writeinto( dest, @buffer.size )
      end
      dest
    end

        
    def readline
      ret = readuntil( "\n" )
      ret.chop!
      ret
    end


    def read_pendstr( dest )
      @pipe << "reading text...\n" if @pipe; pipeoff

      rsize = 0
      while (str = readuntil("\r\n")) != ".\r\n" do
        rsize += str.size
        str.gsub!( /\A\./, '' )
        dest << str
      end

      @pipe << "read #{rsize} bytes\n" if pipeon
      dest
    end


    # private use only (can not handle 'break')
    def read_pendlist
      @pipe << "reading list...\n" if @pipe; pipeoff

      str = nil
      i = 0
      while (str = readuntil("\r\n")) != ".\r\n" do
        i += 1
        str.chop!
        yield str
      end

      @pipe << "read #{i} items\n" if pipeon
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


    ###
    ### write
    ###

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
      pre = @writtensize
      each_crlf_line( src ) do |line|
        do_write '.' if line[0] == ?.
        do_write line
      end

      @writtensize - pre
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
      str = m = beg = nil

      adding( src ) do
        beg = 0
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
        yield unless @wbuf.empty?
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


  end   # module Net::NetPrivate


  def Net.quote( str )
    str = str.gsub( "\n", '\\n' )
    str.gsub!( "\r", '\\r' )
    str.gsub!( "\t", '\\t' )
    str
  end

end   # module Net

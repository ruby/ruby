=begin

= net/protocol.rb

Copyright (c) 1999-2002 Yukihiro Matsumoto

written & maintained by Minero Aoki <aamine@loveruby.net>

This program is free software. You can re-distribute and/or
modify this program under the same terms as Ruby itself,
Ruby Distribute License or GNU General Public License.

NOTE: You can find Japanese version of this document in
the doc/net directory of the standard ruby interpreter package.

$Id$

=end

require 'socket'
require 'timeout'


module Net

  class Protocol

    Version = '1.2.3'
    Revision = %q$Revision$.split(/\s+/)[1]


    class << self

      def port
        default_port
      end

      private

      def protocol_param( name, val )
        module_eval <<-End, __FILE__, __LINE__ + 1
            def self.#{name.id2name}
              #{val}
            end
        End
      end
        
    end


    #
    # --- Configuration Staffs for Sub Classes ---
    #
    #   class method default_port
    #   class method command_type
    #   class method socket_type
    #
    #   private method do_start
    #   private method do_finish
    #
    #   private method conn_address
    #   private method conn_port
    #


    def Protocol.start( address, port = nil, *args )
      instance = new(address, port)

      if block_given? then
        instance.start(*args) { return yield(instance) }
      else
        instance.start(*args)
        instance
      end
    end

    def initialize( addr, port = nil )
      @address = addr
      @port    = port || self.class.default_port

      @command = nil
      @socket  = nil

      @started = false

      @open_timeout = 30
      @read_timeout = 60

      @debug_output = nil
    end

    attr_reader :address
    attr_reader :port

    attr_reader :command
    attr_reader :socket

    attr_accessor :open_timeout

    attr_reader :read_timeout

    def read_timeout=( sec )
      @socket.read_timeout = sec if @socket
      @read_timeout = sec
    end

    def started?
      @started
    end

    alias active? started?

    def set_debug_output( arg )   # un-documented
      @debug_output = arg
    end

    def inspect
      "#<#{self.class} #{@address}:#{@port} open=#{active?}>"
    end

    #
    # open
    #

    def start( *args )
      @started and raise IOError, 'protocol has been opened already'

      if block_given? then
        begin
          do_start( *args )
          @started = true
          return yield(self)
        ensure
          finish if @started
        end
      end

      do_start( *args )
      @started = true
      self
    end

    private

    # abstract do_start()

    def conn_socket
      @socket = self.class.socket_type.open(
              conn_address(), conn_port(),
              @open_timeout, @read_timeout, @debug_output )
      on_connect
    end

    alias conn_address address
    alias conn_port    port

    def reconn_socket
      @socket.reopen @open_timeout
      on_connect
    end

    def conn_command
      @command = self.class.command_type.new(@socket)
    end

    def on_connect
    end

    #
    # close
    #

    public

    def finish
      @started or raise IOError, 'closing already closed protocol'
      do_finish
      @started = false
      nil
    end

    private

    # abstract do_finish()

    def disconn_command
      @command.quit if @command and not @command.critical?
      @command = nil
    end

    def disconn_socket
      if @socket and not @socket.closed? then
        @socket.close
      end
      @socket = nil
    end
    
  end

  Session = Protocol


  class Response

    def initialize( ctype, code, msg )
      @code_type = ctype
      @code      = code
      @message   = msg
      super()
    end

    attr_reader :code_type
    attr_reader :code
    attr_reader :message
    alias msg message

    def inspect
      "#<#{self.class} #{@code}>"
    end

    def error!
      raise error_type().new(code + ' ' + @message.dump, self)
    end

    def error_type
      @code_type.error_type
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
  
    def initialize( msg, resp )
      super msg
      @response = resp
    end

    attr_reader :response
    alias data response

    def inspect
      "#<#{self.class} #{self.message}>"
    end
  
  end


  class Code

    def initialize( paren, err )
      @parents = [self] + paren
      @error_type = err
    end

    def parents
      @parents.dup
    end

    attr_reader :error_type

    def inspect
      "#<#{self.class} #{sprintf '0x%x', __id__}>"
    end

    def ===( response )
      response.code_type.parents.each {|c| c == self and return true }
      false
    end

    def mkchild( err = nil )
      self.class.new(@parents, err || @error_type)
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


  class Command

    def initialize( sock )
      @socket = sock
      @last_reply = nil
      @atomic = false
    end

    attr_accessor :socket
    attr_reader :last_reply

    def inspect
      "#<#{self.class} socket=#{@socket.inspect} critical=#{@atomic}>"
    end

    # abstract quit()

    private

    def check_reply( *oks )
      @last_reply = get_reply()
      reply_must @last_reply, *oks
    end

    # abstract get_reply()

    def reply_must( rep, *oks )
      oks.each do |i|
        return rep if i === rep
      end
      rep.error!
    end

    def getok( line, expect = SuccessCode )
      @socket.writeline line
      check_reply expect
    end

    #
    # critical session
    #

    public

    def critical?
      @atomic
    end

    def error_ok
      @atomic = false
    end

    private

    def atomic
      @atomic = true
      ret = yield
      @atomic = false
      ret
    end

  end


  class InternetMessageIO

    class << self
      alias open new
    end

    def initialize( addr, port, otime = nil, rtime = nil, dout = nil )
      @address      = addr
      @port         = port
      @read_timeout = rtime
      @debug_output = dout

      @socket  = nil
      @rbuf    = nil

      connect otime
      D 'opened'
    end

    attr_reader :address
    attr_reader :port

    def ip_address
      @socket or return ''
      @socket.addr[3]
    end

    attr_accessor :read_timeout

    attr_reader :socket

    def connect( otime )
      D "opening connection to #{@address}..."
      timeout( otime ) {
          @socket = TCPSocket.new( @address, @port )
      }
      @rbuf = ''
    end
    private :connect

    def close
      if @socket then
        @socket.close
        D 'closed'
      else
        D 'close call for already closed socket'
      end
      @socket = nil
      @rbuf = ''
    end

    def reopen( otime = nil )
      D 'reopening...'
      close
      connect otime
      D 'reopened'
    end

    def closed?
      not @socket
    end

    def inspect
      "#<#{type} #{closed? ? 'closed' : 'opened'}>"
    end

    ###
    ###  READ
    ###

    public

    def read( len, dest = '', ignore = false )
      D_off "reading #{len} bytes..."

      rsize = 0
      begin
        while rsize + @rbuf.size < len do
          rsize += rbuf_moveto(dest, @rbuf.size)
          rbuf_fill
        end
        rbuf_moveto dest, len - rsize
      rescue EOFError
        raise unless ignore
      end

      D_on "read #{len} bytes"
      dest
    end

    def read_all( dest = '' )
      D_off 'reading all...'

      rsize = 0
      begin
        while true do
          rsize += rbuf_moveto(dest, @rbuf.size)
          rbuf_fill
        end
      rescue EOFError
        ;
      end

      D_on "read #{rsize} bytes"
      dest
    end

    def readuntil( target, ignore = false )
      dest = ''
      begin
        while true do
          idx = @rbuf.index(target)
          break if idx
          rbuf_fill
        end
        rbuf_moveto dest, idx + target.size
      rescue EOFError
        raise unless ignore
        rbuf_moveto dest, @rbuf.size
      end
      dest
    end
        
    def readline
      ret = readuntil("\n")
      ret.chop!
      ret
    end

    private

    BLOCK_SIZE = 1024

    def rbuf_fill
      until IO.select [@socket], nil, nil, @read_timeout do
        on_read_timeout
      end
      @rbuf << @socket.sysread(BLOCK_SIZE)
    end

    def on_read_timeout
      raise TimeoutError, "socket read timeout (#{@read_timeout} sec)"
    end

    def rbuf_moveto( dest, len )
      dest << (s = @rbuf.slice!(0, len))
      @debug_output << %Q[-> #{s.dump}\n] if @debug_output
      len
    end

    #
    # message read
    #

    public

    def read_message_to( dest )
      D_off 'reading text...'

      rsize = 0
      while (str = readuntil("\r\n")) != ".\r\n" do
        rsize += str.size
        dest << str.sub(/\A\./, '')
      end

      D_on "read #{rsize} bytes"
      dest
    end
  
    # private use only (cannot handle 'break')
    def each_list_item
      while (str = readuntil("\r\n")) != ".\r\n" do
        yield str.chop
      end
    end


    ###
    ###  WRITE
    ###

    #
    # basic write
    #

    public

    def write( str )
      writing {
          do_write str
      }
    end

    def writeline( str )
      writing {
          do_write str + "\r\n"
      }
    end

    private

    def writing
      @writtensize = 0
      @debug_output << '<- ' if @debug_output
      yield
      @socket.flush
      @debug_output << "\n" if @debug_output
      @writtensize
    end

    def do_write( str )
      @debug_output << str.dump if @debug_output
      @writtensize += (n = @socket.write(str))
      n
    end

    #
    # message write
    #

    public

    def write_message( src )
      D_off "writing text from #{src.type}"

      wsize = using_each_crlf_line {
          wpend_in src
      }

      D_on "wrote #{wsize} bytes text"
      wsize
    end

    def through_message
      D_off 'writing text from block'

      wsize = using_each_crlf_line {
          yield WriteAdapter.new(self, :wpend_in)
      }

      D_on "wrote #{wsize} bytes text"
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

    def using_each_crlf_line
      writing {
          @wbuf = ''

          yield

          if not @wbuf.empty? then       # unterminated last line
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
          m = Regexp.last_match
          if m.begin(0) == buf.size - 1 and buf[-1] == ?\r then
            # "...\r" : can follow "\n..."
            break
          end
          str = buf[ beg ... m.begin(0) ]
          str.concat "\r\n"
          yield str
          beg = m.end(0)
        end
        @wbuf = buf[ beg ... buf.size ]
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
          i = src.read(2048)
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

    ###
    ### DEBUG
    ###

    private

    def D_off( msg )
      D msg
      @savedo, @debug_output = @debug_output, nil
    end

    def D_on( msg )
      @debug_output = @savedo
      D msg
    end

    def D( msg )
      @debug_output or return
      @debug_output << msg
      @debug_output << "\n"
    end
  
  end


  class WriteAdapter

    def initialize( sock, mid )
      @socket = sock
      @mid = mid
    end

    def inspect
      "#<#{type} socket=#{@socket.inspect}>"
    end

    def write( str )
      @socket.__send__ @mid, str
    end

    alias print write

    def <<( str )
      write str
      self
    end

    def puts( str = '' )
      write str.sub(/\n?/, "\n")
    end

    def printf( *args )
      write sprintf(*args)
    end
  
  end


  class ReadAdapter

    def initialize( block )
      @block = block
    end

    def inspect
      "#<#{type}>"
    end

    def <<( str )
      call_block str, &@block if @block
    end

    private

    def call_block( str )
      yield str
    end
  
  end


  # for backward compatibility
  module NetPrivate
    Response = ::Net::Response
    Command = ::Net::Command
    Socket = ::Net::InternetMessageIO
    BufferedSocket = ::Net::InternetMessageIO
    WriteAdapter = ::Net::WriteAdapter
    ReadAdapter = ::Net::ReadAdapter
  end
  BufferedSocket = ::Net::InternetMessageIO

end   # module Net

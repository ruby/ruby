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

    Version = '1.1.37'
    Revision = %q$Revision$.split(/\s+/)[1]


    class << self

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
    #   protocol_param port
    #   protocol_param command_type
    #   protocol_param socket_type   (optional)
    #
    #   private method do_start
    #   private method do_finish
    #
    #   private method conn_address
    #   private method conn_port
    #

    protocol_param :port,         'nil'
    protocol_param :command_type, 'nil'
    protocol_param :socket_type,  '::Net::BufferedSocket'


    def Protocol.start( address, port = nil, *args )
      instance = new( address, port )

      if block_given? then
        ret = nil
        instance.start( *args ) { ret = yield(instance) }
        ret
      else
        instance.start( *args )
        instance
      end
    end

    def initialize( addr, port = nil )
      @address = addr
      @port    = port || type.port

      @command = nil
      @socket  = nil

      @active = false

      @open_timeout = 30
      @read_timeout = 60

      @dout = nil
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

    def active?
      @active
    end

    def set_debug_output( arg )   # un-documented
      @dout = arg
    end

    alias set_pipe set_debug_output

    def inspect
      "#<#{type} #{address}:#{port} open=#{active?}>"
    end

    #
    # open
    #

    def start( *args )
      @active and raise IOError, 'protocol has been opened already'

      if block_given? then
        begin
          do_start( *args )
          @active = true
          return yield(self)
        ensure
          finish if @active
        end
      end

      do_start( *args )
      @active = true
      self
    end

    private

    # abstract do_start()

    def conn_socket
      @socket = type.socket_type.open(
              conn_address(), conn_port(),
              @open_timeout, @read_timeout, @dout )
      on_connect
    end

    alias conn_address address
    alias conn_port    port

    def reconn_socket
      @socket.reopen @open_timeout
      on_connect
    end

    def conn_command
      @command = type.command_type.new(@socket)
    end

    def on_connect
    end

    #
    # close
    #

    public

    def finish
      active? or raise IOError, 'closing already closed protocol'
      do_finish
      @active = false
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

    attr_reader :code_type, :code, :message
    alias msg message

    def inspect
      "#<#{type} #{code}>"
    end

    def error!
      raise @code_type.error_type.new( code + ' ' + msg.dump, self )
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

    attr :response
    alias data response

    def inspect
      "#<#{type}>"
    end
  
  end


  class Code

    def initialize( paren, err )
      @parents = [self] + paren
      @err = err
    end

    def parents
      @parents.dup
    end

    def inspect
      "#<#{type} #{sprintf '0x%x', __id__}>"
    end

    def error_type
      @err
    end

    def ===( response )
      response.code_type.parents.each {|c| return true if c == self }
      false
    end

    def mkchild( err = nil )
      type.new( @parents, err || @err )
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



  class WriteAdapter

    def initialize( sock, mid )
      @socket = sock
      @mid = mid
    end

    def inspect
      "#<#{type} socket=#{@socket.inspect}>"
    end

    def <<( str )
      @socket.__send__ @mid, str
      self
    end

    def write( str )
      @socket.__send__ @mid, str
    end

    alias print write

    def puts( str = '' )
      @socket.__send__ @mid, str.sub(/\n?/, "\n")
    end

    def printf( *args )
      @socket.__send__ @mid, sprintf(*args)
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



  class Command

    def initialize( sock )
      @socket = sock
      @last_reply = nil
      @atomic = false
    end

    attr_accessor :socket
    attr_reader :last_reply

    def inspect
      "#<#{type}>"
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
    # error handle
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

    def begin_atomic
      ret = @atomic
      @atomic = true
      not ret
    end

    def end_atomic
      @atomic = false
    end

    alias critical       atomic
    alias begin_critical begin_atomic
    alias end_critical   end_atomic

  end



  class BufferedSocket

    class << self
      alias open new
    end

    def initialize( addr, port, otime = nil, rtime = nil, dout = nil )
      @address      = addr
      @port         = port
      @read_timeout = rtime
      @debugout = dout

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
          @socket = TCPsocket.new( @address, @port )
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

    #
    # basic reader
    #

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

    #
    # line oriented reader
    #

    public

    def read_pendstr( dest )
      D_off 'reading text...'

      rsize = 0
      while (str = readuntil("\r\n")) != ".\r\n" do
        rsize += str.size
        str.gsub!( /\A\./, '' )
        dest << str
      end

      D_on "read #{rsize} bytes"
      dest
    end
  
    # private use only (can not handle 'break')
    def read_pendlist
    #  D_off 'reading list...'

      str = nil
      i = 0
      while (str = readuntil("\r\n")) != ".\r\n" do
        i += 1
        str.chop!
        yield str
      end

    #  D_on "read #{i} items"
    end

    #
    # lib (reader)
    #

    private

    BLOCK_SIZE = 1024 * 2

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
      @debugout << %Q[-> #{s.dump}\n] if @debugout
      len
    end


    ###
    ###  WRITE
    ###

    #
    # basic writer
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

    def write_bin( src, block )
      writing {
          if block then
            block.call WriteAdapter.new(self, :do_write)
          else
            src.each do |bin|
              do_write bin
            end
          end
      }
    end

    #
    # line oriented writer
    #

    public

    def write_pendstr( src, &block )
      D_off "writing text from #{src.type}"

      wsize = using_each_crlf_line {
          if block_given? then
            yield WriteAdapter.new(self, :wpend_in)
          else
            wpend_in src
          end
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

    #
    # lib (writer)
    #

    private

    def writing
      @writtensize = 0
      @debugout << '<- ' if @debugout
      yield
      @socket.flush
      @debugout << "\n" if @debugout
      @writtensize
    end

    def do_write( str )
      @debugout << str.dump if @debugout
      @writtensize += (n = @socket.write(str))
      n
    end

    ###
    ### DEBUG
    ###

    private

    def D_off( msg )
      D msg
      @savedo, @debugout = @debugout, nil
    end

    def D_on( msg )
      @debugout = @savedo
      D msg
    end

    def D( msg )
      @debugout or return
      @debugout << msg
      @debugout << "\n"
    end

  end


  # for backward compatibility
  module NetPrivate
    Response       = ::Net::Response
    WriteAdapter   = ::Net::WriteAdapter
    ReadAdapter    = ::Net::ReadAdapter
    Command        = ::Net::Command
    Socket         = ::Net::BufferedSocket
  end

end   # module Net

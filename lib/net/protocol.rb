=begin

= net/protocol.rb version 1.1.36

Copyright (c) 1999-2001 Yukihiro Matsumoto

written & maintained by Minero Aoki <aamine@loveruby.net>

This program is free software. You can re-distribute and/or
modify this program under the same terms as Ruby itself,
Ruby Distribute License or GNU General Public License.

NOTE: You can get Japanese version of this document from
Ruby Documentation Project (RDP):
((<URL:http://www.ruby-lang.org/~rubikitch/RDP.cgi>))

=end

require 'socket'
require 'timeout'


module Net

  module NetPrivate
  end

  def self.net_private( &block )
    ::Net::NetPrivate.module_eval( &block )
  end


  class Protocol

    Version = '1.1.36'

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
    # --- Configuration Staffs for Sub Classes ---
    #
    #   protocol_param port
    #   protocol_param command_type
    #   protocol_param socket_type   (optional)
    #
    #   private method do_start      (optional)
    #   private method do_finish     (optional)
    #
    #   private method on_connect    (optional)
    #   private method on_disconnect (optional)
    #

    protocol_param :port,         'nil'
    protocol_param :command_type, 'nil'
    protocol_param :socket_type,  '::Net::NetPrivate::Socket'


    def initialize( addr = nil, port = nil )
      @address = addr || 'localhost'
      @port    = port || type.port

      @command = nil
      @socket  = nil

      @active = false

      @open_timeout = nil
      @read_timeout = nil

      @dout = nil
    end

    attr_reader :address
    attr_reader :port

    attr_reader :command
    attr_reader :socket

    attr_accessor :open_timeout
    attr_accessor :read_timeout

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
    # open session
    #

    def start( *args )
      active? and raise IOError, 'protocol has been opened already'

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
      nil
    end

    private

    def _start( args )
      connect
      do_start( *args )
      @active = true
    end

    def connect
      conn_socket @address, @port
      conn_command @socket
      on_connect
    end

    def re_connect
      @socket.reopen @open_timeout
      on_connect
    end

    def conn_socket( addr, port )
      @socket = type.socket_type.open(
              addr, port, @open_timeout, @read_timeout, @dout )
    end

    def conn_command( sock )
      @command = type.command_type.new( sock )
    end

    def on_connect
    end

    def do_start
    end

    #
    # close session
    #

    public

    def finish
      active? or raise IOError, 'already closed protocol'

      do_finish if @command and not @command.critical?
      disconnect
      @active = false
      nil
    end

    private

    def do_finish
      @command.quit
    end

    def disconnect
      @command = nil
      if @socket and not @socket.closed? then
        @socket.close
      end
      @socket = nil
      on_disconnect
    end

    def on_disconnect
    end
    
  end

  Session = Protocol


  net_private {

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

    def error!
      raise code_type.error_type.new( code + ' ' + Net.quote(msg), self )
    end

  end

  }


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



  net_private {

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

    def <<( str )
      @sock.__send__ @mid, str
      self
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

    def initialize( addr, port, otime = nil, rtime = nil, dout = nil )
      @addr = addr
      @port = port

      @read_timeout = rtime

      @debugout = dout

      @socket = nil
      @sending = ''
      @buffer  = ''

      connect otime
      D 'opened'
    end

    def connect( otime )
      D "opening connection to #{@addr}..."
      timeout( otime ) {
        @socket = TCPsocket.new( @addr, @port )
      }
    end
    private :connect

    attr :pipe, true

    class << self
      alias open new
    end

    def inspect
      "#<#{type} #{closed? ? 'closed' : 'opened'}>"
    end

    def reopen( otime = nil )
      D 'reopening...'
      close
      connect otime
      D 'reopened'
    end

    attr :socket, true

    def close
      if @socket then
        @socket.close
        D 'closed'
      else
        D 'close call for already closed socket'
      end
      @socket = nil
      @buffer = ''
    end

    def closed?
      not @socket
    end

    def address
      @addr.dup
    end

    alias addr address

    attr_reader :port

    def ip_address
      @socket or return ''
      @socket.addr[3]
    end

    alias ipaddr ip_address

    attr_reader :sending


    #
    # read
    #

    public

    CRLF = "\r\n"

    def read( len, dest = '', igneof = false )
      D_off "reading #{len} bytes..."

      rsize = 0
      begin
        while rsize + @buffer.size < len do
          rsize += rbuf_moveto( dest, @buffer.size )
          rbuf_fill
        end
        rbuf_moveto dest, len - rsize
      rescue EOFError
        raise unless igneof
      end

      D_on "read #{len} bytes"
      dest
    end

    def read_all( dest = '' )
      D_off 'reading all...'

      rsize = 0
      begin
        while true do
          rsize += rbuf_moveto( dest, @buffer.size )
          rbuf_fill
        end
      rescue EOFError
        ;
      end

      D_on "read #{rsize} bytes"
      dest
    end

    def readuntil( target, igneof = false )
      dest = ''
      begin
        while true do
          idx = @buffer.index( target )
          break if idx
          rbuf_fill
        end
        rbuf_moveto dest, idx + target.size
      rescue EOFError
        raise unless igneof
        rbuf_moveto dest, @buffer.size
      end
      dest
    end
        
    def readline
      ret = readuntil( "\n" )
      ret.chop!
      ret
    end

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


    private


    READ_SIZE = 1024 * 4

    def rbuf_fill
      unless IO.select [@socket], nil, nil, @read_timeout then
        on_read_timeout
      end
      @buffer << @socket.sysread( READ_SIZE )
    end

    def on_read_timeout
      raise TimeoutError, "socket read timeout (#{@read_timeout} sec)"
    end

    def rbuf_moveto( dest, len )
      bsi = @buffer.size
      s = @buffer[ 0, len ]
      dest << s
      @buffer = @buffer[ len, bsi - len ]

      @debugout << %<read  "#{Net.quote s}"\n> if @debugout
      len
    end


    #
    # write interfece
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
          block.call ::Net::NetPrivate::WriteAdapter.new( self, :do_write )
        else
          src.each do |bin|
            do_write bin
          end
        end
      }
    end

    def write_pendstr( src, block )
      D_off "writing text from #{src.type}"

      wsize = use_each_crlf_line {
        if block then
          block.call ::Net::NetPrivate::WriteAdapter.new( self, :wpend_in )
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

      if @debugout then
        @debugout << 'write "'
        @debugout << @sending
        @debugout << "\"\n"
      end
      @socket.flush
      @writtensize
    end

    def do_write( arg )
      if @debugout or @sending.size < 128 then
        @sending << Net.quote( arg )
      else
        @sending << '...' unless @sending[-1] == ?.
      end

      s = @socket.write( arg )
      @writtensize += s
      s
    end


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

  }


  def Net.quote( str )
    str = str.gsub( "\n", '\\n' )
    str.gsub!( "\r", '\\r' )
    str.gsub!( "\t", '\\t' )
    str
  end

end   # module Net

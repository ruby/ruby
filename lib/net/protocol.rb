=begin

= net/protocol.rb

Copyright (c) 1999-2003 Yukihiro Matsumoto
Copyright (c) 1999-2003 Minero Aoki

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

  class ProtocolError          < StandardError; end
  class ProtoSyntaxError       < ProtocolError; end
  class ProtoFatalError        < ProtocolError; end
  class ProtoUnknownError      < ProtocolError; end
  class ProtoServerError       < ProtocolError; end
  class ProtoAuthError         < ProtocolError; end
  class ProtoCommandError      < ProtocolError; end
  class ProtoRetriableError    < ProtocolError; end
  ProtocRetryError = ProtoRetriableError


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
      timeout(otime) {
          @socket = TCPsocket.new(@address, @port)
      }
      @rbuf = ''
    end
    private :connect

    def close
      if @socket
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
      "#<#{self.class} #{closed? ? 'closed' : 'opened'}>"
    end

    ###
    ###  READ
    ###

    public

    def read( len, dest = '', ignore = false )
      D_off "reading #{len} bytes..."

      rsize = 0
      begin
        while rsize + @rbuf.size < len
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
        while true
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
        until idx = @rbuf.index(target)
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
      until IO.select [@socket], nil, nil, @read_timeout
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
      while (str = readuntil("\r\n")) != ".\r\n"
        rsize += str.size
        dest << str.sub(/\A\./, '')
      end

      D_on "read #{rsize} bytes"
      dest
    end
  
    # private use only (cannot handle 'break')
    def each_list_item
      while (str = readuntil("\r\n")) != ".\r\n"
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
      D_off "writing text from #{src.class}"

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
      each_crlf_line(src) do |line|
        do_write '.' if line[0] == ?.
        do_write line
      end

      @writtensize - pre
    end

    def using_each_crlf_line
      writing {
          @wbuf = ''

          yield

          if not @wbuf.empty?       # unterminated last line
            if @wbuf[-1] == ?\r
              @wbuf.chop!
            end
            @wbuf.concat "\r\n"
            do_write @wbuf
          elsif @writtensize == 0   # empty src
            do_write "\r\n"
          end
          do_write ".\r\n"

          @wbuf = nil
      }
    end

    def each_crlf_line( src )
      str = m = beg = nil

      adding(src) do
        beg = 0
        buf = @wbuf
        while buf.index(/\n|\r\n|\r/, beg)
          m = Regexp.last_match
          if m.begin(0) == buf.size - 1 and buf[-1] == ?\r
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
      i = s = nil

      case src
      when String
        0.step(src.size - 1, 2048) do |i|
          @wbuf << src[i,2048]
          yield
        end

      when File
        while s = src.read(2048)
          s[0,0] = @wbuf
          @wbuf = s
          yield
        end

      else
        src.each do |s|
          @wbuf << s
          yield if @wbuf.size > 2048
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
      "#<#{self.class} socket=#{@socket.inspect}>"
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
      "#<#{self.class}>"
    end

    def <<( str )
      call_block(str, &@block) if @block
    end

    private

    def call_block( str )
      yield str
    end
  
  end

end   # module Net

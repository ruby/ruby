#
# = net/protocol.rb
#
#--
# Copyright (c) 1999-2003 Yukihiro Matsumoto
# Copyright (c) 1999-2003 Minero Aoki
#
# written and maintained by Minero Aoki <aamine@loveruby.net>
#
# This program is free software. You can re-distribute and/or
# modify this program under the same terms as Ruby itself,
# Ruby Distribute License or GNU General Public License.
#
# $Id$
#++
#
# WARNING: This file is going to remove.
# Do not rely on the implementation written in this file.
#

require 'socket'
require 'timeout'

module Net # :nodoc:

  class Protocol   #:nodoc: internal use only
    private
    def Protocol.protocol_param( name, val )
      module_eval(<<-End, __FILE__, __LINE__ + 1)
        def #{name}
          #{val}
        end
      End
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


  class InternetMessageIO   #:nodoc: internal use only

    class << self
      alias open new
    end

    def initialize( addr, port,
                    open_timeout = nil, read_timeout = nil,
                    debug_output = nil )
      @address      = addr
      @port         = port
      @read_timeout = read_timeout
      @debug_output = debug_output
      @socket       = nil
      @rbuf         = nil   # read buffer
      @wbuf         = nil   # write buffer
      connect open_timeout
      LOG 'opened'
    end

    attr_reader :address
    attr_reader :port

    def ip_address
      return '' unless @socket
      @socket.addr[3]
    end

    attr_accessor :read_timeout

    attr_reader :socket

    def connect( open_timeout )
      LOG "opening connection to #{@address}..."
      timeout(open_timeout) {
        @socket = TCPsocket.new(@address, @port)
      }
      @rbuf = ''
    end
    private :connect

    def close
      if @socket
        @socket.close
        LOG 'closed'
      else
        LOG 'close call for already closed socket'
      end
      @socket = nil
      @rbuf = ''
    end

    def reopen( open_timeout = nil )
      LOG 'reopening...'
      close
      connect open_timeout
      LOG 'reopened'
    end

    def closed?
      not @socket
    end

    def inspect
      "#<#{self.class} #{closed?() ? 'closed' : 'opened'}>"
    end

    ###
    ###  READ
    ###

    public

    def read( len, dest = '', ignore_eof = false )
      LOG "reading #{len} bytes..."
      # LOG_off()   # experimental: [ruby-list:38800]
      read_bytes = 0
      begin
        while read_bytes + @rbuf.size < len
          read_bytes += rbuf_moveto(dest, @rbuf.size)
          rbuf_fill
        end
        rbuf_moveto dest, len - read_bytes
      rescue EOFError
        raise unless ignore_eof
      end
      # LOG_on()
      LOG "read #{read_bytes} bytes"
      dest
    end

    def read_all( dest = '' )
      LOG 'reading all...'
      # LOG_off()   # experimental: [ruby-list:38800]
      read_bytes = 0
      begin
        while true
          read_bytes += rbuf_moveto(dest, @rbuf.size)
          rbuf_fill
        end
      rescue EOFError
        ;
      end
      # LOG_on()
      LOG "read #{read_bytes} bytes"
      dest
    end

    def readuntil( terminator, ignore_eof = false )
      dest = ''
      begin
        until idx = @rbuf.index(terminator)
          rbuf_fill
        end
        rbuf_moveto dest, idx + terminator.size
      rescue EOFError
        raise unless ignore_eof
        rbuf_moveto dest, @rbuf.size
      end
      dest
    end
        
    def readline
      readuntil("\n").chop
    end

    def each_message_chunk
      LOG 'reading message...'
      LOG_off()
      read_bytes = 0
      while (line = readuntil("\r\n")) != ".\r\n"
        read_bytes += line.size
        yield line.sub(/\A\./, '')
      end
      LOG_on()
      LOG "read message (#{read_bytes} bytes)"
    end
  
    # *library private* (cannot handle 'break')
    def each_list_item
      while (str = readuntil("\r\n")) != ".\r\n"
        yield str.chop
      end
    end

    private

    def rbuf_fill
      until IO.select([@socket], nil, nil, @read_timeout)
        raise TimeoutError, "socket read timeout (#{@read_timeout} sec)"
      end
      @rbuf << @socket.sysread(1024)
    end

    def rbuf_moveto( dest, len )
      dest << (s = @rbuf.slice!(0, len))
      @debug_output << %Q[-> #{s.dump}\n] if @debug_output
      len
    end

    ###
    ###  WRITE
    ###

    public

    def write( str )
      writing {
        write0 str
      }
    end

    def writeline( str )
      writing {
        write0 str + "\r\n"
      }
    end

    def write_message( src )
      LOG "writing message from #{src.class}"
      LOG_off()
      len = using_each_crlf_line {
        write_message_0 src
      }
      LOG_on()
      LOG "wrote #{len} bytes"
      len
    end

    def write_message_by_block( &block )
      LOG 'writing message from block'
      LOG_off()
      len = using_each_crlf_line {
        begin
          block.call(WriteAdapter.new(self, :write_message_0))
        rescue LocalJumpError
          # allow `break' from writer block
        end
      }
      LOG_on()
      LOG "wrote #{len} bytes"
      len
    end

    private

    def writing
      @written_bytes = 0
      @debug_output << '<- ' if @debug_output
      yield
      @socket.flush
      @debug_output << "\n" if @debug_output
      bytes = @written_bytes
      @written_bytes = nil
      bytes
    end

    def write0( str )
      @debug_output << str.dump if @debug_output
      len = @socket.write(str)
      @written_bytes += len
      len
    end

    #
    # Reads string from src calling :each, and write to @socket.
    # Escapes '.' on the each line head.
    #
    def write_message_0( src )
      prev = @written_bytes
      each_crlf_line(src) do |line|
        if line[0] == ?.
        then write0 '.' + line
        else write0       line
        end
      end
      @written_bytes - prev
    end

    #
    # setup @wbuf for each_crlf_line.
    #
    def using_each_crlf_line
      writing {
          @wbuf = ''
          yield
          if not @wbuf.empty?       # unterminated last line
            if @wbuf[-1] == ?\r
              @wbuf.chop!
            end
            @wbuf.concat "\r\n"
            write0 @wbuf
          elsif @written_bytes == 0   # empty src
            write0 "\r\n"
          end
          write0 ".\r\n"
          @wbuf = nil
      }
    end

    #
    # extract a CR-LF-terminating-line from @wbuf and yield it.
    #
    def each_crlf_line( src )
      adding(src) do
        beg = 0
        buf = @wbuf
        while buf.index(/\n|\r\n|\r/, beg)
          m = Regexp.last_match
          if (m.begin(0) == buf.length - 1) and buf[-1] == ?\r
            # "...\r" : can follow "\n..."
            break
          end
          str = buf[beg ... m.begin(0)]
          str.concat "\r\n"
          yield str
          beg = m.end(0)
        end
        @wbuf = buf[beg ... buf.length]
      end
    end

    #
    # Reads strings from SRC and add to @wbuf, then yield.
    #
    def adding( src )
      case src
      when String    # for speeding up.
        0.step(src.size - 1, 2048) do |i|
          @wbuf << src[i,2048]
          yield
        end

      when File    # for speeding up.
        while s = src.read(2048)
          s[0,0] = @wbuf
          @wbuf = s
          yield
        end

      else    # generic reader
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

    def LOG_off
      @save_debug_out = @debug_output
      @debug_output = nil
    end

    def LOG_on
      @debug_output = @save_debug_out
    end

    def LOG( msg )
      return unless @debug_output
      @debug_output << msg
      @debug_output << "\n"
    end
  
  end


  #
  # The writer adapter class
  #
  class WriteAdapter

    def initialize( sock, mid )
      @socket = sock
      @method_id = mid
    end

    def inspect
      "#<#{self.class} socket=#{@socket.inspect}>"
    end

    def write( str )
      @socket.__send__(@method_id, str)
    end

    alias print write

    def <<( str )
      write str
      self
    end

    def puts( str = '' )
      write str.sub(/\n?\z/, "\n")
    end

    def printf( *args )
      write sprintf(*args)
    end
  
  end


  class ReadAdapter   #:nodoc: internal use only

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

    #
    # This method is needed because @block must be called by yield,
    # not Proc#call.  You can see difference when using `break' in
    # the block.
    #
    def call_block( str )
      yield str
    end
  
  end


  module NetPrivate   #:nodoc: obsolete
    Socket = ::Net::InternetMessageIO
  end

end   # module Net

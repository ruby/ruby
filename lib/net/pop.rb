#
# pop.rb  version 1.0.1
#
#   author: Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#

require 'net/session'
require 'md5'


module Net

  class POP3Session < Session

    attr :mails

    def each() @mails.each{|m| yield m} end


    private


    def proto_initialize
      @proto_type = POP3Command
      @port       = 110
      @mails      = [].freeze
    end


    def do_start( acnt, pwd )
      @proto.auth( acnt, pwd )
      @mails = []
      @proto.list.each_with_index do |size,idx|
        if size then
          @mails.push POPMail.new( idx, size, @proto )
        end
      end
      @mails.freeze
    end


    def do_finish
      @proto.quit
    end



    class POPMail

      def initialize( idx, siz, pro )
        @num     = idx
        @size    = siz
        @proto   = pro

        @deleted = false
      end

      attr :size

      def all( dest = '' )
        @proto.retr( @num, dest )
      end
      alias pop all
      alias mail all

      def top( lines, dest = '' )
        @proto.top( @num, lines, dest )
      end

      def header( dest = '' )
        top( 0, dest )
      end

      def delete
        @proto.dele( @num )
        @deleted = true
      end
      alias delete! delete

      def deleted?
        @deleted
      end

    end

  end


  class APOPSession < POP3Session

    def proto_initialize
      super
      @proto_type = APOPCommand
    end

  end


  POPSession = POP3Session
  POP3       = POP3Session



  class POP3Command < Command

    def auth( acnt, pass )
      @socket.writeline( 'USER ' + acnt )
      check_reply_auth

      @socket.writeline( 'PASS ' + pass )
      ret = check_reply_auth

      return ret
    end


    def list
      @socket.writeline( 'LIST' )
      check_reply( SuccessCode )
      
      arr = []
      @socket.read_pendlist do |line|
        num, siz = line.split( / +/o )
        arr[ num.to_i ] = siz.to_i
      end

      return arr
    end


    def rset
      @socket.writeline( 'RSET' )
      check_reply( SuccessCode )
    end


    def top( num, lines = 0, dest = '' )
      @socket.writeline( sprintf( 'TOP %d %d', num, lines ) )
      check_reply( SuccessCode )

      return @socket.read_pendstr( dest )
    end


    def retr( num, dest = '', &block )
      @socket.writeline( sprintf( 'RETR %d', num ) )
      check_reply( SuccessCode )

      return @socket.read_pendstr( dest, &block )
    end

    
    def dele( num )
      @socket.writeline( sprintf( 'DELE %s', num ) )
      check_reply( SuccessCode )
    end



    private


    def do_quit
      @socket.writeline( 'QUIT' )
      check_reply( SuccessCode )
    end


    def check_reply_auth
      begin
        cod = check_reply( SuccessCode )
      rescue ProtocolError
        raise ProtoAuthError, 'Fail to POP authentication'
      end

      return cod
    end


    def get_reply
      str = @socket.readline

      if /\A\+/ === str then
        return SuccessCode.new( str[0,3], str[3, str.size - 3].strip )
      else
        return ErrorCode.new( str[0,4], str[4, str.size - 4].strip )
      end
    end

  end



  class APOPCommand < POP3Command

    def initialize( sock )
      rep = super( sock )

      /<[^@]+@[^@>]+>/o === rep.msg
      @stamp = $&
      unless @stamp then
        raise ProtoAuthError, "This is not APOP server: can't login"
      end
    end


    def auth( acnt, pass )
      @socket.writeline( "APOP #{acnt} #{digest(@stamp + pass)}" )
      return check_reply_auth
    end


    def digest( str )
      temp = MD5.new( str ).digest

      ret = ''
      temp.each_byte do |i|
        ret << sprintf( '%02x', i )
      end
      return ret
    end
      
  end


  unless Session::Version == '1.0.1' then
    $stderr.puts "WARNING: wrong version of session.rb & pop.rb"
  end

end

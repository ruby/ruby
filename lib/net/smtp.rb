#
# smtp.rb  version 1.0.1
#
#   author Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#

require 'net/session'


module Net

  class SMTPSession < Session

    def proto_initialize
      @proto_type = SMTPCommand
      @port       = 25
    end

    def sendmail( mailsrc, fromaddr, toaddrs )
      @proto.mailfrom( fromaddr )
      @proto.rcpt( toaddrs )
      @proto.data
      @proto.sendmail( mailsrc )
    end


    private


    def do_start( helodom = nil )
      unless helodom then
        helodom = ENV[ 'HOSTNAME' ]
      end
      @proto.helo( helodom )
    end

    def do_finish
      @proto.quit
    end

  end

  SMTP = SMTPSession



  class SMTPCommand < Command

    def helo( fromdom )
      @socket.writeline( 'HELO ' << fromdom )
      check_reply( SuccessCode )
    end


    def mailfrom( fromaddr )
      @socket.writeline( 'MAIL FROM:<' + fromaddr + '>' )
      check_reply( SuccessCode )
    end


    def rcpt( toaddrs )
      toaddrs.each do |i|
        @socket.writeline( 'RCPT TO:<' + i + '>' )
        check_reply( SuccessCode )
      end
    end


    def data
      @socket.writeline( 'DATA' )
      check_reply( ContinueCode )
    end


    def sendmail( mailsrc )
      @socket.write_pendstr( mailsrc )
      check_reply( SuccessCode )
    end


    private


    def do_quit
      @socket.writeline( 'QUIT' )
      check_reply( SuccessCode )
    end


    def get_reply
      arr = read_reply
      stat = arr[0][0,3]

      cls = UnknownCode
      case stat[0]
      when ?2 then cls = SuccessCode
      when ?3 then cls = ContinueCode
      when ?4 then cls = ServerBusyCode
      when ?5 then
        case stat[1]
        when ?0 then cls = SyntaxErrorCode
        when ?5 then cls = FatalErrorCode
        end
      end

      return cls.new( stat, arr.join('') )
    end


    def read_reply
      arr = []

      while (str = @socket.readline)[3] == ?- do   # ex: "210-..."
        arr.push str
      end
      arr.push str

      return arr
    end

  end


  unless Session::Version == '1.0.1' then
    $stderr.puts "WARNING: wrong version of session.rb & smtp.rb"
  end

end

=begin

= Net module version 1.0.2 reference manual

smtp.rb written by Minero Aoki <aamine@dp.u-netsurf.ne.jp>

This library is distributed under the terms of Ruby style license.
You can freely redistribute/modify/copy this file.

=end


require 'net/session'


=begin

== Net::SMTPSession

=== Super Class

Net::Session

=== Class Methods

: new( address = 'localhost', port = 25 )

  This method create new SMTPSession object.

=end

module Net

  class SMTPSession < Session

    def proto_initialize
      @proto_type = SMTPCommand
      @port       = 25
    end

=begin

=== Methods

: start( helo_domain = ENV['HOSTNAME'] )

  This method opens TCP connection and start SMTP session.
  If session had been started, do nothing and return false.

: sendmail( mailsrc, from_domain, to_addrs )

  This method sends 'mailsrc' as mail. SMTPSession read strings from 'mailsrc'
  by calling 'each' iterator, and convert them into "\r\n" terminated string when write.

  SMTPSession's Exceptions are:
  * Protocol::ProtoSyntaxError: syntax error (errno.500)
  * Protocol::ProtoFatalError: fatal error (errno.550)
  * Protocol::ProtoUnknownError: unknown error
  * Protocol::ProtoServerBusy: temporary error (errno.420/450)

: finish

  This method closes SMTP session.
  If session had not started, do nothind and return false.

=end

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


=begin

== Net::SMTPCommand

=== Super Class

Net::Command

=== Class Methods

: new( socket )

  This method creates new SMTPCommand object, and open SMTP session.


=== Methods

: helo( helo_domain )

  This method send "HELO" command and start SMTP session.<br>
  helo_domain is localhost's FQDN.

: mailfrom( from_addr )

  This method sends "MAIL FROM" command.<br>
  from_addr is your mail address(????@????).

: rcpt( to_addrs )

  This method sends "RCPT TO" command.<br>
  to_addrs is array of mail address(???@???) of destination.

: data( mailsrc )

  This method send 'mailsrc' as mail. SMTP reads strings from 'mailsrc'
  by calling 'each' iterator. 

: quit

  This method sends "QUIT" command and ends SMTP session.

=end

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


  unless Session::Version == '1.0.2' then
    $stderr.puts "WARNING: wrong version of session.rb & smtp.rb"
  end

end

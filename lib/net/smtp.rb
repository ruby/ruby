=begin

= net/smtp.rb

written by Minero Aoki <aamine@dp.u-netsurf.ne.jp>

This library is distributed under the terms of the Ruby license.
You can freely distribute/modify this library.

=end


require 'net/session'


module Net


=begin

== Net::SMTP

=== Super Class

Net::Protocol

=== Class Methods

: new( address = 'localhost', port = 25 )
  This method create new SMTP object.


=== Methods

: start( helo_domain = ENV['HOSTNAME'] )
  This method opens TCP connection and start SMTP.
  If protocol had been started, do nothing and return false.

: sendmail( mailsrc, from_domain, to_addrs )
  This method sends 'mailsrc' as mail. SMTPSession read strings
  from 'mailsrc' by calling 'each' iterator, and convert them
  into "\r\n" terminated string when write.

  Exceptions which SMTP raises are:
  * Net::ProtoSyntaxError: syntax error (errno.500)
  * Net::ProtoFatalError: fatal error (errno.550)
  * Net::ProtoUnknownError: unknown error
  * Net::ProtoServerBusy: temporary error (errno.420/450)

: finish
  This method ends SMTP.
  If protocol had not started, do nothind and return false.

=end

  class SMTP < Protocol

    Version = '1.1.3'

    protocol_param :port,         '25'
    protocol_param :command_type, '::Net::SMTPCommand'


    def sendmail( mailsrc, fromaddr, toaddrs )
      @command.mailfrom fromaddr
      @command.rcpt toaddrs
      @command.data
      @command.sendmail mailsrc
    end


    private


    def do_start( helodom = ENV['HOSTNAME'] )
      unless helodom then
        raise ArgumentError, "cannot get hostname"
      end
      @command.helo helodom
    end

  end

  SMTPSession = SMTP


=begin

== Net::SMTPCommand

=== Super Class

Net::Command

=== Class Methods

: new( socket )
  This method creates new SMTPCommand object, and open SMTP.


=== Methods

: helo( helo_domain )
  This method send "HELO" command and start SMTP.
  helo_domain is localhost's FQDN.

: mailfrom( from_addr )
  This method sends "MAIL FROM" command.
  from_addr is your mail address(????@????).

: rcpt( to_addrs )
  This method sends "RCPT TO" command.
  to_addrs is array of mail address(???@???) of destination.

: data( mailsrc )
  This method send 'mailsrc' as mail. SMTP reads strings from 'mailsrc'
  by calling 'each' iterator. 

: quit
  This method sends "QUIT" command and ends SMTP session.

=end

  class SMTPCommand < Command

    def initialize( sock )
      super
      check_reply SuccessCode
    end


    def helo( fromdom )
      getok sprintf( 'HELO %s', fromdom )
    end


    def mailfrom( fromaddr )
      getok sprintf( 'MAIL FROM:<%s>', fromaddr )
    end


    def rcpt( toaddrs )
      toaddrs.each do |i|
        getok sprintf( 'RCPT TO:<%s>', i )
      end
    end


    def data
      getok 'DATA', ContinueCode
    end


    def writemail( mailsrc )
      @socket.write_pendstr mailsrc
      check_reply SuccessCode
    end
    alias sendmail writemail


    private


    def do_quit
      getok 'QUIT'
    end


    def get_reply
      arr = read_reply
      stat = arr[0][0,3]

      klass = UnknownCode
      klass = case stat[0]
              when ?2 then SuccessCode
              when ?3 then ContinueCode
              when ?4 then ServerBusyCode
              when ?5 then
                case stat[1]
                when ?0 then SyntaxErrorCode
                when ?5 then FatalErrorCode
                end
              end

      klass.new( stat, arr.join('') )
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

end

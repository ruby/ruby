=begin

= net/smtp.rb

written by Minero Aoki <aamine@dp.u-netsurf.ne.jp>

This library is distributed under the terms of the Ruby license.
You can freely distribute/modify this library.

=end


require 'net/protocol'


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

: sendmail( mailsrc, from_addr, to_addrs )
  This method sends 'mailsrc' as mail. SMTPSession read strings
  from 'mailsrc' by calling 'each' iterator, and convert them
  into "\r\n" terminated string when write.

  Exceptions which SMTP raises are:
  * Net::ProtoSyntaxError: syntax error (errno.500)
  * Net::ProtoFatalError: fatal error (errno.550)
  * Net::ProtoUnknownError: unknown error
  * Net::ProtoServerBusy: temporary error (errno.420/450)

: ready( from_addr, to_addrs ) {|adapter| .... }
  This method stands by the SMTP object for sending mail.
  In the block of this iterator, you can call ONLY 'write' method
  for 'adapter'.

    # usage example

    SMTP.start( 'localhost', 25 ) do |smtp|
      smtp.ready( from, to ) do |adapter|
        adapter.write str1
        adapter.write str2
        adapter.write str3
      end
    end

: finish
  This method ends SMTP.
  If protocol had not started, do nothind and return false.

=end

  class SMTP < Protocol

    protocol_param :port,         '25'
    protocol_param :command_type, '::Net::SMTPCommand'


    def sendmail( mailsrc, fromaddr, toaddrs )
      do_ready fromaddr, toaddrs
      @command.write_mail mailsrc
    end

    def ready( fromaddr, toaddrs, &block )
      do_ready fromaddr, toaddrs
      @command.write_mail( &block )
    end


    attr :esmtp


    private


    def do_ready
      @command.mailfrom fromaddr
      @command.rcpt toaddrs
      @command.data
    end

    def do_start( helodom = ENV['HOSTNAME'] )
      unless helodom then
        raise ArgumentError, "cannot get hostname"
      end

      @esmtp = false
      begin
        @command.ehlo helodom
        @esmtp = true
      rescue ProtocolError
        @command.helo helodom
      end
    end

  end

  SMTPSession = SMTP



  class SMTPCommand < Command

    def initialize( sock )
      super
      check_reply SuccessCode
    end


    def helo( fromdom )
      getok sprintf( 'HELO %s', fromdom )
    end


    def ehlo( fromdom )
      getok sprintf( 'EHLO %s', fromdom )
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


    def write_mail( mailsrc = nil, &block )
      @socket.write_pendstr mailsrc, &block
      check_reply SuccessCode
    end
    alias sendmail write_mail


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

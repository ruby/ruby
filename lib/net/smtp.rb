=begin

= net/smtp.rb

Copyright (c) 1999-2003 Yukihiro Matsumoto
Copyright (c) 1999-2003 Minero Aoki

written & maintained by Minero Aoki <aamine@loveruby.net>

This program is free software. You can re-distribute and/or
modify this program under the same terms as Ruby itself,
Ruby Distribute License or GNU General Public License.

NOTE: You can find Japanese version of this document in
the doc/net directory of the standard ruby interpreter package.

$Id$

== What is This Module?

This module provides your program the functions to send internet
mail via SMTP, Simple Mail Transfer Protocol. For details of
SMTP itself, refer [RFC2821] ((<URL:http://www.ietf.org/rfc/rfc2821.txt>)).

== What is NOT This Module?

This module does NOT provide functions to compose internet mails.
You must create it by yourself. If you want better mail support,
try RubyMail or TMail. You can get both libraries from RAA.
((<URL:http://www.ruby-lang.org/en/raa.html>))

FYI: official documentation of internet mail is:
[RFC2822] ((<URL:http://www.ietf.org/rfc/rfc2822.txt>)).

== Examples

=== Sending Mail

You must open connection to SMTP server before sending mails.
First argument is the address of SMTP server, and second argument
is port number. Using SMTP.start with block is the most simple way
to do it. SMTP connection is closed automatically after block is
executed.

    require 'net/smtp'
    Net::SMTP.start('your.smtp.server', 25) {|smtp|
        # use SMTP object only in this block
    }

Replace 'your.smtp.server' by your SMTP server. Normally
your system manager or internet provider is supplying a server
for you.

Then you can send mail.

    mail_text = <<END_OF_MAIL
    From: Your Name <your@mail.address>
    To: Dest Address <to@some.domain>
    Subject: test mail
    Date: Sat, 23 Jun 2001 16:26:43 +0900
    Message-Id: <unique.message.id.string@some.domain>

    This is test mail.
    END_OF_MAIL

    require 'net/smtp'
    Net::SMTP.start('your.smtp.server', 25) {|smtp|
        smtp.send_mail mail_text,
                       'your@mail.address',
                       'his_addess@example.com'
    }

=== Closing Session

You MUST close SMTP session after sending mails, by calling #finish
method. You can also use block form of SMTP.start/SMTP#start, which
closes session automatically. I strongly recommend later one. It is
more beautiful and simple.

    # using SMTP#finish
    smtp = Net::SMTP.start('your.smtp.server', 25)
    smtp.send_mail mail_string, 'from@address', 'to@address'
    smtp.finish

    # using block form of SMTP.start
    Net::SMTP.start('your.smtp.server', 25) {|smtp|
        smtp.send_mail mail_string, 'from@address', 'to@address'
    }

=== Sending Mails From non-String Sources

In an example above I has sent mail from String (here document literal).
SMTP#send_mail accepts any objects which has "each" method
like File and Array.

    require 'net/smtp'
    Net::SMTP.start('your.smtp.server', 25) {|smtp|
        File.open('Mail/draft/1') {|f|
            smtp.send_mail f, 'your@mail.address', 'to@some.domain'
        }
    }

=== HELO domain

In almost all situation, you must designate the third argument
of SMTP.start/SMTP#start. It is the domain name which you are on
(the host to send mail from). It is called "HELO domain".
SMTP server will judge if he/she should send or reject
the SMTP session by inspecting HELO domain.

    Net::SMTP.start( 'your.smtp.server', 25,
                     'mail.from.domain' ) {|smtp|


== class Net::SMTP

=== Class Methods

: new( address, port = 25 )
    creates a new Net::SMTP object.

: start( address, port = 25, helo_domain = 'localhost.localdomain', account = nil, password = nil, authtype = nil )
: start( address, port = 25, helo_domain = 'localhost.localdomain', account = nil, password = nil, authtype = nil ) {|smtp| .... }
    is equal to
        Net::SMTP.new(address,port).start(helo_domain,account,password,authtype)

        # example
        Net::SMTP.start( 'your.smtp.server' ) {
            smtp.send_mail mail_string, 'from@mail.address', 'dest@mail.address'
        }

=== Instance Methods

: start( helo_domain = <local host name>, account = nil, password = nil, authtype = nil )
: start( helo_domain = <local host name>, account = nil, password = nil, authtype = nil ) {|smtp| .... }
    opens TCP connection and starts SMTP session.
    HELO_DOMAIN is a domain that you'll dispatch mails from.
    If protocol had been started, raises IOError.

    When this methods is called with block, give a SMTP object to block and
    close session after block call finished.

    If both of account and password are given, is trying to get
    authentication by using AUTH command. :plain or :cram_md5 is
    allowed for AUTHTYPE.

: started?
    true if SMTP session is started.

: esmtp?
    true if the SMTP object uses ESMTP.

: esmtp=(b)
    set wheather SMTP should use ESMTP.

: address
    the address to connect

: port
    the port number to connect

: open_timeout
: open_timeout=(n)
    seconds to wait until connection is opened.
    If SMTP object cannot open a conection in this seconds,
    it raises TimeoutError exception.

: read_timeout
: read_timeout=(n)
    seconds to wait until reading one block (by one read(1) call).
    If SMTP object cannot open a conection in this seconds,
    it raises TimeoutError exception.

: finish
    finishes SMTP session.
    If SMTP session had not started, raises an IOError.

: send_mail( mailsrc, from_addr, *to_addrs )
    This method sends MAILSRC as mail. A SMTP object read strings
    from MAILSRC by calling "each" iterator, with converting them
    into CRLF ("\r\n") terminated string when write.

    FROM_ADDR must be a String, representing source mail address.
    TO_ADDRS must be Strings or an Array of Strings, representing
    destination mail addresses.

        # example
        Net::SMTP.start( 'your.smtp.server' ) {|smtp|
            smtp.send_mail mail_string,
                           'from@mail.address',
                           'dest@mail.address' 'dest2@mail.address'
        }

: ready( from_addr, *to_addrs ) {|adapter| .... }
    This method stands by the SMTP object for sending mail and
    gives adapter object to the block. ADAPTER has these 5 methods:

        puts print printf write <<

    FROM_ADDR must be a String, representing source mail address.
    TO_ADDRS must be Strings or an Array of Strings, representing
    destination mail addresses.

        # example
        Net::SMTP.start( 'your.smtp.server', 25 ) {|smtp|
	    smtp.ready( 'from@mail.addr', 'dest@mail.addr' ) {|f|
                f.puts 'From: aamine@loveruby.net'
                f.puts 'To: someone@somedomain.org'
                f.puts 'Subject: test mail'
                f.puts
                f.puts 'This is test mail.'
	    }
        }

== Exceptions

SMTP objects raise these exceptions:

: Net::ProtoSyntaxError
    Syntax error (errno.500)
: Net::ProtoFatalError
    Fatal error (errno.550)
: Net::ProtoUnknownError
    Unknown error. (is probably bug)
: Net::ProtoServerBusy
    Temporal error (errno.420/450)

=end

require 'net/protocol'
require 'digest/md5'


module Net

  class SMTP < Protocol

    Revision = %q$Revision$.split[1]

    def SMTP.default_port
      25
    end

    def initialize( address, port = nil )
      @address = address
      @port = port || SMTP.default_port

      @esmtp = true

      @command = nil
      @socket = nil
      @started = false
      @open_timeout = 30
      @read_timeout = 60

      @debug_output = nil
    end

    def inspect
      "#<#{self.class} #{address}:#{@port} open=#{@started}>"
    end

    def esmtp?
      @esmtp
    end

    def esmtp=( bool )
      @esmtp = bool
    end

    alias esmtp esmtp?

    attr_reader :address
    attr_reader :port

    attr_accessor :open_timeout
    attr_reader :read_timeout

    def read_timeout=( sec )
      @socket.read_timeout = sec if @socket
      @read_timeout = sec
    end

    def set_debug_output( arg )
      @debug_output = arg
    end

    #
    # SMTP session control
    #

    def SMTP.start( address, port = nil,
                    helo = 'localhost.localdomain',
                    user = nil, secret = nil, authtype = nil,
                    &block)
      new(address, port).start(helo, user, secret, authtype, &block)
    end

    def started?
      @started
    end

    def start( helo = 'localhost.localdomain',
               user = nil, secret = nil, authtype = nil )
      raise IOError, 'SMTP session already started' if @started
      if block_given?
        begin
          do_start(helo, user, secret, authtype)
          return yield(self)
        ensure
          finish if @started
        end
      else
        do_start(helo, user, secret, authtype)
        return self
      end
    end

    def do_start( helo, user, secret, authtype )
      @socket = InternetMessageIO.open(@address, @port,
                                       @open_timeout, @read_timeout,
                                       @debug_output)
      @command = SMTPCommand.new(@socket)
      begin
        if @esmtp
          @command.ehlo helo
        else
          @command.helo helo
        end
      rescue ProtocolError
        if @esmtp
          @esmtp = false
          @command = SMTPCommand.new(@socket)
          retry
        end
        raise
      end

      if user or secret
        raise ArgumentError, 'both of account and password are required'\
                        unless user and secret
        mid = 'auth_' + (authtype || 'cram_md5').to_s
        raise ArgumentError, "wrong auth type #{authtype}"\
                        unless command().respond_to?(mid)
        @command.__send__ mid, user, secret
      end
    end
    private :do_start

    def finish
      raise IOError, 'closing already closed SMTP session' unless @started
      @command.quit if @command
      @command = nil
      @socket.close if @socket and not @socket.closed?
      @socket = nil
      @started = false
    end

    #
    # SMTP wrapper
    #

    def send_mail( mailsrc, from_addr, *to_addrs )
      do_ready from_addr, to_addrs.flatten
      command().write_mail mailsrc
    end

    alias sendmail send_mail   # backward compatibility

    def ready( from_addr, *to_addrs, &block )
      do_ready from_addr, to_addrs.flatten
      command().through_mail(&block)
    end

    private

    def do_ready( from_addr, to_addrs )
      raise ArgumentError, 'mail destination does not given' if to_addrs.empty?
      command().mailfrom from_addr
      command().rcpt to_addrs
    end

    def command
      raise IOError, "closed session" unless @command
      @command
    end

  end

  SMTPSession = SMTP


  class SMTPCommand

    def initialize( sock )
      @socket = sock
      @in_critical_block = false
      check_response(critical { recv_response() })
    end

    def inspect
      "#<#{self.class} socket=#{@socket.inspect}>"
    end

    def helo( domain )
      getok('HELO %s', domain)
    end

    def ehlo( domain )
      getok('EHLO %s', domain)
    end

    # "PLAIN" authentication [RFC2554]
    def auth_plain( user, secret )
      res = critical { get_response('AUTH PLAIN %s',
                                    ["\0#{user}\0#{secret}"].pack('m').chomp) }
      raise SMTPAuthenticationError, res unless /\A2../ === res
    end

    # "CRAM-MD5" authentication [RFC2195]
    def auth_cram_md5( user, secret )
      res = nil
      critical {
          res = check_response(get_response('AUTH CRAM-MD5'), true)
          challenge = res.split(/ /)[1].unpack('m')[0]
          secret = Digest::MD5.digest(secret) if secret.size > 64

          isecret = secret + "\0" * (64 - secret.size)
          osecret = isecret.dup
          0.upto(63) do |i|
            isecret[i] ^= 0x36
            osecret[i] ^= 0x5c
          end
          tmp = Digest::MD5.digest(isecret + challenge)
          tmp = Digest::MD5.hexdigest(osecret + tmp)

          res = get_response([user + ' ' + tmp].pack('m').gsub(/\s+/, ''))
      }
      raise SMTPAuthenticationError, res unless /\A2../ === res
    end

    def mailfrom( fromaddr )
      getok('MAIL FROM:<%s>', fromaddr)
    end

    def rcpt( toaddrs )
      toaddrs.each do |i|
        getok('RCPT TO:<%s>', i)
      end
    end

    def write_mail( src )
      res = critical {
          check_response(get_response('DATA'), true)
          @socket.write_message src
          recv_response()
      }
      check_response(res)
    end

    def through_mail( &block )
      res = critical {
          check_response(get_response('DATA'), true)
          @socket.through_message(&block)
          recv_response()
      }
      check_response(res)
    end

    def quit
      getok('QUIT')
    end

    private

    def getok( fmt, *args )
      @socket.writeline sprintf(fmt, *args)
      check_response(critical { recv_response() })
    end

    def get_response( fmt, *args )
      @socket.writeline sprintf(fmt, *args)
      recv_response()
    end

    def recv_response
      res = ''
      while true
        line = @socket.readline
        res << line << "\n"
        break unless line[3] == ?-   # "210-PIPELINING"
      end
      res
    end

    def check_response( res, cont = false )
      etype = case res[0]
              when ?2 then nil
              when ?3 then cont ? nil : ProtoUnknownError
              when ?4 then ProtoServerError
              when ?5 then
                case res[1]
                when ?0 then ProtoSyntaxError
                when ?3 then ProtoAuthError
                when ?5 then ProtoFatalError
                end
              end
      raise etype, res if etype
      res
    end

    def critical
      return if @in_critical_block
      @in_critical_block = true
      result = yield()
      @in_critical_block = false
      result
    end

  end

end   # module Net

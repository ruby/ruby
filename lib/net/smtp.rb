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

=== Sending Message

You must open connection to SMTP server before sending messages.
First argument is the address of SMTP server, and second argument
is port number. Using SMTP.start with block is the most simple way
to do it. SMTP connection is closed automatically after block is
executed.

    require 'net/smtp'
    Net::SMTP.start('your.smtp.server', 25) {|smtp|
      # use a SMTP object only in this block
    }

Replace 'your.smtp.server' by your SMTP server. Normally
your system manager or internet provider is supplying a server
for you.

Then you can send messages.

    msgstr = <<END_OF_MESSAGE
    From: Your Name <your@mail.address>
    To: Destination Address <someone@example.com>
    Subject: test message
    Date: Sat, 23 Jun 2001 16:26:43 +0900
    Message-Id: <unique.message.id.string@example.com>

    This is a test message.
    END_OF_MESSAGE

    require 'net/smtp'
    Net::SMTP.start('your.smtp.server', 25) {|smtp|
      smtp.send_message msgstr,
                        'your@mail.address',
                        'his_addess@example.com'
    }

=== Closing Session

You MUST close SMTP session after sending messages, by calling #finish
method:

    # using SMTP#finish
    smtp = Net::SMTP.start('your.smtp.server', 25)
    smtp.send_message msgstr, 'from@address', 'to@address'
    smtp.finish

You can also use block form of SMTP.start/SMTP#start.  They closes
SMTP session automatically:

    # using block form of SMTP.start
    Net::SMTP.start('your.smtp.server', 25) {|smtp|
      smtp.send_message msgstr, 'from@address', 'to@address'
    }

I strongly recommend this scheme.  This form is more simple and robust.

=== HELO domain

In almost all situation, you must designate the third argument
of SMTP.start/SMTP#start. It is the domain name which you are on
(the host to send mail from). It is called "HELO domain".
SMTP server will judge if he/she should send or reject
the SMTP session by inspecting HELO domain.

    Net::SMTP.start('your.smtp.server', 25,
                    'mail.from.domain') {|smtp|

=== SMTP Authentication

The Net::SMTP class supports three authentication schemes;
PLAIN, LOGIN and CRAM MD5.  (SMTP Authentication: [RFC2554])
To use SMTP authentication, pass extra arguments to
SMTP.start/SMTP#start methods.

    # PLAIN
    Net::SMTP.start('your.smtp.server', 25, 'mail.from,domain',
                    'Your Account', 'Your Password', :plain)
    # LOGIN
    Net::SMTP.start('your.smtp.server', 25, 'mail.from,domain',
                    'Your Account', 'Your Password', :login)

    # CRAM MD5
    Net::SMTP.start('your.smtp.server', 25, 'mail.from,domain',
                    'Your Account', 'Your Password', :cram_md5)

== class Net::SMTP

=== Class Methods

: new( address, port = 25 )
    creates a new Net::SMTP object.
    This method does not open TCP connection.

: start( address, port = 25, helo_domain = 'localhost.localdomain', account = nil, password = nil, authtype = nil )
: start( address, port = 25, helo_domain = 'localhost.localdomain', account = nil, password = nil, authtype = nil ) {|smtp| .... }
    is equal to:
        Net::SMTP.new(address,port).start(helo_domain,account,password,authtype)

        # example
        Net::SMTP.start('your.smtp.server') {
          smtp.send_message msgstr, 'from@example.com', ['dest@example.com']
        }

    This method may raise:

      * Net::SMTPAuthenticationError
      * Net::SMTPServerBusy
      * Net::SMTPSyntaxError
      * Net::SMTPFatalError
      * Net::SMTPUnknownError
      * IOError
      * TimeoutError

=== Instance Methods

: start( helo_domain = <local host name>, account = nil, password = nil, authtype = nil )
: start( helo_domain = <local host name>, account = nil, password = nil, authtype = nil ) {|smtp| .... }
    opens TCP connection and starts SMTP session.
    HELO_DOMAIN is a domain that you'll dispatch mails from.
    If protocol had been started, raises IOError.

    When this methods is called with block, give a SMTP object to block and
    close session after block call finished.

    If both of account and password are given, is trying to get
    authentication by using AUTH command. AUTHTYPE is an either of
    :login, :plain, and :cram_md5.

    This method may raise:

      * Net::SMTPAuthenticationError
      * Net::SMTPServerBusy
      * Net::SMTPSyntaxError
      * Net::SMTPFatalError
      * Net::SMTPUnknownError
      * IOError
      * TimeoutError

: started?
: active?    OBSOLETE
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
    seconds to wait until reading one block (by one read(2) call).
    If SMTP object cannot open a conection in this seconds,
    it raises TimeoutError exception.

: finish
    finishes SMTP session.
    If SMTP session had not started, raises an IOError.
    If SMTP session timed out, raises TimeoutError.

: send_message( msgstr, from_addr, *dest_addrs )
: send_mail( msgstr, from_addr, *dest_addrs )
: sendmail( msgstr, from_addr, *dest_addrs )   OBSOLETE
    sends a String MSGSTR.  If a single CR ("\r") or LF ("\n") found
    in the MEGSTR, converts it to the CR LF pair.  You cannot send a
    binary message with this class.

    FROM_ADDR must be a String, representing source mail address.
    TO_ADDRS must be Strings or an Array of Strings, representing
    destination mail addresses.

        # example
        Net::SMTP.start('smtp.example.com') {|smtp|
          smtp.send_message msgstr,
                            'from@example.com',
                            ['dest@example.com', 'dest2@example.com']
        }

    This method may raise:

      * Net::SMTPServerBusy
      * Net::SMTPSyntaxError
      * Net::SMTPFatalError
      * Net::SMTPUnknownError
      * IOError
      * TimeoutError

: open_message_stream( from_addr, *dest_addrs ) {|stream| .... }
: ready( from_addr, *dest_addrs ) {|stream| .... }    OBSOLETE
    opens a message writer stream and gives it to the block.
    STREAM is valid only in the block, and has these methods:

      : puts(str = '')
          outputs STR and CR LF.
      : print(str)
          outputs STR.
      : printf(fmt, *args)
          outputs sprintf(fmt,*args).
      : write(str)
          outputs STR and returns the length of written bytes.
      : <<(str)
          outputs STR and returns self.

    If a single CR ("\r") or LF ("\n") found in the message,
    converts it to the CR LF pair.  You cannot send a binary
    message with this class.

    FROM_ADDR must be a String, representing source mail address.
    TO_ADDRS must be Strings or an Array of Strings, representing
    destination mail addresses.

        # example
        Net::SMTP.start('smtp.example.com', 25) {|smtp|
          smtp.open_message_stream('from@example.com', ['dest@example.com']) {|f|
            f.puts 'From: from@example.com'
            f.puts 'To: dest@example.com'
            f.puts 'Subject: test message'
            f.puts
            f.puts 'This is a test message.'
          }
        }

    This method may raise:

      * Net::SMTPServerBusy
      * Net::SMTPSyntaxError
      * Net::SMTPFatalError
      * Net::SMTPUnknownError
      * IOError
      * TimeoutError

: set_debug_output( output )
    WARNING: This method causes serious security holes.
    Use this method for only debugging.

    set an output stream for debug logging.
    You must call this before #start.

      # example
      smtp = Net::SMTP.new(addr, port)
      smtp.set_debug_output $stderr
      smtp.start {
        ....
      }


== SMTP Related Exception Classes

: Net::SMTPAuthenticationError
    SMTP authentication error.

    ancestors: SMTPError, ProtoAuthError (obsolete), ProtocolError (obsolete)

: Net::SMTPServerBusy
    Temporal error; error number 420/450.

    ancestors: SMTPError, ProtoServerError (obsolete), ProtocolError (obsolete)

: Net::SMTPSyntaxError
    SMTP command syntax error (error number 500)

    ancestors: SMTPError, ProtoSyntaxError (obsolete), ProtocolError (obsolete)

: Net::SMTPFatalError
    Fatal error (error number 5xx, except 500)

    ancestors: SMTPError, ProtoFatalError (obsolete), ProtocolError (obsolete)

: Net::SMTPUnknownError
    Unexpected reply code returned from server
    (might be a bug of this library).

    ancestors: SMTPError, ProtoUnkownError (obsolete), ProtocolError (obsolete)

=end

require 'net/protocol'
require 'digest/md5'


module Net

  module SMTPError
    # This *class* is module for some reason.
    # In ruby 1.9.x, this module becomes a class.
  end
  class SMTPAuthenticationError < ProtoAuthError
    include SMTPError
  end
  class SMTPServerBusy < ProtoServerError
    include SMTPError
  end
  class SMTPSyntaxError < ProtoSyntaxError
    include SMTPError
  end
  class SMTPFatalError < ProtoFatalError
    include SMTPError
  end
  class SMTPUnknownError < ProtoUnknownError
    include SMTPError
  end


  class SMTP

    Revision = %q$Revision$.split[1]

    def SMTP.default_port
      25
    end

    def initialize( address, port = nil )
      @address = address
      @port = (port || SMTP.default_port)
      @esmtp = true
      @socket = nil
      @started = false
      @open_timeout = 30
      @read_timeout = 60
      @error_occured = false
      @debug_output = nil
    end

    def inspect
      "#<#{self.class} #{@address}:#{@port} started=#{@started}>"
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

    def do_start( helodomain, user, secret, authtype )
      raise IOError, 'SMTP session already started' if @started
      check_auth_args user, secret, authtype if user or secret

      @socket = InternetMessageIO.open(@address, @port,
                                       @open_timeout, @read_timeout,
                                       @debug_output)
      check_response(critical { recv_response() })
      begin
        if @esmtp
          ehlo helodomain
        else
          helo helodomain
        end
      rescue ProtocolError
        if @esmtp
          @esmtp = false
          @error_occured = false
          retry
        end
        raise
      end
      authenticate user, secret, authtype if user
    end
    private :do_start

    def finish
      raise IOError, 'closing already closed SMTP session' unless @started
      quit if @socket and not @socket.closed? and not @error_occured
      @socket.close if @socket and not @socket.closed?
      @socket = nil
      @error_occured = false
      @started = false
    end

    #
    # message send
    #

    public

    def send_message( msgstr, from_addr, *to_addrs )
      send0(from_addr, to_addrs.flatten) {
        @socket.write_message msgstr
      }
    end

    alias send_mail send_message
    alias sendmail send_message   # obsolete

    def open_message_stream( from_addr, *to_addrs, &block )
      send0(from_addr, to_addrs.flatten) {
        @socket.write_message_by_block(&block)
      }
    end

    alias ready open_message_stream   # obsolete

    private

    def send0( from_addr, to_addrs )
      raise IOError, 'closed session' unless @socket
      raise ArgumentError, 'mail destination does not given' if to_addrs.empty?
      if $SAFE > 0
        raise SecurityError, 'tainted from_addr' if from_addr.tainted?
        to_addrs.each do |to| 
          raise SecurityError, 'tainted to_addr' if to.tainted?
        end
      end

      mailfrom from_addr
      to_addrs.each do |to|
        rcptto to
      end
      res = critical {
        check_response(get_response('DATA'), true)
        yield
        recv_response()
      }
      check_response(res)
    end

    #
    # auth
    #

    private

    def check_auth_args( user, secret, authtype )
      raise ArgumentError, 'both of user and secret are required'\
                      unless user and secret
      auth_method = "auth_#{authtype || 'cram_md5'}"
      raise ArgumentError, "wrong auth type #{authtype}"\
                      unless respond_to?(auth_method)
    end

    def authenticate( user, secret, authtype )
      __send__("auth_#{authtype || 'cram_md5'}", user, secret)
    end

    def auth_plain( user, secret )
      res = critical { get_response('AUTH PLAIN %s',
                                    base64_encode("\0#{user}\0#{secret}")) }
      raise SMTPAuthenticationError, res unless /\A2../ === res
    end

    def auth_login( user, secret )
      res = critical {
        check_response(get_response('AUTH LOGIN'), true)
        check_response(get_response(base64_encode(user)), true)
        get_response(base64_encode(secret))
      }
      raise SMTPAuthenticationError, res unless /\A2../ === res
    end

    def auth_cram_md5( user, secret )
      # CRAM-MD5: [RFC2195]
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

        res = get_response(base64_encode(user + ' ' + tmp))
      }
      raise SMTPAuthenticationError, res unless /\A2../ === res
    end

    def base64_encode( str )
      # expects "str" may not become too long
      [str].pack('m').gsub(/\s+/, '')
    end

    #
    # SMTP command dispatcher
    #

    private

    def helo( domain )
      getok('HELO %s', domain)
    end

    def ehlo( domain )
      getok('EHLO %s', domain)
    end

    def mailfrom( fromaddr )
      getok('MAIL FROM:<%s>', fromaddr)
    end

    def rcptto( to )
      getok('RCPT TO:<%s>', to)
    end

    def quit
      getok('QUIT')
    end

    #
    # row level library
    #

    private

    def getok( fmt, *args )
      res = critical {
        @socket.writeline sprintf(fmt, *args)
        recv_response()
      }
      return check_response(res)
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

    def check_response( res, allow_continue = false )
      return res if /\A2/ === res
      return res if allow_continue and /\A354/ === res
      err = case res
            when /\A4/  then SMTPServerBusy
            when /\A50/ then SMTPSyntaxError
            when /\A55/ then SMTPFatalError
            else SMTPUnknownError
            end
      raise err, res
    end

    def critical( &block )
      return '200 dummy reply code' if @error_occured
      begin
        return yield()
      rescue Exception
        @error_occured = true
        raise
      end
    end

  end   # class SMTP

  SMTPSession = SMTP

end   # module Net

=begin

= net/smtp.rb version 1.1.36

Copyright (c) 1999-2001 Yukihiro Matsumoto

written & maintained by Minero Aoki <aamine@loveruby.net>

This program is free software. You can re-distribute and/or
modify this program under the same terms as Ruby itself,
Ruby Distribute License or GNU General Public License.

NOTE: You can get Japanese version of this document from
Ruby Documentation Project (RDP):
((<URL:http://www.ruby-lang.org/~rubikitch/RDP.cgi>))

== What is This Module?

This module provides your program the functions to send internet
mail via SMTP, Simple Mail Transfer Protocol. For details of
SMTP itself, refer [RFC2821] ((<URL:http://www.ietf.org/rfc/rfc2821.txt>)).

== What This Module is NOT?

This module does NOT provide the functions to compose internet
mail. You must create it by yourself. For details of internet mail
format, see [RFC2822] ((<URL:http://www.ietf.org/rfc/rfc2822.txt>)).

== Examples

=== Sending Mail

You must open connection to SMTP server before sending mails.
First argument is the address of SMTP server, and second argument
is port number. Using SMTP.start with block is the most simple way
to do it. SMTP Connection is closed automatically after block is
executed.

    require 'net/smtp'
    Net::SMTP.start( 'your.smtp.server', 25 ) {|smtp|
      # use smtp object only in this block
    }

Replace 'your.smtp.server' by your SMTP server. Normally
your system manager or internet provider is supplying a server
for you.

Then you can send mail.

    require 'net/smtp'

    Net::SMTP.start( 'your.smtp.server', 25 ) {|smtp|
      smtp.send_mail <<EndOfMail, 'your@mail.address', 'to@some.domain'
    From: Your Name <your@mail.address>
    To: Dest Address <to@some.domain>
    Subject: test mail
    Date: Sat, 23 Jun 2001 16:26:43 +0900
    Message-Id: <unique.message.id.string@some.domain>

    This is test mail.
    EndOfMail
    }

=== Sending Mails from Any Sources

In an example above I sent mail from String (here document literal).
SMTP#send_mail accepts any objects which has "each" method
like File and Array.

    require 'net/smtp'
    Net::SMTP.start( 'your.smtp.server', 25 ) {|smtp|
      File.open( 'Mail/draft/1' ) {|f|
        smtp.send_mail f, 'your@mail.address', 'to@some.domain'
      }
    }

=== Giving "Hello" Domain

If your machine does not have canonical host name, maybe you
must designate the third argument of SMTP.start.

    Net::SMTP.start( 'your.smtp.server', 25,
                     'mail.from.domain' ) {|smtp|

This argument gives MAILFROM domain, the domain name that
you send mail from. SMTP server might judge if he (or she?)
send or reject SMTP session by this data.

== class Net::SMTP

=== Class Methods

: new( address = 'localhost', port = 25 )
    creates a new Net::SMTP object.

: start( address = 'localhost', port = 25, helo_domain = Socket.gethostname, account = nil, password = nil, authtype = nil )
: start( address = 'localhost', port = 25, helo_domain = Socket.gethostname, account = nil, password = nil, authtype = nil ) {|smtp| .... }
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

: active?
    true if SMTP session is started.

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
    give adapter object to the block. ADAPTER accepts only "write"
    method.

    FROM_ADDR must be a String, representing source mail address.
    TO_ADDRS must be Strings or an Array of Strings, representing
    destination mail addresses.

        # example
        Net::SMTP.start( 'your.smtp.server', 25 ) {|smtp|
          smtp.ready( 'from@mail.addr', 'dest@mail.addr' ) do |adapter|
            adapter.write str1
            adapter.write str2
            adapter.write str3
          end
        }

== Exceptions

SMTP objects raise these exceptions:
: Net::ProtoSyntaxError
    syntax error (errno.500)
: Net::ProtoFatalError
    fatal error (errno.550)
: Net::ProtoUnknownError
    unknown error. (is probably bug)
: Net::ProtoServerBusy
    temporary error (errno.420/450)

=end

require 'net/protocol'
require 'md5'


module Net


  class SMTP < Protocol

    protocol_param :port,         '25'
    protocol_param :command_type, '::Net::NetPrivate::SMTPCommand'


    def initialize( addr = nil, port = nil )
      super
      @esmtp = true
    end

    attr :esmtp

    def send_mail( mailsrc, from_addr, *to_addrs )
      do_ready from_addr, to_addrs.flatten
      @command.write_mail mailsrc, nil
    end

    alias sendmail send_mail

    def ready( from_addr, *to_addrs, &block )
      do_ready from_addr, to_addrs.flatten
      @command.write_mail nil, block
    end


    private


    def do_ready( from_addr, to_addrs )
      if to_addrs.empty? then
        raise ArgumentError, 'mail destination does not given'
      end
      @command.mailfrom from_addr
      @command.rcpt to_addrs
      @command.data
    end

    def do_start( helodom = nil,
                  user = nil, secret = nil, authtype = nil )
      helodom ||= ::Socket.gethostname
      unless helodom then
        raise ArgumentError,
          "cannot get localhost name; try 'smtp.start(local_host_name)'"
      end

      begin
        if @esmtp then
          @command.ehlo helodom
        else
          @command.helo helodom
        end
      rescue ProtocolError
        if @esmtp then
          @esmtp = false
          @command.error_ok
          retry
        else
          raise
        end
      end

      if user or secret then
        (user and secret) or
            raise ArgumentError, 'both of account and password are required'

        mid = 'auth_' + (authtype || 'cram_md5').to_s
        @command.respond_to? mid or
            raise ArgumentError, "wrong auth type #{authtype.to_s}"

        @command.__send__ mid, user, secret
      end
    end

  end

  SMTPSession = SMTP



  module NetPrivate


  class SMTPCommand < Command

    def initialize( sock )
      super
      critical {
        check_reply SuccessCode
      }
    end


    def helo( fromdom )
      critical {
        getok sprintf( 'HELO %s', fromdom )
      }
    end


    def ehlo( fromdom )
      critical {
        getok sprintf( 'EHLO %s', fromdom )
      }
    end


    # "PLAIN" authentication [RFC2554]
    def auth_plain( user, secret )
      critical {
        getok sprintf( 'AUTH PLAIN %s',
                       ["\0#{user}\0#{secret}"].pack('m').chomp )
      }
    end

    # "CRAM-MD5" authentication [RFC2195]
    def auth_cram_md5( user, secret )
      critical {
        rep = getok( 'AUTH CRAM-MD5', ContinueCode )
        challenge = rep.msg.split(' ')[1].unpack('m')[0]
        secret = MD5.new( secret ).digest if secret.size > 64

        isecret = secret + "\0" * (64 - secret.size)
        osecret = isecret.dup
        0.upto( 63 ) do |i|
          isecret[i] ^= 0x36
          osecret[i] ^= 0x5c
        end
        tmp = MD5.new( isecret + challenge ).digest
        tmp = MD5.new( osecret + tmp ).hexdigest

        getok [user + ' ' + tmp].pack('m').chomp
      }
    end


    def mailfrom( fromaddr )
      critical {
        getok sprintf( 'MAIL FROM:<%s>', fromaddr )
      }
    end


    def rcpt( toaddrs )
      toaddrs.each do |i|
        critical {
          getok sprintf( 'RCPT TO:<%s>', i )
        }
      end
    end


    def data
      return unless begin_critical
      getok 'DATA', ContinueCode
    end

    def write_mail( mailsrc, block )
      @socket.write_pendstr mailsrc, block
      check_reply SuccessCode
      end_critical
    end


    def quit
      critical {
        getok 'QUIT'
      }
    end


    private


    def get_reply
      arr = read_reply
      stat = arr[0][0,3]

      klass = case stat[0]
              when ?2 then SuccessCode
              when ?3 then ContinueCode
              when ?4 then ServerErrorCode
              when ?5 then
                case stat[1]
                when ?0 then SyntaxErrorCode
                when ?3 then AuthErrorCode
                when ?5 then FatalErrorCode
                end
              end
      klass ||= UnknownCode

      Response.new( klass, stat, arr.join('') )
    end


    def read_reply
      arr = []
      while true do
        str = @socket.readline
        break unless str[3] == ?-   # ex: "210-..."
        arr.push str
      end
      arr.push str

      arr
    end

  end


  end   # module Net::NetPrivate

end   # module Net

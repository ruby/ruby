=begin

= net/smtp.rb version 1.1.33

written by Minero Aoki <aamine@dp.u-netsurf.ne.jp>

This program is free software.
You can distribute/modify this program under
the terms of the Ruby Distribute License.

Japanese version of this document is in "net" full package.
You can get it from RAA
(Ruby Application Archive: http://www.ruby-lang.org/en/raa.html).


== Net::SMTP

=== Super Class

Net::Protocol

=== Class Methods

: new( address = 'localhost', port = 25 )
  creates a new Net::SMTP object.

: start( address = 'localhost', port = 25, *protoargs )
: start( address = 'localhost', port = 25, *protoargs ) {|smtp| .... }
  is equal to Net::SMTP.new( address, port ).start( *protoargs )

=== Methods

: start( helo_domain = Socket.gethostname, \
         account = nil, password = nil, authtype = nil )
: start( helo_domain = Socket.gethostname, \
         account = nil, password = nil, authtype = nil ) {|smtp| .... }
  opens TCP connection and starts SMTP session.
  If protocol had been started, do nothing and return false.

  When this methods is called with block, give a SMTP object to block and
  close session after block call finished.

  If account and password are given, is trying to get authentication
  by using AUTH command. "authtype" is :plain (symbol) or :cram_md5.

: send_mail( mailsrc, from_addr, *to_addrs )
: sendmail( mailsrc, from_addr, *to_addrs )
  This method sends 'mailsrc' as mail. SMTP read strings
  from 'mailsrc' by calling 'each' iterator, and convert them
  into "\r\n" terminated string when write.

  from_addr must be String.
  to_addrs must be a String(s) or an Array of String.

  Exceptions which SMTP raises are:
  * Net::ProtoSyntaxError: syntax error (errno.500)
  * Net::ProtoFatalError: fatal error (errno.550)
  * Net::ProtoUnknownError: unknown error
  * Net::ProtoServerBusy: temporary error (errno.420/450)

    # usage example

    Net::SMTP.start( 'localhost', 25 ) do |smtp|
      smtp.send_mail mail_string, 'from-addr@foo.or.jp', 'to-addr@bar.or.jp'
    end

: ready( from_addr, to_addrs ) {|adapter| .... }
  This method stands by the SMTP object for sending mail.
  "adapter" object accepts only "write" method.

    # usage example

    Net::SMTP.start( 'localhost', 25 ) do |smtp|
      smtp.ready( from, to ) do |adapter|
        adapter.write str1
        adapter.write str2
        adapter.write str3
      end
    end

: finish
  finishes SMTP session.
  If SMTP session had not started, do nothing and return false.

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

      if user and secret then
        mid = 'auth_' + (authtype || 'cram_md5').to_s
        unless @command.respond_to? mid then
          raise ArgumentError, "wrong auth type #{authtype.to_s}"
        end
        @command.send mid, user, secret
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

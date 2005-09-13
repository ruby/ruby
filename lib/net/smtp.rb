# = net/smtp.rb
# 
# Copyright (c) 1999-2003 Yukihiro Matsumoto.
#
# Copyright (c) 1999-2003 Minero Aoki.
# 
# Written & maintained by Minero Aoki <aamine@loveruby.net>.
#
# Documented by William Webber and Minero Aoki.
# 
# This program is free software. You can re-distribute and/or
# modify this program under the same terms as Ruby itself,
# Ruby Distribute License or GNU General Public License.
# 
# NOTE: You can find Japanese version of this document in
# the doc/net directory of the standard ruby interpreter package.
# 
# $Id$
#
# See Net::SMTP for documentation. 
# 

require 'net/protocol'
require 'digest/md5'

module Net

  # Module mixed in to all SMTP error classes
  module SMTPError
    # This *class* is module for some reason.
    # In ruby 1.9.x, this module becomes a class.
  end

  # Represents an SMTP authentication error.
  class SMTPAuthenticationError < ProtoAuthError
    include SMTPError
  end

  # Represents SMTP error code 420 or 450, a temporary error.
  class SMTPServerBusy < ProtoServerError
    include SMTPError
  end

  # Represents an SMTP command syntax error (error code 500)
  class SMTPSyntaxError < ProtoSyntaxError
    include SMTPError
  end

  # Represents a fatal SMTP error (error code 5xx, except for 500)
  class SMTPFatalError < ProtoFatalError
    include SMTPError
  end

  # Unexpected reply code returned from server.
  class SMTPUnknownError < ProtoUnknownError
    include SMTPError
  end

  #
  # = Net::SMTP
  #
  # == What is This Library?
  # 
  # This library provides functionality to send internet
  # mail via SMTP, the Simple Mail Transfer Protocol. For details of
  # SMTP itself, see [RFC2821] (http://www.ietf.org/rfc/rfc2821.txt).
  # 
  # == What is This Library NOT?
  # 
  # This library does NOT provide functions to compose internet mails.
  # You must create them by yourself. If you want better mail support,
  # try RubyMail or TMail. You can get both libraries from RAA.
  # (http://www.ruby-lang.org/en/raa.html)
  # 
  # FYI: the official documentation on internet mail is: [RFC2822] (http://www.ietf.org/rfc/rfc2822.txt).
  # 
  # == Examples
  # 
  # === Sending Messages
  # 
  # You must open a connection to an SMTP server before sending messages.
  # The first argument is the address of your SMTP server, and the second 
  # argument is the port number. Using SMTP.start with a block is the simplest 
  # way to do this. This way, the SMTP connection is closed automatically 
  # after the block is executed.
  # 
  #     require 'net/smtp'
  #     Net::SMTP.start('your.smtp.server', 25) do |smtp|
  #       # Use the SMTP object smtp only in this block.
  #     end
  # 
  # Replace 'your.smtp.server' with your SMTP server. Normally
  # your system manager or internet provider supplies a server
  # for you.
  # 
  # Then you can send messages.
  # 
  #     msgstr = <<END_OF_MESSAGE
  #     From: Your Name <your@mail.address>
  #     To: Destination Address <someone@example.com>
  #     Subject: test message
  #     Date: Sat, 23 Jun 2001 16:26:43 +0900
  #     Message-Id: <unique.message.id.string@example.com>
  # 
  #     This is a test message.
  #     END_OF_MESSAGE
  # 
  #     require 'net/smtp'
  #     Net::SMTP.start('your.smtp.server', 25) do |smtp|
  #       smtp.send_message msgstr,
  #                         'your@mail.address',
  #                         'his_addess@example.com'
  #     end
  # 
  # === Closing the Session
  # 
  # You MUST close the SMTP session after sending messages, by calling 
  # the #finish method:
  # 
  #     # using SMTP#finish
  #     smtp = Net::SMTP.start('your.smtp.server', 25)
  #     smtp.send_message msgstr, 'from@address', 'to@address'
  #     smtp.finish
  # 
  # You can also use the block form of SMTP.start/SMTP#start.  This closes
  # the SMTP session automatically:
  # 
  #     # using block form of SMTP.start
  #     Net::SMTP.start('your.smtp.server', 25) do |smtp|
  #       smtp.send_message msgstr, 'from@address', 'to@address'
  #     end
  # 
  # I strongly recommend this scheme.  This form is simpler and more robust.
  # 
  # === HELO domain
  # 
  # In almost all situations, you must provide a third argument
  # to SMTP.start/SMTP#start. This is the domain name which you are on
  # (the host to send mail from). It is called the "HELO domain".
  # The SMTP server will judge whether it should send or reject
  # the SMTP session by inspecting the HELO domain.
  # 
  #     Net::SMTP.start('your.smtp.server', 25,
  #                     'mail.from.domain') { |smtp| ... }
  # 
  # === SMTP Authentication
  # 
  # The Net::SMTP class supports three authentication schemes;
  # PLAIN, LOGIN and CRAM MD5.  (SMTP Authentication: [RFC2554])
  # To use SMTP authentication, pass extra arguments to 
  # SMTP.start/SMTP#start.
  # 
  #     # PLAIN
  #     Net::SMTP.start('your.smtp.server', 25, 'mail.from.domain',
  #                     'Your Account', 'Your Password', :plain)
  #     # LOGIN
  #     Net::SMTP.start('your.smtp.server', 25, 'mail.from.domain',
  #                     'Your Account', 'Your Password', :login)
  # 
  #     # CRAM MD5
  #     Net::SMTP.start('your.smtp.server', 25, 'mail.from.domain',
  #                     'Your Account', 'Your Password', :cram_md5)
  #
  class SMTP

    Revision = %q$Revision$.split[1]

    # The default SMTP port, port 25.
    def SMTP.default_port
      25
    end

    #
    # Creates a new Net::SMTP object.
    #
    # +address+ is the hostname or ip address of your SMTP
    # server.  +port+ is the port to connect to; it defaults to
    # port 25.
    #
    # This method does not open the TCP connection.  You can use
    # SMTP.start instead of SMTP.new if you want to do everything
    # at once.  Otherwise, follow SMTP.new with SMTP#start.
    #
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

    # Provide human-readable stringification of class state.
    def inspect
      "#<#{self.class} #{@address}:#{@port} started=#{@started}>"
    end

    # +true+ if the SMTP object uses ESMTP (which it does by default).
    def esmtp?
      @esmtp
    end

    #
    # Set whether to use ESMTP or not.  This should be done before 
    # calling #start.  Note that if #start is called in ESMTP mode,
    # and the connection fails due to a ProtocolError, the SMTP
    # object will automatically switch to plain SMTP mode and
    # retry (but not vice versa).
    #
    def esmtp=( bool )
      @esmtp = bool
    end

    alias esmtp esmtp?

    # The address of the SMTP server to connect to.
    attr_reader :address

    # The port number of the SMTP server to connect to.
    attr_reader :port

    # Seconds to wait while attempting to open a connection.
    # If the connection cannot be opened within this time, a
    # TimeoutError is raised.
    attr_accessor :open_timeout

    # Seconds to wait while reading one block (by one read(2) call).
    # If the read(2) call does not complete within this time, a
    # TimeoutError is raised.
    attr_reader :read_timeout

    # Set the number of seconds to wait until timing-out a read(2)
    # call.
    def read_timeout=( sec )
      @socket.read_timeout = sec if @socket
      @read_timeout = sec
    end

    #
    # WARNING: This method causes serious security holes.
    # Use this method for only debugging.
    #
    # Set an output stream for debug logging.
    # You must call this before #start.
    #
    #   # example
    #   smtp = Net::SMTP.new(addr, port)
    #   smtp.set_debug_output $stderr
    #   smtp.start do |smtp|
    #     ....
    #   end
    #
    def set_debug_output( arg )
      @debug_output = arg
    end

    #
    # SMTP session control
    #

    #
    # Creates a new Net::SMTP object and connects to the server.
    #
    # This method is equivalent to:
    # 
    #   Net::SMTP.new(address, port).start(helo_domain, account, password, authtype)
    #
    # === Example
    #
    #     Net::SMTP.start('your.smtp.server') do |smtp|
    #       smtp.send_message msgstr, 'from@example.com', ['dest@example.com']
    #     end
    #
    # === Block Usage
    #
    # If called with a block, the newly-opened Net::SMTP object is yielded
    # to the block, and automatically closed when the block finishes.  If called
    # without a block, the newly-opened Net::SMTP object is returned to
    # the caller, and it is the caller's responsibility to close it when
    # finished.
    #
    # === Parameters
    #
    # +address+ is the hostname or ip address of your smtp server.
    #
    # +port+ is the port to connect to; it defaults to port 25.
    #
    # +helo+ is the _HELO_ _domain_ provided by the client to the
    # server (see overview comments); it defaults to 'localhost.localdomain'. 
    #
    # The remaining arguments are used for SMTP authentication, if required
    # or desired.  +user+ is the account name; +secret+ is your password
    # or other authentication token; and +authtype+ is the authentication
    # type, one of :plain, :login, or :cram_md5.  See the discussion of
    # SMTP Authentication in the overview notes.
    #
    # === Errors
    #
    # This method may raise:
    #
    # * Net::SMTPAuthenticationError
    # * Net::SMTPServerBusy
    # * Net::SMTPSyntaxError
    # * Net::SMTPFatalError
    # * Net::SMTPUnknownError
    # * IOError
    # * TimeoutError
    #
    def SMTP.start( address, port = nil,
                    helo = 'localhost.localdomain',
                    user = nil, secret = nil, authtype = nil,
                    &block) # :yield: smtp
      new(address, port).start(helo, user, secret, authtype, &block)
    end

    # +true+ if the SMTP session has been started.
    def started?
      @started
    end

    #
    # Opens a TCP connection and starts the SMTP session.
    #
    # === Parameters
    #
    # +helo+ is the _HELO_ _domain_ that you'll dispatch mails from; see
    # the discussion in the overview notes.
    #
    # If both of +user+ and +secret+ are given, SMTP authentication 
    # will be attempted using the AUTH command.  +authtype+ specifies 
    # the type of authentication to attempt; it must be one of
    # :login, :plain, and :cram_md5.  See the notes on SMTP Authentication
    # in the overview. 
    #
    # === Block Usage
    #
    # When this methods is called with a block, the newly-started SMTP
    # object is yielded to the block, and automatically closed after
    # the block call finishes.  Otherwise, it is the caller's 
    # responsibility to close the session when finished.
    #
    # === Example
    #
    # This is very similar to the class method SMTP.start.
    #
    #     require 'net/smtp' 
    #     smtp = Net::SMTP.new('smtp.mail.server', 25)
    #     smtp.start(helo_domain, account, password, authtype) do |smtp|
    #       smtp.send_message msgstr, 'from@example.com', ['dest@example.com']
    #     end 
    #
    # The primary use of this method (as opposed to SMTP.start)
    # is probably to set debugging (#set_debug_output) or ESMTP
    # (#esmtp=), which must be done before the session is
    # started.  
    #
    # === Errors
    #
    # If session has already been started, an IOError will be raised.
    #
    # This method may raise:
    #
    # * Net::SMTPAuthenticationError
    # * Net::SMTPServerBusy
    # * Net::SMTPSyntaxError
    # * Net::SMTPFatalError
    # * Net::SMTPUnknownError
    # * IOError
    # * TimeoutError
    #
    def start( helo = 'localhost.localdomain',
               user = nil, secret = nil, authtype = nil ) # :yield: smtp
      if block_given?
        begin
          do_start(helo, user, secret, authtype)
          return yield(self)
        ensure
          do_finish
        end
      else
        do_start(helo, user, secret, authtype)
        return self
      end
    end

    def do_start( helodomain, user, secret, authtype )
      raise IOError, 'SMTP session already started' if @started
      check_auth_args user, secret, authtype if user or secret

      @socket = InternetMessageIO.old_open(@address, @port,
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
      @started = true
    ensure
      @socket.close if not @started and @socket and not @socket.closed?
    end
    private :do_start

    # Finishes the SMTP session and closes TCP connection.
    # Raises IOError if not started.
    def finish
      raise IOError, 'not yet started' unless started?
      do_finish
    end

    def do_finish
      quit if @socket and not @socket.closed? and not @error_occured
    ensure
      @started = false
      @error_occured = false
      @socket.close if @socket and not @socket.closed?
      @socket = nil
    end
    private :do_finish

    #
    # message send
    #

    public

    #
    # Sends +msgstr+ as a message.  Single CR ("\r") and LF ("\n") found
    # in the +msgstr+, are converted into the CR LF pair.  You cannot send a
    # binary message with this method. +msgstr+ should include both 
    # the message headers and body.
    #
    # +from_addr+ is a String representing the source mail address.
    #
    # +to_addr+ is a String or Strings or Array of Strings, representing
    # the destination mail address or addresses.
    #
    # === Example
    #
    #     Net::SMTP.start('smtp.example.com') do |smtp|
    #       smtp.send_message msgstr,
    #                         'from@example.com',
    #                         ['dest@example.com', 'dest2@example.com']
    #     end
    #
    # === Errors
    #
    # This method may raise:
    #
    # * Net::SMTPServerBusy
    # * Net::SMTPSyntaxError
    # * Net::SMTPFatalError
    # * Net::SMTPUnknownError
    # * IOError
    # * TimeoutError
    #
    def send_message( msgstr, from_addr, *to_addrs )
      send0(from_addr, to_addrs.flatten) {
        @socket.write_message msgstr
      }
    end

    alias send_mail send_message
    alias sendmail send_message   # obsolete

    #
    # Opens a message writer stream and gives it to the block.
    # The stream is valid only in the block, and has these methods:
    #
    # puts(str = '')::       outputs STR and CR LF.
    # print(str)::           outputs STR.
    # printf(fmt, *args)::   outputs sprintf(fmt,*args).
    # write(str)::           outputs STR and returns the length of written bytes.
    # <<(str)::              outputs STR and returns self.
    #
    # If a single CR ("\r") or LF ("\n") is found in the message,
    # it is converted to the CR LF pair.  You cannot send a binary
    # message with this method.
    #
    # === Parameters
    #
    # +from_addr+ is a String representing the source mail address.
    #
    # +to_addr+ is a String or Strings or Array of Strings, representing
    # the destination mail address or addresses.
    #
    # === Example
    #
    #     Net::SMTP.start('smtp.example.com', 25) do |smtp|
    #       smtp.open_message_stream('from@example.com', ['dest@example.com']) do |f|
    #         f.puts 'From: from@example.com'
    #         f.puts 'To: dest@example.com'
    #         f.puts 'Subject: test message'
    #         f.puts
    #         f.puts 'This is a test message.'
    #       end
    #     end
    #
    # === Errors
    #
    # This method may raise:
    #
    # * Net::SMTPServerBusy
    # * Net::SMTPSyntaxError
    # * Net::SMTPFatalError
    # * Net::SMTPUnknownError
    # * IOError
    # * TimeoutError
    #
    def open_message_stream( from_addr, *to_addrs, &block ) # :yield: stream
      send0(from_addr, to_addrs.flatten) {
        @socket.write_message_by_block(&block)
      }
    end

    alias ready open_message_stream   # obsolete

    private

    def send0( from_addr, to_addrs )
      raise IOError, 'closed session' unless @socket
      raise ArgumentError, 'mail destination not given' if to_addrs.empty?
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
      raise ArgumentError, 'both user and secret are required'\
                      unless user and secret
      auth_method = "auth_#{authtype || 'cram_md5'}"
      raise ArgumentError, "wrong auth type #{authtype}"\
                      unless respond_to?(auth_method, true)
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
      return res if allow_continue and /\A3/ === res
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

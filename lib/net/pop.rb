=begin

= net/pop.rb

written by Minero Aoki <aamine@dp.u-netsurf.ne.jp>

This library is distributed under the terms of the Ruby license.
You can freely distribute/modify this library.

=end


require 'net/session'
require 'md5'


module Net


=begin

== Net::POP3

=== Super Class

Net::Protocol

=== Class Methods

: new( address = 'localhost', port = 110 )
  This method create a new POP3 object.
  This will not open connection yet.


=== Methods

: start( account, password )
  This method start POP3.

: each{|popmail| ...}
  This method is equals to "pop3.mails.each"

: mails
  This method returns an array of ((URL:#POPMail)).
  This array is renewed when login.

=end

  class POP3 < Protocol

    Version = '1.1.3'

    protocol_param :port,         '110'
    protocol_param :command_type, '::Net::POP3Command'

    protocol_param :mail_type,    '::Net::POPMail'

    def initialize( addr = nil, port = nil )
      super
      @mails = [].freeze
    end

        
    attr :mails

    def each
      @mails.each {|m| yield m }
    end


    private


    def do_start( acnt, pwd )
      @command.auth( acnt, pwd )
      t = self.type.mail_type
      @mails = []
      @command.list.each_with_index do |size,idx|
        if size then
          @mails.push t.new( idx, size, @command )
        end
      end
      @mails.freeze
    end

  end

  POP         = POP3
  POPSession  = POP3
  POP3Session = POP3


=begin

== Net::POPMail

A class of mail which exists on POP server.

=== Super Class

Object


=== Method

: all
: pop
: mail
  This method fetches a mail and return it.

: header
  This method fetches only mail header.

: top( lines )
  This method fetches mail header and 'lines' lines body.

: delete
: delete!
  This method deletes mail.

: size
  size of mail(bytes)

: deleted?
  true if mail was deleted

=end

  class POPMail

    def initialize( n, s, cmd )
      @num     = n
      @size    = s
      @command = cmd

      @deleted = false
    end


    attr :size

    def all( dest = '' )
      @command.retr( @num, dest )
    end
    alias pop all
    alias mail all

    def top( lines, dest = '' )
      @command.top( @num, lines, dest )
    end

    def header( dest = '' )
      top( 0, dest )
    end

    def delete
      @command.dele( @num )
      @deleted = true
    end
    alias delete! delete

    def deleted?
      @deleted
    end

    def uidl
      @command.uidl @num
    end

  end


=begin

== Net::APOP

This class has no new methods. Only way of authetication is changed.

=== Super Class

Net::POP3

=end

  class APOP < POP3

    protocol_param :command_type, 'Net::APOPCommand'

  end

  APOPSession = APOP


=begin

== Net::POP3Command

POP3 command class.

=== Super Class

Net::Command

=== Class Methods

: new( socket )
  This method creates new POP3Command object. 'socket' must be ProtocolSocket.


=== Methods

: auth( account, password )
  This method do POP authorization (no RPOP)
  In case of failed authorization, raises Protocol::ProtocolError exception.

: list
  a list of mails which existing on server.
  The list is an array like "array[ number ] = size".

  ex:

    The list from server is

    1 2452
    2 3355
    4 9842
       :

    then, an array is

    [ nil, 2452, 3355, nil, 9842, ... ]

: quit
  This method ends POP using 'QUIT' commmand.

: rset
  This method reset all changes done in current session,
  by sending 'RSET' command.

: top( num, lines = 0 )
  This method gets all mail header and 'lines' lines body
  by sending 'TOP' command.  'num' is mail number.

  WARNING: the TOP command is 'Optional' in RFC1939 (POP3)

: retr( num : Integer )
  This method gets a mail by 'RETR' command. 'num' is mail number.

: dele( num : Integer )
  This method deletes a mail on server by 'DELE'.

=end


  class POP3Command < Command

    def initialize( sock )
      super
      check_reply SuccessCode
    end


    def auth( acnt, pass )
      @socket.writeline 'USER ' + acnt
      check_reply_auth

      @socket.writeline( 'PASS ' + pass )
      ret = check_reply_auth

      return ret
    end


    def list
      getok 'LIST'
      
      arr = []
      @socket.read_pendlist do |line|
        num, siz = line.split( / +/o )
        arr[ num.to_i ] = siz.to_i
      end

      return arr
    end


    def rset
      getok 'RSET'
    end


    def top( num, lines = 0, dest = '' )
      getok sprintf( 'TOP %d %d', num, lines )
      @socket.read_pendstr( dest )
    end


    def retr( num, dest = '', &block )
      getok sprintf( 'RETR %d', num )
      @socket.read_pendstr( dest, &block )
    end

    
    def dele( num )
      getok sprintf( 'DELE %d', num )
    end


    def uidl( num )
      rep = getok( sprintf 'UIDL %d', num )
      uid = rep.msg.split(' ')[1]

      uid
    end


    private


    def do_quit
      getok 'QUIT'
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


=begin

== APOPCommand

=== Super Class

POP3Command

=== Methods

: auth( account, password )
  This method do authorization by sending 'APOP' command.
  If server is not APOP server, this raises Net::ProtoAuthError exception.
  On other errors, raises Net::ProtocolError.

=end

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

end

=begin

= Net module version 1.0.2 reference manual

pop.rb written by Minero Aoki <aamine@dp.u-netsurf.ne.jp>

This library is distributed under the terms of Ruby style license.
You can freely distribute/modify/copy this file.

=end


require 'net/session'
require 'md5'


module Net

=begin

== Net::POP3Session

=== Super Class

Net::Session

=== Class Methods

: new( address = 'localhost', port = 110 )

  This method create a new POP3Session object but this will not open connection.

=end

  class POP3Session < Session


=begin

=== Methods

: start( account, password )

  This method start POP session.

: each{|popmail| ...}

  This method is equals to "POP3Session.mails.each"

: mails

  This method returns an array of <a href="#popi">POP3Session::POPMail</a>.
  This array is renewed when login.

=end

    attr :mails

    def each() @mails.each{|m| yield m} end


    private


    def proto_initialize
      @proto_type = POP3Command
      @port       = 110
      @mails      = [].freeze
    end


    def do_start( acnt, pwd )
      @proto.auth( acnt, pwd )
      @mails = []
      @proto.list.each_with_index do |size,idx|
        if size then
          @mails.push POPMail.new( idx, size, @proto )
        end
      end
      @mails.freeze
    end


    def do_finish
      @proto.quit
    end


=begin

== Net::POP3Session::POPMail

A class of mail which exists on POP server.

=== Super Class

Object

=end

    class POPMail

      def initialize( idx, siz, pro )
        @num     = idx
        @size    = siz
        @proto   = pro

        @deleted = false
      end

=begin

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

      attr :size

      def all( dest = '' )
        @proto.retr( @num, dest )
      end
      alias pop all
      alias mail all

      def top( lines, dest = '' )
        @proto.top( @num, lines, dest )
      end

      def header( dest = '' )
        top( 0, dest )
      end

      def delete
        @proto.dele( @num )
        @deleted = true
      end
      alias delete! delete

      def deleted?
        @deleted
      end

    end

  end   # POP3Session

  POPSession = POP3Session
  POP3       = POP3Session


=begin

== Net::APOP3Session

This class has no new methods. Only way of authetication is changed.

=== Super Class

Net::POP3Session

=end

  class APOPSession < POP3Session

    def proto_initialize
      super
      @proto_type = APOPCommand
    end

  end

  APOP = APOPSession


=begin

== Net::POP3Command

POP3 protocol class.

=== Super Class

Net::Command

=== Class Methods

: new( socket )

  This method creates new POP3Command object. 'socket' must be ProtocolSocket.

=end

  class POP3Command < Command


=begin

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

  This method finishes POP3 session.

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

    def auth( acnt, pass )
      @socket.writeline( 'USER ' + acnt )
      check_reply_auth

      @socket.writeline( 'PASS ' + pass )
      ret = check_reply_auth

      return ret
    end


    def list
      @socket.writeline( 'LIST' )
      check_reply( SuccessCode )
      
      arr = []
      @socket.read_pendlist do |line|
        num, siz = line.split( / +/o )
        arr[ num.to_i ] = siz.to_i
      end

      return arr
    end


    def rset
      @socket.writeline( 'RSET' )
      check_reply( SuccessCode )
    end


    def top( num, lines = 0, dest = '' )
      @socket.writeline( sprintf( 'TOP %d %d', num, lines ) )
      check_reply( SuccessCode )

      return @socket.read_pendstr( dest )
    end


    def retr( num, dest = '', &block )
      @socket.writeline( sprintf( 'RETR %d', num ) )
      check_reply( SuccessCode )

      return @socket.read_pendstr( dest, &block )
    end

    
    def dele( num )
      @socket.writeline( sprintf( 'DELE %s', num ) )
      check_reply( SuccessCode )
    end



    private


    def do_quit
      @socket.writeline( 'QUIT' )
      check_reply( SuccessCode )
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

POP3

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


  unless Session::Version == '1.0.2' then
    $stderr.puts "WARNING: wrong version of session.rb & pop.rb"
  end

end

=begin

= net/pop.rb

written by Minero Aoki <aamine@dp.u-netsurf.ne.jp>

This library is distributed under the terms of the Ruby license.
You can freely distribute/modify this library.

=end


require 'net/protocol'
require 'md5'


module Net


=begin

== Net::POP3

=== Super Class

Net::Protocol

=== Class Methods

: new( address = 'localhost', port = 110 )
  creates a new Net::POP3 object.
  This method does not open TCP connection yet.

: start( address = 'localhost', port = 110, *protoargs )
: start( address = 'localhost', port = 110, *protoargs ) {|pop| .... }
  equals to Net::POP3.new( address, port ).start( *protoargs )

=== Methods

: start( account, password )
: start( account, password ) {|pop| .... }
  starts POP3 session.

  When called as iterator, give a POP3 object to block and
  close session after block call is finished.

: each {|popmail| .... }
  This method is equals to "pop3.mails.each"

: mails
  an array of ((URL:#POPMail)).
  This array is renewed when session started.

=end

  class POP3 < Protocol

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

      @mails = []
      t = type.mail_type
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

: all( dest = '' )
: pop
: mail
  This method fetches a mail and write to 'dest' using '<<' method.

    # usage example

    mailarr = []
    POP3.start( 'localhost', 110 ) do |pop|
      pop.each do |popm|
        mailarr.push popm.pop   # all() returns 'dest' (this time, string)
        # or, you can also
        # popm.pop( $stdout )   # write mail to stdout
      end
    end

: all {|str| .... }
  You can use all/pop/mail as the iterator.
  argument 'str' is a read string (a part of mail).

    # usage example

    POP3.start( 'localhost', 110 ) do |pop|
      pop.mails[0].pop do |str|               # pop only first mail...
        _do_anything_( str )
      end
    end

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
      if iterator? then
        dest = ReadAdapter.new( Proc.new )
      end
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

This class defines no new methods.
Only difference from POP3 is using APOP authentification.

=== Super Class

Net::POP3

=end

  class APOP < POP3

    protocol_param :command_type, 'Net::APOPCommand'

  end

  APOPSession = APOP



  class POP3Command < Command

    def initialize( sock )
      super
      critical {
        check_reply SuccessCode
      }
    end


    def auth( acnt, pass )
      critical {
        @socket.writeline 'USER ' + acnt
        check_reply_auth

        @socket.writeline 'PASS ' + pass
        check_reply_auth
      }
    end


    def list
      arr = []
      critical {
        getok 'LIST'
        @socket.read_pendlist do |line|
          num, siz = line.split( / +/o )
          arr[ num.to_i ] = siz.to_i
        end
      }
      arr
    end


    def rset
      critical {
        getok 'RSET'
      }
    end


    def top( num, lines = 0, dest = '' )
      critical {
        getok sprintf( 'TOP %d %d', num, lines )
        @socket.read_pendstr( dest )
      }
    end


    def retr( num, dest = '', &block )
      critical {
        getok sprintf( 'RETR %d', num )
        @socket.read_pendstr( dest, &block )
      }
    end

    
    def dele( num )
      critical {
        getok sprintf( 'DELE %d', num )
      }
    end


    def uidl( num )
      critical {
        getok( sprintf 'UIDL %d', num ).msg.split(' ')[1]
      }
    end


    def quit
      critical {
        getok 'QUIT'
      }
    end


    private


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
        return Response.new( SuccessCode, str[0,3], str[3, str.size - 3].strip )
      else
        return Response.new( ErrorCode, str[0,4], str[4, str.size - 4].strip )
      end
    end

  end



  class APOPCommand < POP3Command

    def initialize( sock )
      rep = super( sock )

      m = /<.+>/.match( rep.msg )
      unless m then
        raise ProtoAuthError, "This is not APOP server: can't login"
      end
      @stamp = m[0]
    end


    def auth( account, pass )
      critical {
        @socket.writeline sprintf( 'APOP %s %s',
                            account, MD5.new(@stamp + pass).hexdigest )
        check_reply_auth
      }
    end

  end

end

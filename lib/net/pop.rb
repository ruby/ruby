=begin

= net/pop.rb version 1.1.37

Copyright (c) 1999-2001 Yukihiro Matsumoto

written & maintained by Minero Aoki <aamine@loveruby.net>

This program is free software. You can re-distribute and/or
modify this program under the same terms as Ruby itself,
Ruby Distribute License or GNU General Public License.

NOTE: You can find Japanese version of this document in
the doc/net directory of the standard ruby interpreter package.

== What is This Module?

This module provides your program the functions to retrieve
mails via POP3, Post Office Protocol version 3. For details
of POP3, refer [RFC1939] ((<URL:http://www.ietf.org/rfc/rfc1939.txt>)).

== Examples

=== Retrieving Mails

This example retrieves mails from server and delete it (on server).
Mails are written in file named 'inbox/1', 'inbox/2', ....
Replace 'pop3.server.address' your POP3 server address.

    require 'net/pop'

    Net::POP3.start( 'pop3.server.address', 110,
                     'YourAccount', 'YourPassword' ) {|pop|
      if pop.mails.empty? then
        puts 'no mail.'
      else
        i = 0
        pop.each_mail do |m|   # or "pop.mails.each ..."
          File.open( 'inbox/' + i.to_s, 'w' ) {|f|
            f.write m.pop
          }
          m.delete
          i += 1
        end
      end
      puts "#{pop.mails.size} mails popped."
    }

=== Shorter Version

    require 'net/pop'
    Net::POP3.start( 'pop3.server.address', 110,
                     'YourAccount', 'YourPassword' ) {|pop|
      if pop.mails.empty? then
        puts 'no mail.'
      else
        i = 0
        pop.delete_all do |m|
          File.open( 'inbox/' + i.to_s, 'w' ) {|f|
            f.write m.pop
          }
          i += 1
        end
      end
    }

And here is more shorter example.

    require 'net/pop'
    i = 0
    Net::POP3.delete_all( 'pop3.server.address', 110,
                          'YourAccount', 'YourPassword' ) do |m|
      File.open( 'inbox/' + i.to_s, 'w' ) {|f|
        f.write m.pop
      }
      i += 1
    end

=== Writing to File directly

All examples above get mail as one big string.
This example does not create such one.

    require 'net/pop'
    Net::POP3.delete_all( 'pop3.server.address', 110,
                          'YourAccount', 'YourPassword' ) do |m|
      File.open( 'inbox', 'w' ) {|f|
        m.pop f   ####
      }
    end

=== Using APOP

net/pop also supports APOP authentication. There's two way to use APOP:
(1) using APOP class instead of POP3
(2) passing true for fifth argument of POP3.start

    # (1)
    require 'net/pop'
    Net::APOP.start( 'apop.server.address', 110,
                     'YourAccount', 'YourPassword' ) {|pop|
      # Rest code is same.
    }

    # (2)
    require 'net/pop'
    Net::POP3.start( 'apop.server.address', 110,
                     'YourAccount', 'YourPassword',
                     true   ####
    ) {|pop|
      # Rest code is same.
    }

== Net::POP3 class

=== Class Methods

: new( address, port = 110, apop = false )
    creates a new Net::POP3 object.
    This method does not open TCP connection yet.

: start( address, port = 110, account, password )
: start( address, port = 110, account, password ) {|pop| .... }
    equals to Net::POP3.new( address, port ).start( account, password )

        Net::POP3.start( addr, port, account, password ) do |pop|
          pop.each_mail do |m|
            file.write m.pop
            m.delete
          end
        end

: foreach( address, port = 110, account, password ) {|mail| .... }
    starts POP3 protocol and iterates for each POPMail object.
    This method equals to

        Net::POP3.start( address, port, account, password ) {|pop|
          pop.each_mail do |m|
            yield m
          end
        }

        # example
        Net::POP3.foreach( 'your.pop.server', 110,
                           'YourAccount', 'YourPassword' ) do |m|
          file.write m.pop
          m.delete if $DELETE
        end

: delete_all( address, port = 110, account, password )
: delete_all( address, port = 110, account, password ) {|mail| .... }
    starts POP3 session and delete all mails.
    If block is given, iterates for each POPMail object before delete.

        # example
        Net::POP3.delete_all( addr, nil, 'YourAccount', 'YourPassword' ) do |m|
          m.pop file
        end

: auth_only( address, port = 110, account, password )
    (just for POP-before-SMTP)
    opens POP3 session and does autholize and quit.
    This method must not be called while POP3 session is opened.

        # example
        pop = Net::POP3.auth_only( 'your.pop3.server',
                                    nil,     # using default (110)
                                   'YourAccount',
                                   'YourPassword' )

=== Instance Methods

: start( account, password )
: start( account, password ) {|pop| .... }
    starts POP3 session.

    When called with block, gives a POP3 object to block and
    closes the session after block call finish.

: active?
    true if POP3 session is started.

: address
    the address to connect

: port
    the port number to connect

: open_timeout
: open_timeout=(n)
    seconds to wait until connection is opened.
    If POP3 object cannot open a conection in this seconds,
    it raises TimeoutError exception.

: read_timeout
: read_timeout=(n)
    seconds to wait until reading one block (by one read(1) call).
    If POP3 object cannot open a conection in this seconds,
    it raises TimeoutError exception.

: finish
    finishes POP3 session.
    If POP3 session had not be started, raises an IOError.

: mails
    an array of Net::POPMail objects.
    This array is renewed when session started.

: each_mail {|popmail| .... }
: each {|popmail| .... }
    is equals to "pop3.mails.each"

: delete_all
: delete_all {|popmail| .... }
    deletes all mails on server.
    If called with block, gives mails to the block before deleting.

        # example
        n = 1
        pop.delete_all do |m|
          File.open("inbox/#{n}") {|f| f.write m.pop }
          n += 1
        end

: auth_only( account, password )
    (just for POP-before-SMTP)
    opens POP3 session and does autholize and quit.
    This method must not be called while POP3 session is opened.
        # example
        pop = Net::POP3.new( 'your.pop3.server' )
        pop.auth_only 'YourAccount', 'YourPassword'

: reset
    reset the session. All "deleted mark" are removed.

== Net::APOP

This class defines no new methods.
Only difference from POP3 is using APOP authentification.

=== Super Class
Net::POP3

== Net::POPMail

A class of mail which exists on POP server.

=== Instance Methods

: pop( dest = '' )
    This method fetches a mail and write to 'dest' using '<<' method.

        # example
        allmails = nil
        POP3.start( 'your.pop3.server', 110,
                    'YourAccount, 'YourPassword' ) do |pop|
          allmails = pop.mails.collect {|popmail| popmail.pop }
        end

: pop {|str| .... }
    gives the block part strings of a mail.

        # example
        POP3.start( 'localhost', 110 ) {|pop3|
          pop3.each_mail do |m|
            m.pop do |str|
              # do anything
            end
          end
        }

: header
    This method fetches only mail header.

: top( lines )
    This method fetches mail header and LINES lines of body.

: delete
    deletes mail on server.

: size
    mail size (bytes)

: deleted?
    true if mail was deleted

=end

require 'net/protocol'
require 'digest/md5'


module Net

  class POP3 < Protocol

    protocol_param :port,         '110'
    protocol_param :command_type, '::Net::NetPrivate::POP3Command'
    protocol_param :apop_command_type, '::Net::NetPrivate::APOPCommand'

    protocol_param :mail_type,    '::Net::POPMail'

    class << self

      def foreach( address, port = nil,
                   account = nil, password = nil, &block )
        start( address, port, account, password ) do |pop|
          pop.each_mail( &block )
        end
      end

      def delete_all( address, port = nil,
                      account = nil, password = nil, &block )
        start( address, port, account, password ) do |pop|
          pop.delete_all( &block )
        end
      end

      def auth_only( address, port = nil,
                     account = nil, password = nil )
        new( address, port ).auth_only account, password
      end

    end


    def initialize( addr, port = nil, apop = false )
      super addr, port
      @mails = nil
      @apop = false
    end

    def auth_only( account, password )
      begin
        connect
        @active = true
        @command.auth address, port
        @command.quit
      ensure
        @active = false
        disconnect
      end
    end

    attr :mails

    def each_mail( &block )
      io_check
      @mails.each( &block )
    end

    alias each each_mail

    def delete_all
      io_check
      @mails.each do |m|
        yield m if block_given?
        m.delete unless m.deleted?
      end
    end

    def reset
      io_check
      @command.rset
      @mails.each do |m|
        m.instance_eval { @deleted = false }
      end
    end


    private

    def conn_command( sock )
      @command =
          (@apop ? type.apop_command_type : type.command_type).new(sock)
    end

    def do_start( account, password )
      @command.auth account, password

      mails = []
      mtype = type.mail_type
      @command.list.each_with_index do |size,idx|
        mails.push mtype.new(idx, size, @command) if size
      end
      @mails = mails.freeze
    end

    def io_check
      (not @socket or @socket.closed?) and
              raise IOError, 'pop session is not opened yet'
    end

  end

  POP         = POP3
  POPSession  = POP3
  POP3Session = POP3


  class APOP < POP3
    protocol_param :command_type, 'Net::NetPrivate::APOPCommand'
  end

  APOPSession = APOP


  class POPMail

    def initialize( n, s, cmd )
      @num     = n
      @size    = s
      @command = cmd

      @deleted = false
    end

    attr :size

    def inspect
      "#<#{type} #{@num}#{@deleted ? ' deleted' : ''}>"
    end

    def pop( dest = '', &block )
      if block then
        dest = NetPrivate::ReadAdapter.new( block )
      end
      @command.retr( @num, dest )
    end

    alias all pop
    alias mail pop

    def top( lines, dest = '' )
      @command.top( @num, lines, dest )
    end

    def header( dest = '' )
      top 0, dest
    end

    def delete
      @command.dele @num
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



  module NetPrivate


  class POP3Command < Command

    def initialize( sock )
      super
      critical {
        check_reply SuccessCode
      }
    end

    def auth( account, pass )
      critical {
        @socket.writeline 'USER ' + account
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
          m = /\A(\d+)[ \t]+(\d+)/.match(line) or
                  raise BadResponse, "illegal response: #{line}"
          arr[ m[1].to_i ] = m[2].to_i
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
        @socket.read_pendstr dest
      }
    end

    def retr( num, dest = '', &block )
      critical {
        getok sprintf('RETR %d', num)
        @socket.read_pendstr dest, &block
      }
    end
    
    def dele( num )
      critical {
        getok sprintf('DELE %d', num)
      }
    end

    def uidl( num )
      critical {
        getok( sprintf('UIDL %d', num) ).msg.split(' ')[1]
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
        return check_reply( SuccessCode )
      rescue ProtocolError => err
        raise ProtoAuthError.new( 'Fail to POP authentication', err.response )
      end
    end

    def get_reply
      str = @socket.readline

      if /\A\+/ === str then
        Response.new( SuccessCode, str[0,3], str[3, str.size - 3].strip )
      else
        Response.new( ErrorCode, str[0,4], str[4, str.size - 4].strip )
      end
    end

  end


  class APOPCommand < POP3Command

    def initialize( sock )
      rep = super( sock )

      m = /<.+>/.match( rep.msg ) or
              raise ProtoAuthError.new( "not APOP server: cannot login", nil )
      @stamp = m[0]
    end

    def auth( account, pass )
      critical {
        @socket.writeline sprintf( 'APOP %s %s',
                                   account,
                                   Digest::MD5.hexdigest(@stamp + pass) )
        check_reply_auth
      }
    end

  end


  end   # module Net::NetPrivate

end   # module Net

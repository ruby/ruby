=begin

= net/pop.rb

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

This module provides your program the functions to retrieve
mails via POP3, Post Office Protocol version 3. For details
of POP3, refer [RFC1939] ((<URL:http://www.ietf.org/rfc/rfc1939.txt>)).

== Examples

=== Retrieving Mails

This example retrieves mails from server and delete it (on server).
Mails are written in file named 'inbox/1', 'inbox/2', ....
Replace 'pop3.server.address' your POP3 server address.

    require 'net/pop'

    pop = Net::POP3.new('pop3.server.address', 110)
    pop.start('YourAccount', 'YourPassword')          ###
    if pop.mails.empty? then
      puts 'no mail.'
    else
      i = 0
      pop.each_mail do |m|   # or "pop.mails.each ..."
        File.open('inbox/' + i.to_s, 'w') {|f|
            f.write m.pop
        }
        m.delete
        i += 1
      end
      puts "#{pop.mails.size} mails popped."
    end
    pop.finish                                        ###

(1) call Net::POP3#start and start POP session
(2) access mails by using POP3#each_mail and/or POP3#mails
(3) close POP session by calling POP3#finish or use block form #start.

This example is using block form #start to close the session.
=== Enshort Code

The example above is very verbose. You can enshort code by using
some utility methods. At first, block form of Net::POP3.start can
alternates POP3.new, POP3#start and POP3#finish.

    require 'net/pop'

    Net::POP3.start('pop3.server.address', 110)
                    'YourAccount', 'YourPassword')
        if pop.mails.empty?
          puts 'no mail.'
        else
          i = 0
          pop.each_mail do |m|   # or "pop.mails.each ..."
            File.open('inbox/' + i.to_s, 'w') {|f|
                f.write m.pop
            }
            m.delete
            i += 1
          end
          puts "#{pop.mails.size} mails popped."
        end
    }

POP3#delete_all alternates #each_mail and m.delete.

    require 'net/pop'

    Net::POP3.start('pop3.server.address', 110,
                    'YourAccount', 'YourPassword') {|pop|
        if pop.mails.empty?
          puts 'no mail.'
        else
          i = 0
          pop.delete_all do |m|
            File.open('inbox/' + i.to_s, 'w') {|f|
                f.write m.pop
            }
            i += 1
          end
        end
    }

And here is more shorter example.

    require 'net/pop'

    i = 0
    Net::POP3.delete_all('pop3.server.address', 110,
                         'YourAccount', 'YourPassword') do |m|
      File.open('inbox/' + i.to_s, 'w') {|f|
          f.write m.pop
      }
      i += 1
    end

=== Writing to File directly

All examples above get mail as one big string.
This example does not create such one.

    require 'net/pop'
    Net::POP3.delete_all('pop3.server.address', 110,
                         'YourAccount', 'YourPassword') do |m|
      File.open('inbox', 'w') {|f|
          m.pop f   ####
      }
    end

=== Using APOP

The net/pop library supports APOP authentication.
To use APOP, use Net::APOP class instead of Net::POP3 class.
You can use utility method, Net::POP3.APOP(). Example:

    require 'net/pop'

    # use APOP authentication if $isapop == true
    pop = Net::POP3.APOP($isapop).new('apop.server.address', 110)
    pop.start(YourAccount', 'YourPassword') {|pop|
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

        Net::POP3.start( addr, port, account, password ) {|pop|
            pop.each_mail do |m|
              file.write m.pop
              m.delete
            end
        }

: APOP( is_apop )
    returns Net::APOP class object if IS_APOP is true.
    returns Net::POP3 class object if false.
    Use this method like:

        # example 1
        pop = Net::POP3::APOP($isapop).new( addr, port )

        # example 2
        Net::POP3::APOP($isapop).start( addr, port ) {|pop|
            ....
        }

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
        Net::POP3.auth_only( 'your.pop3.server',
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
                    'YourAccount, 'YourPassword' ) {|pop|
            allmails = pop.mails.collect {|popmail| popmail.pop }
        }

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

  class BadResponseError < StandardError; end


  class POP3 < Protocol

    protocol_param :default_port,      '110'
    protocol_param :command_type,      '::Net::POP3Command'
    protocol_param :apop_command_type, '::Net::APOPCommand'
    protocol_param :mail_type,         '::Net::POPMail'
    protocol_param :socket_type,       '::Net::InternetMessageIO'

    def POP3.APOP( isapop )
      isapop ? APOP : POP3
    end

    def POP3.foreach( address, port = nil,
                      account = nil, password = nil, &block )
      start(address, port, account, password) {|pop|
          pop.each_mail(&block)
      }
    end

    def POP3.delete_all( address, port = nil,
                         account = nil, password = nil, &block )
      start(address, port, account, password) {|pop|
          pop.delete_all(&block)
      }
    end

    def POP3.auth_only( address, port = nil,
                        account = nil, password = nil )
      new(address, port).auth_only account, password
    end

    def auth_only( account, password )
      raise IOError, 'opening already opened POP session' if active?
      start(account, password) {
          ;
      }
    end

    #
    # connection
    #

    def initialize( addr, port = nil, apop = false )
      super addr, port
      @mails = nil
      @apop = false
    end

    private

    def do_start( account, password )
      conn_socket
      conn_command
      @command.auth account, password
    end

    def conn_command
      @command = (@apop ? self.class.apop_command_type :
                          self.class.command_type      ).new(socket())
    end

    def do_finish
      @mails = nil
      disconn_command
      disconn_socket
    end

    #
    # POP operations
    #

    public

    def mail_size
      return @nmails if @nmails
      @nmails, @bytes = command().stat
      @nmails
    end

    def bytes
      return @bytes if @bytes
      @nmails, @bytes = command().stat
      @bytes
    end

    def mails
      return @mails if @mails
      if mail_size() == 0
        # some popd raises error for LIST on the empty mailbox.
        @mails = []
        return @mails
      end

      mails = []
      mailclass = self.class.mail_type
      command().list.each_with_index do |size,idx|
        mails.push mailclass.new(idx, size, command()) if size
      end
      @mails = mails.freeze

      @mails
    end

    def each_mail( &block )
      mails().each(&block)
    end

    alias each each_mail

    def delete_all
      mails().each do |m|
        yield m if block_given?
        m.delete unless m.deleted?
      end
    end

    def reset
      command().rset
      mails().each do |m|
        m.instance_eval {
            @deleted = false
        }
      end
    end

    def command
      io_check
      super
    end

    def io_check
      raise IOError, 'POP session is not opened yet'\
              if not socket() or socket().closed?
    end

  end

  POP = POP3
  POPSession  = POP3
  POP3Session = POP3

  class APOP < POP3
    def APOP.command_type
      APOPCommand
    end
  end

  APOPSession = APOP


  class POPMail

    def initialize( n, s, cmd )
      @num     = n
      @size    = s
      @command = cmd

      @deleted = false
    end

    attr_reader :size

    def inspect
      "#<#{self.class} #{@num}#{@deleted ? ' deleted' : ''}>"
    end

    def pop( dest = '', &block )
      dest = ReadAdapter.new(block) if block
      @command.retr @num, dest
    end

    alias all pop
    alias mail pop

    def top( lines, dest = '' )
      @command.top @num, lines, dest
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


  class POP3Command < Command

    def initialize( sock )
      super
      atomic {
          check_reply SuccessCode
      }
    end

    def auth( account, pass )
      atomic {
          @socket.writeline 'USER ' + account
          check_reply_auth

          @socket.writeline 'PASS ' + pass
          check_reply_auth
      }
    end

    def list
      atomic {
          getok 'LIST'
          list = []
          @socket.each_list_item do |line|
            m = /\A(\d+)[ \t]+(\d+)/.match(line) or
                    raise BadResponse, "bad response: #{line}"
            list[m[1].to_i] = m[2].to_i
          end
          return list
      }
    end

    def stat
      atomic {
          @socket.writeline 'STAT'
          line = @socket.readline
          m = /\A\+OK (\d+)[ \t]+(\d+)/.match(line) or
                  raise BadResponseError, "illegal response: #{line}"
          return [m[1].to_i, m[2].to_i]
      }
    end

    def rset
      atomic {
          getok 'RSET'
      }
    end


    def top( num, lines = 0, dest = '' )
      atomic {
          getok sprintf('TOP %d %d', num, lines)
          @socket.read_message_to dest
      }
    end

    def retr( num, dest = '' )
      atomic {
          getok sprintf('RETR %d', num)
          @socket.read_message_to dest
      }
    end
    
    def dele( num )
      atomic {
          getok sprintf('DELE %d', num)
      }
    end

    def uidl( num )
      atomic {
          getok(sprintf('UIDL %d', num)).message.split(/ /)[1]
      }
    end

    def quit
      atomic {
          getok 'QUIT'
      }
    end

    private

    def check_reply_auth
      begin
        return check_reply(SuccessCode)
      rescue ProtocolError => err
        raise ProtoAuthError.new('Fail to POP authentication', err.response)
      end
    end

    def get_reply
      str = @socket.readline
      if /\A\+/ === str
        Response.new(SuccessCode, str[0,3], str[3, str.size - 3].strip)
      else
        Response.new(ErrorCode, str[0,4], str[4, str.size - 4].strip)
      end
    end

  end


  class APOPCommand < POP3Command

    def initialize( sock )
      @stamp = super(sock).message.slice(/<.+>/) or
              raise ProtoAuthError.new("not APOP server: cannot login", nil)
    end

    def auth( account, pass )
      atomic {
          @socket.writeline sprintf('APOP %s %s',
                                    account,
                                    Digest::MD5.hexdigest(@stamp + pass))
          check_reply_auth
      }
    end

  end

end   # module Net

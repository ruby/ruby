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

    # Use APOP authentication if $isapop == true
    pop = Net::POP3.APOP($isapop).new('apop.server.address', 110)
    pop.start(YourAccount', 'YourPassword') {|pop|
        # Rest code is same.
    }

=== Fetch Only Selected Mail Using POP UIDL Function

If your POP server provides UIDL function,
you can pop only selected mails from POP server.
e.g.

    def need_pop?( id )
      # determine if we need pop this mail...
    end

    Net::POP3.start('pop.server', 110,
                    'Your account', 'Your password') {|pop|
      pop.mails.select {|m| need_pop?(m.unique_id) }.each do |m|
        do_something(m.pop)
      end
    }

POPMail#unique_id method returns the unique-id of the message (String).
Normally unique-id is a hash of the message.


== class Net::POP3

=== Class Methods

: new( address, port = 110, isapop = false )
    creates a new Net::POP3 object.
    This method does NOT open TCP connection yet.

: start( address, port = 110, account, password, isapop = false )
: start( address, port = 110, account, password, isapop = false ) {|pop| .... }
    equals to Net::POP3.new(address, port, isapop).start(account, password).
    This method raises POPAuthenticationError if authentication is failed.

        # Typical usage
        Net::POP3.start(addr, port, account, password) {|pop|
            pop.each_mail do |m|
              file.write m.pop
              m.delete
            end
        }

: APOP( is_apop )
    returns Net::APOP class object if IS_APOP is true.
    returns Net::POP3 class object if false.
    Use this method like:

        # Example 1
        pop = Net::POP3::APOP($isapop).new( addr, port )

        # Example 2
        Net::POP3::APOP($isapop).start( addr, port ) {|pop|
            ....
        }

: foreach( address, port = 110, account, password, isapop = false ) {|mail| .... }
    starts POP3 protocol and iterates for each POPMail object.
    This method equals to:

        Net::POP3.start( address, port, account, password ) {|pop|
            pop.each_mail do |m|
              yield m
            end
        }

    This method raises POPAuthenticationError if authentication is failed.

        # Typical usage
        Net::POP3.foreach( 'your.pop.server', 110,
                           'YourAccount', 'YourPassword' ) do |m|
          file.write m.pop
          m.delete if $DELETE
        end

: delete_all( address, port = 110, account, password, isapop = false )
: delete_all( address, port = 110, account, password, isapop = false ) {|mail| .... }
    starts POP3 session and delete all mails.
    If block is given, iterates for each POPMail object before delete.
    This method raises POPAuthenticationError if authentication is failed.

        # Example
        Net::POP3.delete_all( addr, nil, 'YourAccount', 'YourPassword' ) do |m|
          m.pop file
        end

: auth_only( address, port = 110, account, password, isapop = false )
    (just for POP-before-SMTP)

    opens POP3 session and does autholize and quit.
    This method must not be called while POP3 session is opened.
    This method raises POPAuthenticationError if authentication is failed.

        # Example
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

    This method raises POPAuthenticationError if authentication is failed.

: started?
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

: n_mails
    returns the number of mails on the POP server.

: n_bytes
    returns the bytes of all mails on the POP server.

: mails
    an array of Net::POPMail objects.
    This array is renewed when session restarts.

    This method raises POPError if any problem happend.

: each_mail {|popmail| .... }
: each {|popmail| .... }
    is equals to "pop3.mails.each"

    This method raises POPError if any problem happend.

: delete_all
: delete_all {|popmail| .... }
    deletes all mails on server.
    If called with block, gives mails to the block before deleting.

        # Example
        n = 1
        pop.delete_all do |m|
          File.open("inbox/#{n}") {|f| f.write m.pop }
          n += 1
        end

    This method raises POPError if any problem happend.

: reset
    reset the session. All "deleted mark" are removed.

    This method raises POPError if any problem happend.


== class Net::APOP

This class defines no new methods.
Only difference from POP3 is using APOP authentification.

=== Super Class

Net::POP3


== class Net::POPMail

A class of mail which exists on POP server.

=== Instance Methods

: pop( dest = '' )
    This method fetches a mail and write to 'dest' using '<<' method.

    This method raises POPError if any problem happend.

        # Typical usage
        allmails = nil
        POP3.start( 'your.pop3.server', 110,
                    'YourAccount, 'YourPassword' ) {|pop|
            allmails = pop.mails.collect {|popmail| popmail.pop }
        }

: pop {|str| .... }
    gives the block part strings of a mail.

    This method raises POPError if any problem happend.

        # Typical usage
        POP3.start( 'localhost', 110 ) {|pop3|
            pop3.each_mail do |m|
              m.pop do |str|
                # do anything
              end
            end
        }

: header
    fetches only mail header.

    This method raises POPError if any problem happend.

: top( lines )
    fetches mail header and LINES lines of body.

    This method raises POPError if any problem happend.

: delete
    deletes mail on server.

    This method raises POPError if any problem happend.

: size
    mail size (bytes)

: deleted?
    true if mail was deleted

: unique_id
    returns an unique-id of the message.
    Normally unique-id is a hash of the message.

    This method raises POPError if any problem happend.

=end

require 'net/protocol'
require 'digest/md5'


module Net

  class POPError < ProtocolError; end
  class POPAuthenticationError < ProtoAuthError; end
  class POPBadResponse < StandardError; end


  class POP3 < Protocol

    Revision = %q$Revision$.split[1]

    #
    # Class Parameters
    #

    def POP3.default_port
      110
    end

    def POP3.socket_type
      Net::InternetMessageIO
    end

    #
    # Utilities
    #

    def POP3.APOP( isapop )
      isapop ? APOP : POP3
    end

    def POP3.foreach( address, port = nil,
                      account = nil, password = nil,
                      isapop = false, &block )
      start(address, port, account, password, isapop) {|pop|
          pop.each_mail(&block)
      }
    end

    def POP3.delete_all( address, port = nil,
                         account = nil, password = nil,
                         isapop = false, &block )
      start(address, port, account, password, isapop) {|pop|
          pop.delete_all(&block)
      }
    end

    def POP3.auth_only( address, port = nil,
                        account = nil, password = nil,
                        isapop = false )
      new(address, port, isapop).auth_only account, password
    end

    def auth_only( account, password )
      raise IOError, 'opening already opened POP session' if started?
      start(account, password) {
          ;
      }
    end

    #
    # Session management
    #

    def POP3.start( address, port = nil,
                    account = nil, password = nil,
                    isapop = false, &block )
      new(address, port, isapop).start(account, password, &block)
    end

    def initialize( addr, port = nil, isapop = false )
      @address = addr
      @port = port || self.class.default_port
      @apop = isapop

      @command = nil
      @socket = nil
      @started = false
      @open_timeout = 30
      @read_timeout = 60
      @debug_output = nil

      @mails = nil
      @n_mails = nil
      @n_bytes = nil
    end

    def apop?
      @apop
    end

    def inspect
      "#<#{self.class} #{@address}:#{@port} open=#{@started}>"
    end

    def set_debug_output( arg )   # :nodoc:
      @debug_output = arg
    end

    attr_reader :address
    attr_reader :port

    attr_accessor :open_timeout
    attr_reader :read_timeout

    def read_timeout=( sec )
      @command.socket.read_timeout = sec if @command
      @read_timeout = sec
    end

    def started?
      @started
    end

    alias active? started?   # backward compatibility

    def start( account, password )
      raise IOError, 'POP session already started' if @started

      if block_given?
        begin
          do_start account, password
          return yield(self)
        ensure
          finish if @started
        end
      else
        do_start account, password
        return self
      end
    end

    def do_start( account, password )
      @socket = self.class.socket_type.open(@address, @port,
                                   @open_timeout, @read_timeout, @debug_output)
      on_connect
      @command = POP3Command.new(@socket)
      if apop?
        @command.apop account, password
      else
        @command.auth account, password
      end
      @started = true
    end
    private :do_start

    def on_connect
    end
    private :on_connect

    def finish
      raise IOError, 'already closed POP session' unless @started
      @mails = nil
      @command.quit if @command
      @command = nil
      @socket.close if @socket and not @socket.closed?
      @socket = nil
      @started = false
    end

    def command
      raise IOError, 'POP session not opened yet' \
                                      if not @socket or @socket.closed?
      @command
    end
    private :command

    #
    # POP protocol wrapper
    #

    def n_mails
      return @n_mails if @n_mails
      @n_mails, @n_bytes = command().stat
      @n_mails
    end

    def n_bytes
      return @n_bytes if @n_bytes
      @n_mails, @n_bytes = command().stat
      @n_bytes
    end

    def mails
      return @mails.dup if @mails
      if n_mails() == 0
        # some popd raises error for LIST on the empty mailbox.
        @mails = []
        return []
      end

      @mails = command().list.map {|num, size|
          POPMail.new(num, size, self, command())
      }
      @mails.dup
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

    # internal use only (called from POPMail#uidl).
    def set_all_uids
      command().uidl.each do |num, uid|
        @mails.find {|m| m.number == num }.uid = uid
      end
    end

  end

  # aliases
  POP = POP3
  POPSession  = POP3
  POP3Session = POP3

  class APOP < POP3
    def apop?
      true
    end
  end

  APOPSession = APOP


  class POPMail

    def initialize( num, size, pop, cmd )
      @number = num
      @size = size
      @pop = pop
      @command = cmd
      @deleted = false
      @uid = nil
    end

    attr_reader :number
    attr_reader :size

    def inspect
      "#<#{self.class} #{@number}#{@deleted ? ' deleted' : ''}>"
    end

    def pop( dest = '', &block )
      @command.retr(@number, (block ? ReadAdapter.new(block) : dest))
    end

    alias all pop    # backward compatibility
    alias mail pop   # backward compatibility

    def top( lines, dest = '' )
      @command.top(@number, lines, dest)
    end

    def header( dest = '' )
      top(0, dest)
    end

    def delete
      @command.dele @number
      @deleted = true
    end

    alias delete! delete    # backward compatibility

    def deleted?
      @deleted
    end

    def unique_id
      return @uid if @uid
      @pop.set_all_uids
      @uid
    end

    alias uidl unique_id

    # internal use only (used from POP3#set_all_uids).
    def uid=( uid )
      @uid = uid
    end

  end


  class POP3Command

    def initialize( sock )
      @socket = sock
      @in_critical_block = false
      res = check_response(critical { recv_response() })
      @apop_stamp = res.slice(/<.+>/)
    end

    def inspect
      "#<#{self.class} socket=#{@socket}>"
    end

    def auth( account, password )
      check_response_auth(critical { get_response('USER ' + account) })
      check_response_auth(critical { get_response('PASS ' + password) })
    end

    def apop( account, password )
      raise POPAuthenticationError, 'not APOP server; cannot login' \
                                                      unless @apop_stamp
      check_response_auth(critical {
          get_response('APOP %s %s',
                       account,
                       Digest::MD5.hexdigest(@apop_stamp + password))
      })
    end

    def list
      critical {
          getok 'LIST'
          list = []
          @socket.each_list_item do |line|
            m = /\A(\d+)[ \t]+(\d+)/.match(line) or
                    raise POPBadResponse, "bad response: #{line}"
            list.push [m[1].to_i, m[2].to_i]
          end
          list
      }
    end

    def stat
      res = check_response(critical { get_response('STAT') })
      m = /\A\+OK\s+(\d+)\s+(\d+)/.match(res) or
              raise POPBadResponse, "wrong response format: #{res}"
      [m[1].to_i, m[2].to_i]
    end

    def rset
      check_response(critical { get_response 'RSET' })
    end

    def top( num, lines = 0, dest = '' )
      critical {
          getok('TOP %d %d', num, lines)
          @socket.read_message_to(dest)
      }
    end

    def retr( num, dest = '' )
      critical {
          getok('RETR %d', num)
          @socket.read_message_to dest
      }
    end
    
    def dele( num )
      check_response(critical { get_response('DELE %d', num) })
    end

    def uidl( num = nil )
      if num
        res = check_response(critical { get_response('UIDL %d', num) })
        res.split(/ /)[1]
      else
        critical {
            getok('UIDL')
            table = {}
            @socket.each_list_item do |line|
              num, uid = line.split
              table[num.to_i] = uid
            end
            table
        }
      end
    end

    def quit
      check_response(critical { get_response('QUIT') })
    end

    private

    def getok( *reqs )
      @socket.writeline sprintf(*reqs)
      check_response(recv_response())
    end

    def get_response( *reqs )
      @socket.writeline sprintf(*reqs)
      recv_response()
    end

    def recv_response
      @socket.readline
    end

    def check_response( res )
      raise POPError, res unless /\A\+OK/i === res
      res
    end

    def check_response_auth( res )
      raise POPAuthenticationError, res unless /\A\+OK/i === res
      res
    end

    def critical
      return if @in_critical_block
      # Do not use ensure-block.
      @in_critical_block = true
      result = yield
      @in_critical_block = false
      result
    end

  end

end   # module Net

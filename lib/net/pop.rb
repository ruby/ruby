=begin

= net/pop.rb version 1.1.34

written by Minero Aoki <aamine@dp.u-netsurf.ne.jp>

This program is free software.
You can distribute/modify this program under
the terms of the Ruby Distribute License.

Japanese version of this document is in "net" full package.
You can get it from RAA
(Ruby Application Archive: http://www.ruby-lang.org/en/raa.html).


== Net::POP3

=== Super Class

Net::Protocol

=== Class Methods

: new( address = 'localhost', port = 110 )
  creates a new Net::POP3 object.
  This method does not open TCP connection yet.

: start( address = 'localhost', port = 110, account, password )
: start( address = 'localhost', port = 110, account, password ) {|pop| .... }
  equals to Net::POP3.new( address, port ).start( account, password )

    # typical usage
    Net::POP3.start( addr, port, acnt, pass ) do |pop|
      pop.each_mail do |m|
        any_file.write m.pop
        m.delete
      end
    end

: foreach( address = 'localhost', port = 110, account, password ) {|mail| .... }
  starts protocol and iterate for each POPMail object.
  This method equals to

    Net::POP3.start( address, port, account, password ) do |pop|
      pop.each do |m|
        yield m
      end
    end

  .

    # typical usage
    Net::POP3.foreach( addr, nil, acnt, pass ) do |m|
      m.pop file
      m.delete
    end

: delete_all( address = 'localhost', port = 110, account, password )
: delete_all( address = 'localhost', port = 110, account, password ) {|mail| .... }
  starts POP3 session and delete all mails.
  If block is given, iterates for each POPMail object before delete.

    # typical usage
    Net::POP3.delete_all( addr, nil, acnt, pass ) do |m|
      m.pop file
    end
  
=== Methods

: start( account, password )
: start( account, password ) {|pop| .... }
  starts POP3 session.

  When called with block, gives a POP3 object to block and
  closes the session after block call finish.

: mails
  an array of ((URL:#POPMail)).
  This array is renewed when session started.

: each_mail {|popmail| .... }
: each {|popmail| .... }
  is equals to "pop3.mails.each"

: delete_all
: delete_all {|popmail| .... }
  deletes all mails.
  If called with block, gives mails to the block before deleting.

    # example 1
    # pop and delete all mails
    n = 1
    pop.delete_all do |m|
      File.open("inbox/#{n}") {|f| f.write m.pop }
      n += 1
    end

    # example 2
    # clear all mails on server
    Net::POP3.start( addr, port, acc, pass ) do |pop|
      pop.delete_all
    end

: reset
  reset the session. All "deleted mark" are removed.


== Net::APOP

This class defines no new methods.
Only difference from POP3 is using APOP authentification.

=== Super Class

Net::POP3


== Net::POPMail

A class of mail which exists on POP server.

=== Super Class

Object


=== Methods

: pop( dest = '' )
  This method fetches a mail and write to 'dest' using '<<' method.

    # usage example

    mailarr = []
    POP3.start( 'localhost', 110 ) do |pop|
      pop.each_mail do |popm|
        mailarr.push popm.pop   # all() returns 'dest' (this time, string)
        # or, you can also
        # popm.pop( $stdout )   # write mail to stdout

        # maybe you also want to delete mail after popping
        popm.delete
      end
    end

: pop {|str| .... }
  If pop() is called with block, it gives the block part strings of a mail.

    # usage example

    POP3.start( 'localhost', 110 ) do |pop3|
      pop3.each_mail do |m|
        m.pop do |str|
          # do anything
        end
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

require 'net/protocol'
require 'md5'


module Net

  class POP3 < Protocol

    protocol_param :port,         '110'
    protocol_param :command_type, '::Net::NetPrivate::POP3Command'
    protocol_param :apop_command_type, '::Net::NetPrivate::APOPCommand'

    protocol_param :mail_type,    '::Net::POPMail'

    class << self

      def foreach( address = nil, port = nil,
                   account = nil, password = nil, &block )
        start( address, port, account, password ) do |pop|
          pop.each_mail( &block )
        end
      end

      def delete_all( address = nil, port = nil,
                      account = nil, password = nil, &block )
        start( address, port, account, password ) do |pop|
          pop.delete_all( &block )
        end
      end
    
    end


    def initialize( addr = nil, port = nil, apop = false )
      super addr, port
      @mails = nil
      @apop = false
    end

    attr :mails

    def each_mail( &block )
      io_check
      @mails.each( &block )
    end

    alias each each_mail

    def delete_all
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

    def do_start( acnt, pwd )
      @command.auth( acnt, pwd )

      @mails = []
      mtype = type.mail_type
      @command.list.each_with_index do |size,idx|
        if size then
          @mails.push mtype.new( idx, size, @command )
        end
      end
      @mails.freeze
    end

    def io_check
      if not @socket or @socket.closed? then
        raise IOError, 'pop session is not opened yet'
      end
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

    def all( dest = '' )
      if block_given? then
        dest = NetPrivate::ReadAdapter.new( Proc.new )
      end
      @command.retr( @num, dest )
    end
    alias pop all
    alias mail all

    def top( lines, dest = '' )
      @command.top( @num, lines, dest )
    end

    def header( dest = '' )
      top 0, dest
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



  module NetPrivate


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


  end   # module Net::NetPrivate

end   # module Net

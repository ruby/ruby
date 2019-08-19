# frozen_string_literal: true
require 'net/pop'
require 'test/unit'
require 'digest/md5'

class TestPOP < Test::Unit::TestCase
  def setup
    @users = {'user' => 'pass' }
    @ok_user = 'user'
    @stamp_base = "#{$$}.#{Time.now.to_i}@localhost"
  end

  def test_pop_auth_ok
    pop_test(false) do |pop|
      assert_instance_of Net::POP3, pop
      assert_nothing_raised do
        pop.start(@ok_user, @users[@ok_user])
      end
    end
  end

  def test_pop_auth_ng
    pop_test(false) do |pop|
      assert_instance_of Net::POP3, pop
      assert_raise Net::POPAuthenticationError do
        pop.start(@ok_user, 'bad password')
      end
    end
  end

  def test_apop_ok
    pop_test(@stamp_base) do |pop|
      assert_instance_of Net::APOP, pop
      assert_nothing_raised do
        pop.start(@ok_user, @users[@ok_user])
      end
    end
  end

  def test_apop_ng
    pop_test(@stamp_base) do |pop|
      assert_instance_of Net::APOP, pop
      assert_raise Net::POPAuthenticationError do
        pop.start(@ok_user, 'bad password')
      end
    end
  end

  def test_apop_invalid
    pop_test("\x80"+@stamp_base) do |pop|
      assert_instance_of Net::APOP, pop
      assert_raise Net::POPAuthenticationError do
        pop.start(@ok_user, @users[@ok_user])
      end
    end
  end

  def test_apop_invalid_at
    pop_test(@stamp_base.sub('@', '.')) do |pop|
      assert_instance_of Net::APOP, pop
      assert_raise Net::POPAuthenticationError do
        pop.start(@ok_user, @users[@ok_user])
      end
    end
  end

  def test_popmail
    # totally not representative of real messages, but
    # enough to test frozen bugs
    lines = [ "[ruby-core:85210]" , "[Bug #14416]" ].freeze
    command = Object.new
    command.instance_variable_set(:@lines, lines)

    def command.retr(n)
      @lines.each { |l| yield "#{l}\r\n" }
    end

    def command.top(number, nl)
      @lines.each do |l|
        yield "#{l}\r\n"
        break if (nl -= 1) <= 0
      end
    end

    net_pop = :unused
    popmail = Net::POPMail.new(1, 123, net_pop, command)
    res = popmail.pop
    assert_equal "[ruby-core:85210]\r\n[Bug #14416]\r\n", res
    assert_not_predicate res, :frozen?

    res = popmail.top(1)
    assert_equal "[ruby-core:85210]\r\n", res
    assert_not_predicate res, :frozen?
  end

  def pop_test(apop=false)
    host = 'localhost'
    server = TCPServer.new(host, 0)
    port = server.addr[1]
    server_thread = Thread.start do
      sock = server.accept
      begin
        pop_server_loop(sock, apop)
      ensure
        sock.close
      end
    end
    client_thread = Thread.start do
      begin
        begin
          pop = Net::POP3::APOP(apop).new(host, port)
          #pop.set_debug_output $stderr
          yield pop
        ensure
          begin
            pop.finish
          rescue IOError
            raise unless $!.message == "POP session not yet started"
          end
        end
      ensure
        server.close
      end
    end
    assert_join_threads([client_thread, server_thread])
  end

  def pop_server_loop(sock, apop)
    if apop
      sock.print "+OK ready <#{apop}>\r\n"
    else
      sock.print "+OK ready\r\n"
    end
    user = nil
    while line = sock.gets
      case line
      when /^USER (.+)\r\n/
        user = $1
        if @users.key?(user)
          sock.print "+OK\r\n"
        else
          sock.print "-ERR unknown user\r\n"
        end
      when /^PASS (.+)\r\n/
        if @users[user] == $1
          sock.print "+OK\r\n"
        else
          sock.print "-ERR invalid password\r\n"
        end
      when /^APOP (.+) (.+)\r\n/
        user = $1
        if apop && Digest::MD5.hexdigest("<#{apop}>#{@users[user]}") == $2
          sock.print "+OK\r\n"
        else
          sock.print "-ERR authentication failed\r\n"
        end
      when /^QUIT/
        sock.print "+OK bye\r\n"
        return
      else
        sock.print "-ERR command not recognized\r\n"
        return
      end
    end
  end
end

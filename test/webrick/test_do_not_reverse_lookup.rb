require "test/unit"
require "webrick"
require_relative "utils"

class TestDoNotReverseLookup < Test::Unit::TestCase
  class DNRL < WEBrick::GenericServer
    def run(sock)
      sock << sock.do_not_reverse_lookup.to_s
    end
  end

  # +--------------------------------------------------------------------------+
  # |        Expected interaction between Socket.do_not_reverse_lookup         |
  # |            and WEBrick::Config::General[:DoNotReverseLookup]             |
  # +----------------------------+---------------------------------------------+
  # |                            |WEBrick::Config::General[:DoNotReverseLookup]|
  # +----------------------------+--------------+---------------+--------------+
  # |Socket.do_not_reverse_lookup|     TRUE     |     FALSE     |     NIL      |
  # +----------------------------+--------------+---------------+--------------+
  # |            TRUE            |     true     |     false     |     true     |
  # +----------------------------+--------------+---------------+--------------+
  # |            FALSE           |     true     |     false     |     false    |
  # +----------------------------+--------------+---------------+--------------+

  def test_socket_dnrl_true_server_dnrl_true
    Socket.do_not_reverse_lookup = true
    config = {:DoNotReverseLookup => true}
    TestWEBrick.start_server(DNRL, config) do |server, addr, port, log|
      TCPSocket.open(addr, port) do |sock|
        assert_equal('true', sock.gets, log.call)
      end
    end
  end

  def test_socket_dnrl_true_server_dnrl_false
    Socket.do_not_reverse_lookup = true
    config = {:DoNotReverseLookup => false}
    TestWEBrick.start_server(DNRL, config) do |server, addr, port, log|
      TCPSocket.open(addr, port) do |sock|
        assert_equal('false', sock.gets, log.call)
      end
    end
  end

  def test_socket_dnrl_true_server_dnrl_nil
    Socket.do_not_reverse_lookup = true
    config = {:DoNotReverseLookup => nil}
    TestWEBrick.start_server(DNRL, config) do |server, addr, port, log|
      TCPSocket.open(addr, port) do |sock|
        assert_equal('true', sock.gets, log.call)
      end
    end
  end

  def test_socket_dnrl_false_server_dnrl_true
    Socket.do_not_reverse_lookup = false
    config = {:DoNotReverseLookup => true}
    TestWEBrick.start_server(DNRL, config) do |server, addr, port, log|
      TCPSocket.open(addr, port) do |sock|
        assert_equal('true', sock.gets, log.call)
      end
    end
  end

  def test_socket_dnrl_false_server_dnrl_false
    Socket.do_not_reverse_lookup = false
    config = {:DoNotReverseLookup => false}
    TestWEBrick.start_server(DNRL, config) do |server, addr, port, log|
      TCPSocket.open(addr, port) do |sock|
        assert_equal('false', sock.gets, log.call)
      end
    end
  end

  def test_socket_dnrl_false_server_dnrl_nil
    Socket.do_not_reverse_lookup = false
    config = {:DoNotReverseLookup => nil}
    TestWEBrick.start_server(DNRL, config) do |server, addr, port, log|
      TCPSocket.open(addr, port) do |sock|
        assert_equal('false', sock.gets, log.call)
      end
    end
  end
end

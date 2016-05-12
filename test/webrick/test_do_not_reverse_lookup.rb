# frozen_string_literal: false
require "test/unit"
require "webrick"
require_relative "utils"

class TestDoNotReverseLookup < Test::Unit::TestCase
  class DNRL < WEBrick::GenericServer
    def run(sock)
      sock << sock.do_not_reverse_lookup.to_s
    end
  end

  @@original_do_not_reverse_lookup_value = Socket.do_not_reverse_lookup

  def teardown
    Socket.do_not_reverse_lookup = @@original_do_not_reverse_lookup_value
  end

  def do_not_reverse_lookup?(config)
    result = nil
    TestWEBrick.start_server(DNRL, config) do |server, addr, port, log|
      TCPSocket.open(addr, port) do |sock|
        result = {'true' => true, 'false' => false}[sock.gets]
      end
    end
    result
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
    assert_equal(true, do_not_reverse_lookup?(:DoNotReverseLookup => true))
  end

  def test_socket_dnrl_true_server_dnrl_false
    Socket.do_not_reverse_lookup = true
    assert_equal(false, do_not_reverse_lookup?(:DoNotReverseLookup => false))
  end

  def test_socket_dnrl_true_server_dnrl_nil
    Socket.do_not_reverse_lookup = true
    assert_equal(true, do_not_reverse_lookup?(:DoNotReverseLookup => nil))
  end

  def test_socket_dnrl_false_server_dnrl_true
    Socket.do_not_reverse_lookup = false
    assert_equal(true, do_not_reverse_lookup?(:DoNotReverseLookup => true))
  end

  def test_socket_dnrl_false_server_dnrl_false
    Socket.do_not_reverse_lookup = false
    assert_equal(false, do_not_reverse_lookup?(:DoNotReverseLookup => false))
  end

  def test_socket_dnrl_false_server_dnrl_nil
    Socket.do_not_reverse_lookup = false
    assert_equal(false, do_not_reverse_lookup?(:DoNotReverseLookup => nil))
  end
end

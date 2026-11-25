# frozen_string_literal: true

require_relative "helper"
require "stringio"

class TestGemCoreExtTCPSocketInit < Gem::TestCase
  class FakeSocket
    attr_reader :arguments

    def initialize(host, serv, local_host = nil, local_port = nil, open_timeout: nil)
      @arguments = [host, serv, local_host, local_port, open_timeout]
    end
  end

  def setup
    super
    load_initializer
    FakeSocket.prepend CoreExtensions::TCPSocketExt::Initializer
  end

  def test_initialize_forwards_socket_arguments
    with_resolved_address("2001:db8::1") do
      socket = FakeSocket.new("example.test", 443, "::", 1234)
      assert_equal ["2001:db8::1", 443, "::", 1234, nil], socket.arguments

      socket = FakeSocket.new("example.test", 443, "::", 1234, open_timeout: 7)
      assert_equal ["2001:db8::1", 443, "::", 1234, 7], socket.arguments
    end
  end

  private

  # The file prepends itself to TCPSocket when required, so load it against a stand-in.
  def load_initializer
    return if defined?(CoreExtensions::TCPSocketExt::Initializer)

    tcp_socket = Object.send(:remove_const, :TCPSocket)
    Object.const_set(:TCPSocket, Class.new)
    begin
      require "rubygems/core_ext/tcpsocket_init"
    ensure
      Object.send(:remove_const, :TCPSocket)
      Object.const_set(:TCPSocket, tcp_socket)
    end
  end

  def with_resolved_address(ip_address)
    addrinfo = Struct.new(:ip_address, :ipv4?).new(ip_address, false)

    Addrinfo.stub(:foreach, ->(*, &block) { block.call(addrinfo) }) do
      Socket.stub(:tcp, ->(*) { StringIO.new }) do
        yield
      end
    end
  end
end

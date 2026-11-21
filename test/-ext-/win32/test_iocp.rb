# frozen_string_literal: false
if /mswin|mingw/ =~ RUBY_PLATFORM
  require '-test-/win32/iocp'
  require 'socket'
  require 'test/unit'

  class Test_Win32IOCP < Test::Unit::TestCase
    # A blocking read or write must not leave a completion packet on a
    # port the handle is associated with: the OVERLAPPED that packet
    # points at lives on the stack of the call that already returned.
    def assert_no_stray_completion(*ios)
      port = Bug::Win32::IOCP.new
      ios.each {|io| port.associate(io)}
      yield
      assert_nil(port.poll(100), "completion packet queued by a blocking I/O")
    end

    def with_tcp_pair
      TCPServer.open("127.0.0.1", 0) do |server|
        TCPSocket.open("127.0.0.1", server.addr[1]) do |client|
          accepted = server.accept
          begin
            yield accepted, client
          ensure
            accepted.close
          end
        end
      end
    end

    def test_pipe
      IO.pipe do |r, w|
        assert_no_stray_completion(r, w) do
          w.write("x")
          assert_equal("x", r.read(1))
        end
      end
    end

    def test_socket
      with_tcp_pair do |s, c|
        assert_no_stray_completion(s, c) do
          c.write("x")
          assert_equal("x", s.read(1))
        end
      end
    end

    def test_socket_msg
      UDPSocket.open do |s|
        UDPSocket.open do |c|
          s.bind("127.0.0.1", 0)
          c.connect("127.0.0.1", s.addr[1])
          assert_no_stray_completion(s, c) do
            c.sendmsg("x")
            assert_equal("x", s.recvmsg[0])
          end
        end
      end
    end
  end
end

require "test/unit"
require "tempfile"
require "webrick"
require File.join(File.dirname(__FILE__), "utils.rb")

class TestWEBrickServer < Test::Unit::TestCase
  class Echo < WEBrick::GenericServer
    def run(sock)
      while line = sock.gets
        sock << line
      end
    end
  end

  def test_server
    TestWEBrick.start_server(Echo){|server, addr, port|
      TCPSocket.open(addr, port){|sock|
        sock.puts("foo"); assert_equal("foo\n", sock.gets)
        sock.puts("bar"); assert_equal("bar\n", sock.gets)
        sock.puts("baz"); assert_equal("baz\n", sock.gets)
        sock.puts("qux"); assert_equal("qux\n", sock.gets)
      }
    }
  end

  def test_callbacks
    accepted = started = stopped = 0
    config = {
      :AcceptCallback => Proc.new{ accepted += 1 },
      :StartCallback => Proc.new{ started += 1 },
      :StopCallback => Proc.new{ stopped += 1 },
    }
    TestWEBrick.start_server(Echo, config){|server, addr, port|
      true while server.status != :Running
      assert_equal(started, 1)
      assert_equal(stopped, 0)
      assert_equal(accepted, 0)
      TCPSocket.open(addr, port){|sock| (sock << "foo\n").gets }
      TCPSocket.open(addr, port){|sock| (sock << "foo\n").gets }
      TCPSocket.open(addr, port){|sock| (sock << "foo\n").gets }
      assert_equal(accepted, 3)
    }
    assert_equal(started, 1)
    assert_equal(stopped, 1)
  end

  def test_daemon
    begin
      r, w = IO.pipe
      pid1 = Process.fork{
        r.close
        WEBrick::Daemon.start
        w.puts(Process.pid)
        sleep 10
      }
      pid2 = r.gets.to_i
      assert(Process.kill(:KILL, pid2))
      assert_not_equal(pid1, pid2)
    rescue NotImplementedError
      # snip this test
    ensure
      Process.wait(pid1) if pid1
      r.close
      w.close
    end
  end
end

# frozen_string_literal: false
require "test/unit"
require "tempfile"
require "webrick"
require_relative "utils"

class TestWEBrickServer < Test::Unit::TestCase
  class Echo < WEBrick::GenericServer
    def run(sock)
      while line = sock.gets
        sock << line
      end
    end
  end

  def test_server
    TestWEBrick.start_server(Echo){|server, addr, port, log|
      TCPSocket.open(addr, port){|sock|
        sock.puts("foo"); assert_equal("foo\n", sock.gets, log.call)
        sock.puts("bar"); assert_equal("bar\n", sock.gets, log.call)
        sock.puts("baz"); assert_equal("baz\n", sock.gets, log.call)
        sock.puts("qux"); assert_equal("qux\n", sock.gets, log.call)
      }
    }
  end

  def test_start_exception
    stopped = 0

    log = []
    logger = WEBrick::Log.new(log, WEBrick::BasicLog::WARN)

    assert_raise(SignalException) do
      listener = Object.new
      def listener.to_io # IO.select invokes #to_io.
        raise SignalException, 'SIGTERM' # simulate signal in main thread
      end
      def listener.shutdown
      end
      def listener.close
      end

      server = WEBrick::HTTPServer.new({
        :BindAddress => "127.0.0.1", :Port => 0,
        :StopCallback => Proc.new{ stopped += 1 },
        :Logger => logger,
      })
      server.listeners[0].close
      server.listeners[0] = listener

      server.start
    end

    assert_equal(1, stopped)
    assert_equal(1, log.length)
    assert_match(/FATAL SignalException: SIGTERM/, log[0])
  end

  def test_callbacks
    accepted = started = stopped = 0
    config = {
      :AcceptCallback => Proc.new{ accepted += 1 },
      :StartCallback => Proc.new{ started += 1 },
      :StopCallback => Proc.new{ stopped += 1 },
    }
    TestWEBrick.start_server(Echo, config){|server, addr, port, log|
      true while server.status != :Running
      sleep 1 if defined?(RubyVM::MJIT) && RubyVM::MJIT.enabled? # server.status behaves unexpectedly with --jit-wait
      assert_equal(1, started, log.call)
      assert_equal(0, stopped, log.call)
      assert_equal(0, accepted, log.call)
      TCPSocket.open(addr, port){|sock| (sock << "foo\n").gets }
      TCPSocket.open(addr, port){|sock| (sock << "foo\n").gets }
      TCPSocket.open(addr, port){|sock| (sock << "foo\n").gets }
      assert_equal(3, accepted, log.call)
    }
    assert_equal(1, started)
    assert_equal(1, stopped)
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

  def test_restart_after_shutdown
    address = '127.0.0.1'
    port = 0
    log = []
    config = {
      :BindAddress => address,
      :Port => port,
      :Logger => WEBrick::Log.new(log, WEBrick::BasicLog::WARN),
    }
    server = Echo.new(config)
    client_proc = lambda {|str|
      begin
        ret = server.listeners.first.connect_address.connect {|s|
          s.write(str)
          s.close_write
          s.read
        }
        assert_equal(str, ret)
      ensure
        server.shutdown
      end
    }
    server_thread = Thread.new { server.start }
    client_thread = Thread.new { client_proc.call("a") }
    assert_join_threads([client_thread, server_thread])
    server.listen(address, port)
    server_thread = Thread.new { server.start }
    client_thread = Thread.new { client_proc.call("b") }
    assert_join_threads([client_thread, server_thread])
    assert_equal([], log)
  end

  def test_restart_after_stop
    log = Object.new
    class << log
      include Test::Unit::Assertions
      def <<(msg)
        flunk "unexpected log: #{msg.inspect}"
      end
    end
    client_thread = nil
    wakeup = -> {client_thread.wakeup}
    warn_flunk = WEBrick::Log.new(log, WEBrick::BasicLog::WARN)
    server = WEBrick::HTTPServer.new(
      :StartCallback => wakeup,
      :StopCallback => wakeup,
      :BindAddress => '0.0.0.0',
      :Port => 0,
      :Logger => warn_flunk)
    2.times {
      server_thread = Thread.start {
        server.start
      }
      client_thread = Thread.start {
        sleep 0.1 until server.status == :Running || !server_thread.status
        server.stop
        sleep 0.1 until server.status == :Stop || !server_thread.status
      }
      assert_join_threads([client_thread, server_thread])
    }
  end

  def test_port_numbers
    config = {
      :BindAddress => '0.0.0.0',
      :Logger => WEBrick::Log.new([], WEBrick::BasicLog::WARN),
    }

    ports = [0, "0"]

    ports.each do |port|
      config[:Port]= port
      server = WEBrick::GenericServer.new(config)
      server_thread = Thread.start { server.start }
      client_thread = Thread.start {
        sleep 0.1 until server.status == :Running || !server_thread.status
        server_port = server.listeners[0].addr[1]
        server.stop
        assert_equal server.config[:Port], server_port
        sleep 0.1 until server.status == :Stop || !server_thread.status
      }
      assert_join_threads([client_thread, server_thread])
    end

    assert_raise(ArgumentError) do
      config[:Port]= "FOO"
      WEBrick::GenericServer.new(config)
    end
  end
end

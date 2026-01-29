# frozen_string_literal: true
require 'test/unit'
require 'securerandom'
require 'fileutils'
require 'socket'
require_relative 'scheduler'

class TestFiberScheduler < Test::Unit::TestCase
  def test_fiber_without_scheduler
    # Cannot create fiber without scheduler.
    assert_raise RuntimeError do
      Fiber.schedule do
      end
    end
  end

  def test_fiber_new
    f = Fiber.new{}
    refute f.blocking?
  end

  def test_fiber_new_with_options
    f = Fiber.new(blocking: true){}
    assert f.blocking?

    f = Fiber.new(blocking: false){}
    refute f.blocking?

    f = Fiber.new(pool: nil){}
    refute f.blocking?
  end

  def test_fiber_blocking
    f = Fiber.new(blocking: false) do
      fiber = Fiber.current
      refute fiber.blocking?
      Fiber.blocking do |_fiber|
        assert_equal fiber, _fiber
        assert fiber.blocking?
      end
    end
    f.resume
  end

  def test_closed_at_thread_exit
    scheduler = Scheduler.new

    thread = Thread.new do
      Fiber.set_scheduler scheduler
    end

    thread.join

    assert scheduler.closed?
  end

  def test_closed_when_set_to_nil
    scheduler = Scheduler.new

    thread = Thread.new do
      Fiber.set_scheduler scheduler
      Fiber.set_scheduler nil

      assert scheduler.closed?
    end

    thread.join
  end

  def test_close_at_exit
    assert_in_out_err %W[-I#{__dir__} -], <<-RUBY, ['Running Fiber'], [], success: true
    require 'scheduler'
    Warning[:experimental] = false

    scheduler = Scheduler.new
    Fiber.set_scheduler scheduler

    Fiber.schedule do
      sleep(0)
      puts "Running Fiber"
    end
    RUBY
  end

  def test_minimal_interface
    scheduler = Object.new

    def scheduler.block
    end

    def scheduler.unblock
    end

    def scheduler.io_wait
    end

    def scheduler.kernel_sleep
    end

    def scheduler.fiber_interrupt(_fiber, _exception)
    end

    thread = Thread.new do
      Fiber.set_scheduler scheduler
    end

    thread.join
  end

  def test_current_scheduler
    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      assert Fiber.scheduler
      refute Fiber.current_scheduler

      Fiber.schedule do
        assert Fiber.current_scheduler
      end
    end

    thread.join
  end

  def test_autoload
    10.times do
      Object.autoload(:TestFiberSchedulerAutoload, File.expand_path("autoload.rb", __dir__))

      thread = Thread.new do
        scheduler = Scheduler.new
        Fiber.set_scheduler scheduler

        10.times do
          Fiber.schedule do
            Object.const_get(:TestFiberSchedulerAutoload)
          end
        end
      end

      thread.join
    ensure
      $LOADED_FEATURES.delete(File.expand_path("autoload.rb", __dir__))
      Object.send(:remove_const, :TestFiberSchedulerAutoload)
    end
  end

  def test_iseq_compile_under_gc_stress_bug_21180
    Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        EnvUtil.under_gc_stress do
          RubyVM::InstructionSequence.compile_file(File::NULL)
        end
      end
    end.join
  end

  def test_deadlock
    mutex = Thread::Mutex.new
    condition = Thread::ConditionVariable.new
    q = 0.0001

    signaller = Thread.new do
      loop do
        mutex.synchronize do
          condition.signal
        end
        sleep q
      end
    end

    i = 0

    thread = Thread.new do
      scheduler = SleepingBlockingScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        10.times do
          mutex.synchronize do
            condition.wait(mutex)
            sleep q
            i += 1
          end
        end
      end
    end

    # Wait for 10 seconds at most... if it doesn't finish, it's deadlocked.
    thread.join(10)

    # If it's deadlocked, it will never finish, so this will be 0.
    assert_equal 10, i
  ensure
    # Make sure the threads are dead...
    thread.kill
    signaller.kill
    thread.join
    signaller.join
  end

  def test_condition_variable
    condition_variable = ::Thread::ConditionVariable.new
    mutex = ::Thread::Mutex.new

    error = nil

    thread = Thread.new do
      Thread.current.report_on_exception = false

      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      fiber = Fiber.schedule do
        begin
          mutex.synchronize do
            condition_variable.wait(mutex)
          end
        rescue => error
        end
      end

      fiber.raise(RuntimeError)
    end

    thread.join
    assert_kind_of RuntimeError, error
  end

  def test_post_fork_scheduler_reset
    omit 'fork not supported' unless Process.respond_to?(:fork)

    forked_scheduler_state = nil
    thread = Thread.new do
      r, w = IO.pipe
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      forked_pid = fork do
        r.close
        w << (Fiber.scheduler ? 'set' : 'reset')
        w.close
      end
      w.close
      forked_scheduler_state = r.read
      Process.wait(forked_pid)
    ensure
      r.close rescue nil
      w.close rescue nil
    end
    thread.join
    assert_equal 'reset', forked_scheduler_state
  ensure
    thread.kill rescue nil
  end

  def test_post_fork_fiber_blocking
    omit 'fork not supported' unless Process.respond_to?(:fork)

    fiber_blocking_state = nil
    thread = Thread.new do
      r, w = IO.pipe
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      forked_pid = nil
      Fiber.schedule do
        forked_pid = fork do
          r.close
          w << (Fiber.current.blocking? ? 'blocking' : 'nonblocking')
          w.close
        end
      end
      w.close
      fiber_blocking_state = r.read
      Process.wait(forked_pid)
    ensure
      r.close rescue nil
      w.close rescue nil
    end
    thread.join
    assert_equal 'blocking', fiber_blocking_state
  ensure
    thread.kill rescue nil
  end

  def test_io_write_on_flush
    begin
      path = File.join(Dir.tmpdir, "ruby_test_io_write_on_flush_#{SecureRandom.hex}")
      descriptor = nil
      operations = nil

      thread = Thread.new do
        scheduler = IOScheduler.new
        Fiber.set_scheduler scheduler

        Fiber.schedule do
          File.open(path, 'w+') do |file|
            descriptor = file.fileno
            file << 'foo'
            file.flush
            file << 'bar'
          end
        end

        operations = scheduler.operations
      end

      thread.join
      assert_equal [
        [:io_write, descriptor, 'foo'],
        [:io_write, descriptor, 'bar']
      ], operations

      assert_equal 'foobar', IO.read(path)
    ensure
      thread.kill rescue nil
      FileUtils.rm_f(path)
    end
  end

  def test_io_read_error
    path = File.join(Dir.tmpdir, "ruby_test_io_read_error_#{SecureRandom.hex}")
    error = nil

    thread = Thread.new do
      scheduler = IOErrorScheduler.new
      Fiber.set_scheduler scheduler
      Fiber.schedule do
        File.open(path, 'w+') { it.read }
      rescue => error
        # Ignore.
      end
    end

    thread.join
    assert_kind_of Errno::EBADF, error
  ensure
    thread.kill rescue nil
    FileUtils.rm_f(path)
  end

  def test_io_write_error
    path = File.join(Dir.tmpdir, "ruby_test_io_write_error_#{SecureRandom.hex}")
    error = nil

    thread = Thread.new do
      scheduler = IOErrorScheduler.new
      Fiber.set_scheduler scheduler
      Fiber.schedule do
        File.open(path, 'w+') { it.sync = true; it << 'foo' }
      rescue => error
        # Ignore.
      end
    end

    thread.join
    assert_kind_of Errno::EINVAL, error
  ensure
    thread.kill rescue nil
    FileUtils.rm_f(path)
  end

  def test_io_write_flush_error
    path = File.join(Dir.tmpdir, "ruby_test_io_write_flush_error_#{SecureRandom.hex}")
    error = nil

    thread = Thread.new do
      scheduler = IOErrorScheduler.new
      Fiber.set_scheduler scheduler
      Fiber.schedule do
        File.open(path, 'w+') { it << 'foo' }
      rescue => error
        # Ignore.
      end
    end

    thread.join
    assert_kind_of Errno::EINVAL, error
  ensure
    thread.kill rescue nil
    FileUtils.rm_f(path)
  end

  def test_socket_send
    s1, s2 = UNIXSocket.socketpair
    operations = nil

    thread = Thread.new do
      scheduler = SocketIOScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        s1.send('foo', 0)
        s1.send('bar', 0)
      end

      operations = scheduler.operations
    end

    thread.join
    assert_equal [
      [:socket_send, s1.fileno, nil, 'foo', 0, 0],
      [:socket_send, s1.fileno, nil, 'bar', 0, 0]
    ], operations

    assert_equal 'foobar', s2.recv(6)
  ensure
    thread.kill rescue nil
    s1.close rescue nil
    s2.close rescue nil
  end

  def test_socket_send_udp
    s1 = UDPSocket.new
    s2 = UDPSocket.new
    port = SecureRandom.rand(60001..65535)
    s2.bind('127.0.0.1', port)
    dest = Addrinfo.new(s2.addr)
    operations = nil

    thread = Thread.new do
      scheduler = SocketIOScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        s1.send('foo', 0, dest)
        s1.send('bar', 0, '127.0.0.1', port)
      end

      operations = scheduler.operations
    end

    thread.join
    assert_equal [
      [:socket_send, s1.fileno, dest.to_s, 'foo', 0, 0],
      [:socket_send, s1.fileno, dest.to_s, 'bar', 0, 0]
    ], operations

    assert_equal 'foo', s2.recv(6)
    assert_equal 'bar', s2.recv(6)
  ensure
    thread.kill rescue nil
    s1.close rescue nil
    s2.close rescue nil
  end

  def test_socket_send_error
    s1, s2 = UNIXSocket.socketpair
    error = nil

    thread = Thread.new do
      scheduler = IOErrorScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        s1.send('foo', 0)
      rescue => error
      end
    end

    thread.join
    assert_kind_of Errno::ENOTCONN, error
  ensure
    thread.kill rescue nil
    s1.close rescue nil
    s2.close rescue nil
  end

  def test_socket_recv
    s1, s2 = UNIXSocket.socketpair
    operations = nil

    s1.send('foobar', 0)
    s1.shutdown(:WR)
    received = []

    thread = Thread.new do
      scheduler = SocketIOScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        received << s2.recv(9)
      end

      operations = scheduler.operations
    end

    thread.join
    assert_equal [
      [:socket_recv, s2.fileno, 9, 0, false],
    ], operations

    assert_equal ['foobar'], received
  ensure
    thread.kill rescue nil
    s1.close rescue nil
    s2.close rescue nil
  end

  def test_socket_recv_udp
    s1 = UDPSocket.new
    port_src = SecureRandom.rand(60001..65534)
    s1.bind('127.0.0.1', port_src)

    s2 = UDPSocket.new
    port_dest = port_src + 1
    s2.bind('127.0.0.1', port_dest)

    src = Addrinfo.new(s1.addr)
    dest = Addrinfo.new(s2.addr)

    operations = nil

    s1.send('foobar', 0, dest)
    received = []

    thread = Thread.new do
      scheduler = SocketIOScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        received << s2.recvfrom(9)
      end

      operations = scheduler.operations
    end

    thread.join
    assert_equal [
      [:socket_recv, s2.fileno, 9, 0, true],
    ], operations

    assert_equal [['foobar', ["AF_INET", port_src, "127.0.0.1", "127.0.0.1"]]], received
  ensure
    thread.kill rescue nil
    s1.close rescue nil
    s2.close rescue nil
  end

  def test_socket_recv_error
    s1, s2 = UNIXSocket.socketpair
    error = nil

    s1.send('foobar', 0)
    s1.shutdown(:WR)
    received = []

    thread = Thread.new do
      scheduler = IOErrorScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        received << s2.recv(9)
      rescue => error
      end
    end

    thread.join
    assert_kind_of Errno::ENOTSOCK, error
  ensure
    thread.kill rescue nil
    s1.close rescue nil
    s2.close rescue nil
  end

  def test_socket_connect
    s1 = UDPSocket.new
    port = SecureRandom.rand(60001..65534)
    addr = Addrinfo.udp('127.0.0.1', port)

    operations = nil
    result = nil

    thread = Thread.new do
      scheduler = SocketIOScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        result = s1.connect('127.0.0.1', port)
      end

      operations = scheduler.operations
    end

    thread.join
    assert_equal [
      [:socket_connect, s1.fileno, addr.to_s],
    ], operations
    assert_equal 0, result
  ensure
    thread.kill rescue nil
    s1.close rescue nil
  end

  def test_socket_connect_error
    s1 = UDPSocket.new
    port = SecureRandom.rand(60001..65534)

    error = nil

    thread = Thread.new do
      scheduler = IOErrorScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        s1.connect('127.0.0.1', port)
      rescue => error
      end
    end

    thread.join
    assert_kind_of Errno::EBADF, error
  ensure
    thread.kill rescue nil
    s1.close rescue nil
  end

  def test_socket_accept
    server_port = SecureRandom.rand(60001..65534)
    server = Socket.new(:INET, :STREAM, 0)
    server.bind(Addrinfo.tcp('127.0.0.1', server_port))
    server.listen(5)

    client_port = server_port + 1
    client = Socket.new(:INET, :STREAM, 0)
    client_addr = Addrinfo.tcp('127.0.0.1', client_port)
    client.bind(client_addr)
    client.connect(server.connect_address)

    operations = nil
    conn = nil
    addr = nil

    thread = Thread.new do
      scheduler = SocketIOScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        conn, addr = server.accept
      end

      operations = scheduler.operations
    end

    thread.join
    assert_equal [
      [:socket_accept, server.fileno, client_addr.to_s]
    ], operations
    assert_kind_of Socket, conn
    assert_equal client_addr.to_s, addr.to_s
  ensure
    thread.kill rescue nil
    server.close rescue nil
    client&.close rescue nil
    conn&.close rescue nil
  end

  def test_socket_accept_tcpserver
    server_port = port = SecureRandom.rand(60001..65534)
    server = TCPServer.new('127.0.0.1', server_port)

    client_port = server_port + 1
    client = Socket.new(:INET, :STREAM, 0)
    client_addr = Addrinfo.tcp('127.0.0.1', client_port)
    client.bind(client_addr)
    client.connect(server.connect_address)

    operations = nil
    conn = nil

    thread = Thread.new do
      scheduler = SocketIOScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        conn = server.accept
      end

      operations = scheduler.operations
    end

    thread.join
    assert_equal [
      [:socket_accept, server.fileno, client_addr.to_s]
    ], operations
    assert_kind_of TCPSocket, conn
  ensure
    thread.kill rescue nil
    server.close rescue nil
    client&.close rescue nil
    conn&.close rescue nil
  end

  def test_socket_accept_error
    server = Socket.new(:INET, :STREAM, 0)

    error = nil

    thread = Thread.new do
      scheduler = IOErrorScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        server.accept
      rescue => error
      end
    end

    thread.join
    assert_kind_of Errno::ENOTSOCK, error
  ensure
    thread.kill rescue nil
    server.close rescue nil
  end
end

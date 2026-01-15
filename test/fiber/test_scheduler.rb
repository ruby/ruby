# frozen_string_literal: true
require 'test/unit'
require 'securerandom'
require 'fileutils'
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
end

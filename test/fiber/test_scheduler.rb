# frozen_string_literal: true
require 'test/unit'
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
end

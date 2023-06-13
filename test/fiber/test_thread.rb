# frozen_string_literal: true
require "test/unit"
require_relative 'scheduler'

class TestFiberThread < Test::Unit::TestCase
  def test_thread_join
    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      result = nil
      Fiber.schedule do
        result = Thread.new{:done}.value
      end

      scheduler.run
      result
    end

    assert_equal :done, thread.value
  end

  def test_thread_join_timeout
    sleeper = nil

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        sleeper = Thread.new{sleep}
        sleeper.join(0.1)
      end

      scheduler.run
    end

    thread.join

    assert_predicate sleeper, :alive?
  ensure
    sleeper&.kill
  end

  def test_thread_join_implicit
    sleeping = false
    finished = false

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        sleeping = true
        sleep(0.1)
        finished = true
      end

      :done
    end

    Thread.pass until sleeping

    thread.join

    assert_equal :done, thread.value
    assert finished, "Scheduler thread's task should be finished!"
  end

  def test_thread_join_blocking
    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      result = nil
      Fiber.schedule do
        Fiber.new(blocking: true) do
          # This can deadlock if the blocking state is not taken into account:
          Thread.new do
            sleep(0)
            result = :done
          end.join
        end.resume
      end

      scheduler.run
      result
    end

    assert_equal :done, thread.value
  end

  def test_broken_unblock
    thread = Thread.new do
      Thread.current.report_on_exception = false

      scheduler = BrokenUnblockScheduler.new

      Fiber.set_scheduler scheduler

      Fiber.schedule do
        Thread.new{
          Thread.current.report_on_exception = false
        }.join
      end

      scheduler.run
    ensure
      scheduler.close
    end

    assert_raise(RuntimeError) do
      thread.join
    end
  end

  def test_thread_join_hang
    thread = Thread.new do
      scheduler = SleepingUnblockScheduler.new

      Fiber.set_scheduler scheduler

      Fiber.schedule do
        Thread.new{sleep(0.01)}.value
      end
    end

    thread.join
  end
end

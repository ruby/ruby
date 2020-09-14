# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberScheduler < Test::Unit::TestCase
  def test_fiber_without_scheduler
    # Cannot create fiber without scheduler.
    assert_raise RuntimeError do
      Fiber do
      end
    end
  end

  def test_fiber_blocking
    scheduler = Scheduler.new

    thread = Thread.new do
      Thread.current.scheduler = scheduler

      # Close is always a blocking operation.
      IO.pipe.each(&:close)
    end

    thread.join

    assert_not_empty scheduler.blocking
    assert_match(/test_scheduler\.rb:\d+:in `close'/, scheduler.blocking.last)
  end
end

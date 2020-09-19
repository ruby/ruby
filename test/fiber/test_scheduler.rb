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
  
  def test_closed_at_thread_exit
    scheduler = Scheduler.new

    thread = Thread.new do
      Thread.current.scheduler = scheduler
    end

    thread.join

    assert scheduler.closed?
  end

  def test_closed_when_set_to_nil
    scheduler = Scheduler.new

    thread = Thread.new do
      Thread.current.scheduler = scheduler
      Thread.current.scheduler = nil

      assert scheduler.closed?
    end

    thread.join
  end
end

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

  def test_close_at_exit
    assert_in_out_err %W[-I#{__dir__} -], <<-RUBY, ['Running Fiber'], [], success: true
    require 'scheduler'

    scheduler = Scheduler.new
    Thread.current.scheduler = scheduler

    Fiber.schedule do
      sleep(0)
      puts "Running Fiber"
    end
    RUBY
  end

  def test_optional_close
    thread = Thread.new do
      Thread.current.scheduler = Object.new
    end

    thread.join
  end
end

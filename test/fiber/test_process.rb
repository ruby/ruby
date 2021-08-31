# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberProcess < Test::Unit::TestCase
  def test_process_wait
    Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        pid = Process.spawn("true")
        Process.wait(pid)

        # TODO test that scheduler was invoked.

        assert_predicate $?, :success?
      end
    end.join
  end

  def test_system
    Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        system("true")

        # TODO test that scheduler was invoked (currently it's not).

        assert_predicate $?, :success?
      end
    end.join
  end
end

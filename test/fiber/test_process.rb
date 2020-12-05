# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberProcess < Test::Unit::TestCase
  def test_system
    Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        system("true")
        assert_predicate $?, :success?
      end
    end.join
  end
end

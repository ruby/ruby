# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberProcess < Test::Unit::TestCase
  def test_system
    Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        system("sleep 1")
      end
    end.join
  end
end

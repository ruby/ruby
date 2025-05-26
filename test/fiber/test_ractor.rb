# frozen_string_literal: true
require "test/unit"
require "fiber"

class TestFiberCurrentRactor < Test::Unit::TestCase
  def setup
    omit unless defined? Ractor
  end

  def test_ractor_shareable
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      $VERBOSE = nil
      require "fiber"
      r = Ractor.new do
        Fiber.new do
          Fiber.current.class
        end.resume
      end
      assert_equal(Fiber, r.value)
    end;
  end
end

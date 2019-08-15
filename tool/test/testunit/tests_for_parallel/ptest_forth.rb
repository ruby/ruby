# frozen_string_literal: false
require 'test/unit'

class TestE < Test::Unit::TestCase
  class UnknownError < RuntimeError; end

  def test_not_fail
    assert_equal(1,1)
  end

  def test_always_skip
    skip "always"
  end

  def test_always_fail
    assert_equal(0,1)
  end

  def test_skip_after_unknown_error
    begin
      raise UnknownError, "unknown error"
    rescue
      skip "after raise"
    end
  end

  def test_unknown_error
    raise UnknownError, "unknown error"
  end
end

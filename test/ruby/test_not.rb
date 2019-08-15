# frozen_string_literal: false
require 'test/unit'

class TestNot < Test::Unit::TestCase
  def test_not_with_grouped_expression
    assert_equal(false, (not (true)))
    assert_equal(true, (not (false)))
  end

  def test_not_with_empty_grouped_expression
    assert_equal(true, (not ()))
  end
end

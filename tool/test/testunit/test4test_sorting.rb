# frozen_string_literal: false
$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../../lib"

require 'test/unit'

class TestForTestHideSkip < Test::Unit::TestCase
  def test_c
    omit "do nothing"
  end

  def test_b
    assert_equal true, false
  end

  def test_a
    raise
  end
end

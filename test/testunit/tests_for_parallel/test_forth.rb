require 'test/unit'
require_relative "misc.rb"

class TestE < TestCaseForParallelTest
  def ptest_not_fail
    assert_equal(1,1)
  end

  def ptest_always_skip
    skip "always"
  end

  def ptest_always_fail
    assert_equal(0,1)
  end
end


require 'test/unit'
require_relative "misc.rb"

class TestD < TestCaseForParallelTest
  def ptest_sleeping
    sleep 2
  end

  def ptest_fail_at_worker
    if MiniTest::Unit.output != STDOUT
      assert_equal(0,1)
    end
  end
end

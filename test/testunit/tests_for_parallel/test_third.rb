require 'test/unit'
require_relative "misc.rb"

class TestD < TestCaseForParallelTest
  def ptest_fail_at_worker
    if /test\/unit\/parallel\.rb/ =~ $0
      assert_equal(0,1)
    end
  end
end

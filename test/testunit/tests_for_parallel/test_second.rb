require 'test/unit'
require_relative "misc.rb"

class TestB < TestCaseForParallelTest
  def ptest_nothing
  end
end

class TestC < TestCaseForParallelTest
  def ptest_nothing
  end
end

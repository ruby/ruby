# -*- coding: us-ascii -*-
require 'test/unit'
require_relative '../ruby/envutil'

class TestRecursion < Test::Unit::TestCase
  require '-test-/recursion'

  def setup
    @obj = Struct.new(:visited).new(false)
    @obj.extend(Bug::Recursive)
  end

  def test_recursive
    def @obj.doit
      self.visited = true
      exec_recursive(:doit)
      raise "recursive"
    end
    assert_raise_with_message(RuntimeError, "recursive") {
      @obj.exec_recursive(:doit)
    }
    assert(@obj.visited, "obj.hash was not called")
  end

  def test_recursive_outer
    def @obj.doit
      self.visited = true
      exec_recursive_outer(:doit)
      raise "recursive_outer should short circuit intermediate calls"
    end
    assert_nothing_raised {
      @obj.exec_recursive_outer(:doit)
    }
    assert(@obj.visited, "obj.hash was not called")
  end
end

require 'test/unit'
require 'delegate'

class TestDelegateClass < Test::Unit::TestCase
  module M
    attr_reader :m
  end

  def test_extend
    obj = DelegateClass(Array).new([])
    obj.instance_eval { @m = :m }
    obj.extend M
    assert_equal(:m, obj.m, "[ruby-dev:33116]")
  end

  def test_systemcallerror_eq
    e = SystemCallError.new(0)
    assert((SimpleDelegator.new(e) == e) == (e == SimpleDelegator.new(e)), "[ruby-dev:34808]")
  end
end

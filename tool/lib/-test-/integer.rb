require 'test/unit'
require '-test-/integer.so'

module Test::Unit::Assertions
  def assert_fixnum(v, msg=nil)
    assert_instance_of(Integer, v, msg)
    assert_predicate(v, :fixnum?, msg)
  end

  def assert_bignum(v, msg=nil)
    assert_instance_of(Integer, v, msg)
    assert_predicate(v, :bignum?, msg)
  end
end

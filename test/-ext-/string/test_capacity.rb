# frozen_string_literal: true
require 'test/unit'
require '-test-/string'
require 'rbconfig/sizeof'

class Test_StringCapacity < Test::Unit::TestCase
  def test_capacity_embeded
    size = RbConfig::SIZEOF['void*'] * 3 - 1
    assert_equal size, Bug::String.capacity('foo')
  end

  def test_capacity_shared
    assert_equal 0, Bug::String.capacity(:abcdefghijklmnopqrstuvwxyz.to_s)
  end

  def test_capacity_normal
    assert_equal 128, Bug::String.capacity('1'*128)
  end
end

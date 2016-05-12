# frozen_string_literal: true
require 'test/unit'
require '-test-/string'
require 'rbconfig/sizeof'

class Test_StringCapacity < Test::Unit::TestCase
  def capa(str)
    Bug::String.capacity(str)
  end

  def test_capacity_embeded
    size = RbConfig::SIZEOF['void*'] * 3 - 1
    assert_equal size, capa('foo')
  end

  def test_capacity_shared
    assert_equal 0, capa(:abcdefghijklmnopqrstuvwxyz.to_s)
  end

  def test_capacity_normal
    assert_equal 128, capa('1'*128)
  end

  def test_s_new_capacity
    assert_equal("", String.new(capacity: 1000))
    assert_equal(String, String.new(capacity: 1000).class)
    assert_equal(10000, capa(String.new(capacity: 10000)))

    assert_equal("", String.new(capacity: -1000))
    assert_equal(capa(String.new(capacity: -10000)), capa(String.new(capacity: -1000)))
  end
end

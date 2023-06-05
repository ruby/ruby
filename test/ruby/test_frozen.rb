# frozen_string_literal: false
require 'test/unit'

class TestFrozen < Test::Unit::TestCase
  def test_setting_ivar_on_frozen_obj
    obj = Object.new
    obj.freeze
    assert_raise(FrozenError) { obj.instance_variable_set(:@a, 1) }
  end

  def test_setting_ivar_on_frozen_obj_with_ivars
    obj = Object.new
    obj.instance_variable_set(:@a, 1)
    obj.freeze
    assert_raise(FrozenError) { obj.instance_variable_set(:@b, 1) }
  end

  def test_setting_ivar_on_frozen_string
    str = "str"
    str.freeze
    assert_raise(FrozenError) { str.instance_variable_set(:@a, 1) }
  end

  def test_setting_ivar_on_frozen_string_with_ivars
    str = "str"
    str.instance_variable_set(:@a, 1)
    str.freeze
    assert_raise(FrozenError) { str.instance_variable_set(:@b, 1) }
  end
end

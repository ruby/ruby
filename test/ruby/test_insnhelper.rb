require 'test/unit'

class TestInsnHelper < Test::Unit::TestCase
  InsnHelper = RubyVM::InstructionHelper

  def test_method_serial_returns_fixnum
    assert_kind_of Fixnum, InsnHelper.method_serial
  end

  def test_constant_serial_returns_fixnum
    assert_kind_of Fixnum, InsnHelper.constant_serial
  end
end

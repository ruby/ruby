require 'test/unit'

class TestRubyVM < Test::Unit::TestCase

  def test_method_serial_returns_fixnum
    assert_kind_of Fixnum, RubyVM.method_serial
  end

  def test_constant_serial_returns_fixnum
    assert_kind_of Fixnum, RubyVM.constant_serial
  end
end

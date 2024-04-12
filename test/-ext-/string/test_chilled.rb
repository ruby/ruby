require 'test/unit'
require '-test-/string'

class Test_String_ChilledString < Test::Unit::TestCase
  def test_rb_str_chilled_p
    str = ""
    assert_equal true, Bug::String.rb_str_chilled_p(str)
  end

  def test_rb_str_chilled_p_frozen
    str = "".freeze
    assert_equal false, Bug::String.rb_str_chilled_p(str)
  end

  def test_rb_str_chilled_p_mutable
    str = "".dup
    assert_equal false, Bug::String.rb_str_chilled_p(str)
  end
end

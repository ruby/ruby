require 'test/unit'
require '-test-/string'

class Test_RbInternedStr < Test::Unit::TestCase
  def test_interned_str
    src = "a" * 20
    interned_str = Bug::String.rb_interned_str_dup(src)
    src.clear
    src << "b" * 20
    assert_equal "a" * 20, interned_str
  end
end

require 'test/unit'
require '-test-/string'

class Test_RbStrDup < Test::Unit::TestCase
  def test_nested_shared_non_frozen
    str = Bug::String.rb_str_dup(Bug::String.rb_str_dup("a" * 50))
    assert_send([Bug::String, :shared_string?, str])
    assert_not_send([Bug::String, :sharing_with_shared?, str], '[Bug #15792]')
  end

  def test_nested_shared_frozen
    str = Bug::String.rb_str_dup(Bug::String.rb_str_dup("a" * 50).freeze)
    assert_send([Bug::String, :shared_string?, str])
    assert_not_send([Bug::String, :sharing_with_shared?, str], '[Bug #15792]')
  end
end

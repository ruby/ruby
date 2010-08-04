require 'test/unit'
require '-test-/bug-3652/bug'

class Test_BUG_3652 < Test::Unit::TestCase
  def test_block_call_id
    bug3652 = '[ruby-core:31615]'
    s = "123456789012345678901234"
    assert_equal(s, Bug.str_resize(127, s), bug3652)
    s = "123456789"
    assert_equal(s, Bug.str_resize(127, s), bug3652)
  end
end

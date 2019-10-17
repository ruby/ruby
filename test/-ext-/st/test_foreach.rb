# frozen_string_literal: false
require 'test/unit'
require '-test-/st/foreach'

class Test_StForeachUnpack < Test::Unit::TestCase
  def test_st_foreach_check_unpack
    assert_nil Bug.unp_st_foreach_check(:check), "goto unpacked_continue"
    assert_nil Bug.unp_st_foreach_check(:delete1), "goto unpacked"
    assert_nil Bug.unp_st_foreach_check(:delete2), "goto deleted"
  end

  def test_st_foreach_unpack
    assert_nil Bug.unp_st_foreach(:unpacked), "goto unpacked"
    assert_nil Bug.unp_st_foreach(:unpack_delete), "if (!ptr) return 0"
  end
end

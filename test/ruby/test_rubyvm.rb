require 'test/unit'

class TestRubyVM < Test::Unit::TestCase
  def test_stat
    assert_kind_of Hash, RubyVM.stat
    assert_kind_of Fixnum, RubyVM.stat[:global_method_state]

    RubyVM.stat(stat = {})
    assert_not_empty stat
    assert_equal stat[:global_method_state], RubyVM.stat(:global_method_state)
  end

  def test_stat_unknown
    assert_raise(ArgumentError){ RubyVM.stat(:unknown) }
  end
end

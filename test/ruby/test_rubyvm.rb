require 'test/unit'

class TestRubyVM < Test::Unit::TestCase
  def test_stat
    assert_kind_of Hash, RubyVM.stat
    assert_kind_of Fixnum, RubyVM.stat[:method_serial]

    RubyVM.stat(stat = {})
    assert_not_empty stat
    assert_equal stat[:method_serial], RubyVM.stat(:method_serial)
  end

  def test_stat_unknown
    assert_raise(ArgumentError){ RubyVM.stat(:unknown) }
  end
end

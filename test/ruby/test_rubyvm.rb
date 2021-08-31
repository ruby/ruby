# frozen_string_literal: false
require 'test/unit'

class TestRubyVM < Test::Unit::TestCase
  def test_stat
    assert_kind_of Hash, RubyVM.stat
    assert_kind_of Integer, RubyVM.stat[:global_constant_state]

    RubyVM.stat(stat = {})
    assert_not_empty stat
    assert_equal stat[:global_constant_state], RubyVM.stat(:global_constant_state)
  end

  def test_stat_unknown
    assert_raise(ArgumentError){ RubyVM.stat(:unknown) }
    assert_raise_with_message(ArgumentError, /\u{30eb 30d3 30fc}/) {RubyVM.stat(:"\u{30eb 30d3 30fc}")}
  end
end

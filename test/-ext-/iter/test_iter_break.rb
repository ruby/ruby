# frozen_string_literal: false
require 'test/unit'
require '-test-/iter'

module TestIter
end

class TestIter::IterBreak < Test::Unit::TestCase
  def test_iter_break
    backport7896 = '[ruby-core:52607]'
    assert_equal(nil, 1.times{Bug::Iter::Breakable.iter_break}, backport7896)

    feature5895 = '[ruby-dev:45132]'
    assert_equal(42, 1.times{Bug::Iter::Breakable.iter_break_value(42)}, feature5895)
  end
end

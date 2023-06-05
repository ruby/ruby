# frozen_string_literal: false
require 'test/unit'
require "-test-/eval"

class  EvalTest < Test::Unit::TestCase
  def test_rb_eval_string
    _a = 1
    assert_equal [self, 1, __method__], rb_eval_string(%q{
      [self, _a, __method__]
    })
  end
end

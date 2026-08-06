# frozen_string_literal: false
require 'test/unit'
require "-test-/eval"

class IseqLoadTest < Test::Unit::TestCase
  def test_rb_iseq_load_from_binary
    binary = RubyVM::InstructionSequence.compile('1 + 1').to_binary
    assert_equal 2, rb_iseq_load_from_binary(binary).eval
  end
end

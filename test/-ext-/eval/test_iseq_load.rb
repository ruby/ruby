# frozen_string_literal: false
require 'test/unit'
require "-test-/eval"

class IseqLoadTest < Test::Unit::TestCase
  def test_rb_iseq_load_from_binary
    binary = begin
      RubyVM::InstructionSequence.compile('1 + 1').to_binary
    rescue RuntimeError => e
      omit e.message if /compile with coverage/ =~ e.message
      raise
    end
    assert_equal 2, rb_iseq_load_from_binary(binary).eval
  end
end

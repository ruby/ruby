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
    assert_equal 2, rb_iseq_load_from_binary(binary, nil, nil).eval
  end

  def test_rb_iseq_load_from_binary_overrides
    source = '[__FILE__, __dir__]'
    assert_equal iseq_eval(source, "original", "/original-realpath/file.rb"), load_iseq_eval(source, "original", "/original-realpath/file.rb")
    assert_equal iseq_eval(source, "override", nil), load_iseq_eval(source, "override", nil)
    assert_equal iseq_eval(source, nil, nil), load_iseq_eval(source, nil, nil)
  end

  private

  def iseq_eval(source, file, path)
    iseq = RubyVM::InstructionSequence.compile(source, file, path)
    iseq.eval
  end

  def load_iseq_eval(source, file, path)
    binary = RubyVM::InstructionSequence.compile(source).to_binary
    iseq = rb_iseq_load_from_binary(binary, file, path)
    iseq.eval
  end
end

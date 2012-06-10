require 'test/unit'
require_relative 'envutil'

class TestISeq < Test::Unit::TestCase
  ISeq = RubyVM::InstructionSequence

  def test_no_linenum
    bug5894 = '[ruby-dev:45130]'
    assert_normal_exit('p RubyVM::InstructionSequence.compile("1", "mac", "", 0).to_a', bug5894)
  end

  def test_unsupport_type
    ary = RubyVM::InstructionSequence.compile("p").to_a
    ary[9] = :foobar
    e = assert_raise(TypeError) {RubyVM::InstructionSequence.load(ary)}
    assert_match(/:foobar/, e.message)
  end if defined?(RubyVM::InstructionSequence.load)

  def test_disasm_encoding
    src = "\u{3042} = 1"
    enc, Encoding.default_internal = Encoding.default_internal, src.encoding
    assert_equal(src.encoding, RubyVM::InstructionSequence.compile(src).disasm.encoding)
    src.encode!(Encoding::Shift_JIS)
    assert_equal(true, RubyVM::InstructionSequence.compile(src).disasm.ascii_only?)
  ensure
    Encoding.default_internal = enc
  end
end

require 'test/unit'
require_relative 'envutil'

class TestISeq < Test::Unit::TestCase
  ISeq = RubyVM::InstructionSequence

  def test_no_linenum
    bug5894 = '[ruby-dev:45130]'
    assert_normal_exit('p RubyVM::InstructionSequence.compile("1", "mac", "", 0).to_a', bug5894)
  end

  def test_to_a_lines
    src = <<-EOS
    p __LINE__ # 1
    p __LINE__ # 2
               # 3
    p __LINE__ # 4
    EOS
    body = RubyVM::InstructionSequence.new(src).to_a[13]
    lines = body.find_all{|e| e.kind_of? Fixnum}
    assert_equal [1, 2, 4], lines
  end

  def test_unsupport_type
    ary = RubyVM::InstructionSequence.compile("p").to_a
    ary[9] = :foobar
    e = assert_raise(TypeError) {RubyVM::InstructionSequence.load(ary)}
    assert_match(/:foobar/, e.message)
  end if defined?(RubyVM::InstructionSequence.load)

  def test_disasm_encoding
    src = "\u{3042} = 1; \u{3042}"
    enc, Encoding.default_internal = Encoding.default_internal, src.encoding
    assert_equal(src.encoding, RubyVM::InstructionSequence.compile(src).disasm.encoding)
    src.encode!(Encoding::Shift_JIS)
    assert_equal(true, RubyVM::InstructionSequence.compile(src).disasm.ascii_only?)
  ensure
    Encoding.default_internal = enc
  end

  LINE_BEFORE_METHOD = __LINE__
  def method_test_line_trace

    a = 1

    b = 2

  end

  def test_line_trace
    iseq = ISeq.compile \
  %q{ a = 1
      b = 2
      c = 3
      # d = 4
      e = 5
      # f = 6
      g = 7

    }
    assert_equal([1, 2, 3, 5, 7], iseq.line_trace_all)
    iseq.line_trace_specify(1, true) # line 2
    iseq.line_trace_specify(3, true) # line 5

    result = []
    TracePoint.new(:specified_line){|tp|
      result << tp.lineno
    }.enable{
      iseq.eval
    }
    assert_equal([2, 5], result)

    iseq = ISeq.of(self.class.instance_method(:method_test_line_trace))
    assert_equal([LINE_BEFORE_METHOD + 3, LINE_BEFORE_METHOD + 5], iseq.line_trace_all)
  end if false # TODO: now, it is only for C APIs.

  LINE_OF_HERE = __LINE__
  def test_location
    iseq = ISeq.of(method(:test_location))

    assert_equal(__FILE__, iseq.path)
    assert(/#{__FILE__}/ =~ iseq.absolute_path)
    assert_equal("test_location", iseq.label)
    assert_equal("test_location", iseq.base_label)
    assert_equal(LINE_OF_HERE+1, iseq.first_lineno)

    line = __LINE__
    iseq = ISeq.of(Proc.new{})
    assert_equal(__FILE__, iseq.path)
    assert(/#{__FILE__}/ =~ iseq.absolute_path)
    assert_equal("test_location", iseq.base_label)
    assert_equal("block in test_location", iseq.label)
    assert_equal(line+1, iseq.first_lineno)
  end
end

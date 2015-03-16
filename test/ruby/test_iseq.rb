require 'test/unit'

class TestISeq < Test::Unit::TestCase
  ISeq = RubyVM::InstructionSequence

  def test_no_linenum
    bug5894 = '[ruby-dev:45130]'
    assert_normal_exit('p RubyVM::InstructionSequence.compile("1", "mac", "", 0).to_a', bug5894)
  end

  def lines src
    body = RubyVM::InstructionSequence.new(src).to_a[13]
    body.find_all{|e| e.kind_of? Fixnum}
  end

  def test_to_a_lines
    src = <<-EOS
    p __LINE__ # 1
    p __LINE__ # 2
               # 3
    p __LINE__ # 4
    EOS
    assert_equal [1, 2, 4], lines(src)

    src = <<-EOS
               # 1
    p __LINE__ # 2
               # 3
    p __LINE__ # 4
               # 5
    EOS
    assert_equal [2, 4], lines(src)

    src = <<-EOS
    1 # should be optimized out
    2 # should be optimized out
    p __LINE__ # 3
    p __LINE__ # 4
    5 # should be optimized out
    6 # should be optimized out
    p __LINE__ # 7
    8 # should be optimized out
    9
    EOS
    assert_equal [3, 4, 7, 9], lines(src)
  end

  def test_unsupport_type
    ary = RubyVM::InstructionSequence.compile("p").to_a
    ary[9] = :foobar
    assert_raise_with_message(TypeError, /:foobar/) {RubyVM::InstructionSequence.load(ary)}
  end if defined?(RubyVM::InstructionSequence.load)

  def test_disasm_encoding
    src = "\u{3042} = 1; \u{3042}; \u{3043}"
    asm = RubyVM::InstructionSequence.compile(src).disasm
    assert_equal(src.encoding, asm.encoding)
    assert_predicate(asm, :valid_encoding?)
    src.encode!(Encoding::Shift_JIS)
    asm = RubyVM::InstructionSequence.compile(src).disasm
    assert_equal(src.encoding, asm.encoding)
    assert_predicate(asm, :valid_encoding?)
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
    assert_match(/#{__FILE__}/, iseq.absolute_path)
    assert_equal("test_location", iseq.label)
    assert_equal("test_location", iseq.base_label)
    assert_equal(LINE_OF_HERE+1, iseq.first_lineno)

    line = __LINE__
    iseq = ISeq.of(Proc.new{})
    assert_equal(__FILE__, iseq.path)
    assert_match(/#{__FILE__}/, iseq.absolute_path)
    assert_equal("test_location", iseq.base_label)
    assert_equal("block in test_location", iseq.label)
    assert_equal(line+1, iseq.first_lineno)
  end

  def test_label_fstring
    c = Class.new{ def foobar() end }

    a, b = eval("# encoding: us-ascii\n'foobar'.freeze"),
           ISeq.of(c.instance_method(:foobar)).label
    assert_same a, b
  end

  def test_disable_opt
    src = "a['foo'] = a['bar']; 'a'.freeze"
    _,_,_,_,_,_,_,_,_,_,_,_,_,body= RubyVM::InstructionSequence.compile(src, __FILE__, __FILE__, __LINE__, false).to_a
    body.each{|insn|
      next if Integer === insn
      op = insn.first
      assert(!op.to_s.match(/^opt_/), "#{op}")
    }
  end
end

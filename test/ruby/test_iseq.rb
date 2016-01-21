require 'test/unit'

class TestISeq < Test::Unit::TestCase
  ISeq = RubyVM::InstructionSequence

  def test_no_linenum
    bug5894 = '[ruby-dev:45130]'
    assert_normal_exit('p RubyVM::InstructionSequence.compile("1", "mac", "", 0).to_a', bug5894)
  end

  def compile(src, line = nil, opt = nil)
    RubyVM::InstructionSequence.new(src, __FILE__, __FILE__, line, opt)
  end

  def lines src
    body = compile(src).to_a[13]
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

  def test_loaded_cdhash_mark
    iseq = compile(<<-'end;', __LINE__+1)
      def bug(kw)
        case kw
        when "false" then false
        when "true"  then true
        when "nil"   then nil
        else raise("unhandled argument: #{kw.inspect}")
        end
      end
    end;
    assert_separately([], <<-"end;")
      iseq = #{iseq.to_a.inspect}
      RubyVM::InstructionSequence.load(iseq).eval
      assert_equal(false, bug("false"))
      GC.start
      assert_equal(false, bug("false"))
    end;
  end if defined?(RubyVM::InstructionSequence.load)

  def test_disasm_encoding
    src = "\u{3042} = 1; \u{3042}; \u{3043}"
    asm = compile(src).disasm
    assert_equal(src.encoding, asm.encoding)
    assert_predicate(asm, :valid_encoding?)
    src.encode!(Encoding::Shift_JIS)
    asm = compile(src).disasm
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
    body= compile(src, __LINE__, false).to_a[13]
    body.each{|insn|
      next unless Array === insn
      op = insn.first
      assert(!op.to_s.match(/^opt_/), "#{op}")
    }
  end

  def test_invalid_source
    bug11159 = '[ruby-core:69219] [Bug #11159]'
    assert_raise(TypeError, bug11159) {ISeq.compile(nil)}
    assert_raise(TypeError, bug11159) {ISeq.compile(:foo)}
    assert_raise(TypeError, bug11159) {ISeq.compile(1)}
  end

  def test_frozen_string_literal_compile_option
    $f = 'f'
    line = __LINE__ + 2
    code = <<-'EOS'
    ['foo', 'foo', "#{$f}foo", "#{'foo'}"]
    EOS
    s1, s2, s3, s4 = compile(code, line, {frozen_string_literal: true}).eval
    assert_predicate(s1, :frozen?)
    assert_predicate(s2, :frozen?)
    assert_predicate(s3, :frozen?)
    assert_predicate(s4, :frozen?)
  end

  def test_safe_call_chain
    src = "a&.a&.a&.a&.a&.a"
    body = compile(src, __LINE__, {peephole_optimization: true}).to_a[13]
    labels = body.select {|op, arg| op == :branchnil}.map {|op, arg| arg}
    assert_equal(1, labels.uniq.size)
  end

  def test_parent_iseq_mark
    assert_separately([], <<-'end;', timeout: 20)
      ->{
        ->{
          ->{
            eval <<-EOS
              class Segfault
                define_method :segfault do
                  x = nil
                  GC.disable
                  1000.times do |n|
                    n.times do
                      x = (foo rescue $!).local_variables
                    end
                    GC.start
                  end
                  x
                end
              end
            EOS
          }.call
        }.call
      }.call
      at_exit { assert_equal([:n, :x], Segfault.new.segfault.sort) }
    end;
  end
end

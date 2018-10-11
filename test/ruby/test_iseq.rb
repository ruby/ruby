require 'test/unit'
require 'tempfile'

class TestISeq < Test::Unit::TestCase
  ISeq = RubyVM::InstructionSequence

  def test_no_linenum
    bug5894 = '[ruby-dev:45130]'
    assert_normal_exit('p RubyVM::InstructionSequence.compile("1", "mac", "", 0).to_a', bug5894)
  end

  def compile(src, line = nil, opt = nil)
    EnvUtil.suppress_warning do
      ISeq.new(src, __FILE__, __FILE__, line, opt)
    end
  end

  def lines src
    body = compile(src).to_a[13]
    body.find_all{|e| e.kind_of? Integer}
  end

  def test_allocate
    assert_raise(TypeError) {ISeq.allocate}
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
    ary = compile("p").to_a
    ary[9] = :foobar
    assert_raise_with_message(TypeError, /:foobar/) {ISeq.load(ary)}
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

    _a = 1

    _b = 2

  end

  def test_line_trace
    iseq = compile \
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
    assert_raise(TypeError, bug11159) {compile(nil)}
    assert_raise(TypeError, bug11159) {compile(:foo)}
    assert_raise(TypeError, bug11159) {compile(1)}
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

  # Safe call chain is not optimized when Coverage is running.
  # So we can test it only when Coverage is not running.
  def test_safe_call_chain
    src = "a&.a&.a&.a&.a&.a"
    body = compile(src, __LINE__, {peephole_optimization: true}).to_a[13]
    labels = body.select {|op, arg| op == :branchnil}.map {|op, arg| arg}
    assert_equal(1, labels.uniq.size)
  end if (!defined?(Coverage) || !Coverage.running?)

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

  def test_syntax_error_message
    feature11951 = '[Feature #11951]'

    src, line = <<-'end;', __LINE__+1
      def x@;end
      def y@;end
    end;
    e1 = e2 = nil
    m1 = EnvUtil.verbose_warning do
      e1 = assert_raise(SyntaxError) do
        eval(src, nil, __FILE__, line)
      end
    end
    m2 = EnvUtil.verbose_warning do
      e2 = assert_raise(SyntaxError) do
        ISeq.new(src, __FILE__, __FILE__, line)
      end
    end
    assert_equal([m1, e1.message], [m2, e2.message], feature11951)
    e1, e2 = e1.message.lines
    assert_send([e1, :start_with?, __FILE__])
    assert_send([e2, :start_with?, __FILE__])
  end

  def test_compile_file_error
    Tempfile.create(%w"test_iseq .rb") do |f|
      f.puts "end"
      f.close
      path = f.path
      assert_in_out_err(%W[- #{path}], "#{<<-"begin;"}\n#{<<-"end;"}", /keyword_end/, [], success: true)
      begin;
        path = ARGV[0]
        begin
          RubyVM::InstructionSequence.compile_file(path)
        rescue SyntaxError => e
          puts e.message
        end
      end;
    end
  end

  def test_translate_by_object
    assert_separately([], <<-"end;")
      class Object
        def translate
        end
      end
      assert_equal(0, eval("0"))
    end;
  end

  def test_inspect
    %W[foo \u{30d1 30b9}].each do |name|
      assert_match /@#{name}/, ISeq.compile("", name).inspect, name
      m = ISeq.compile("class TestISeq::Inspect; def #{name}; end; instance_method(:#{name}); end").eval
      assert_match /:#{name}@/, ISeq.of(m).inspect, name
    end
  end

  def sample_iseq
    ISeq.compile <<-EOS.gsub(/^.*?: /, "")
     1: class C
     2:   def foo
     3:     begin
     4:     rescue
     5:       p :rescue
     6:     ensure
     7:       p :ensure
     8:     end
     9:   end
    10:   def bar
    11:     1.times{
    12:       2.times{
    13:       }
    14:     }
    15:   end
    16: end
    17: class D < C
    18: end
    EOS
  end

  def test_each_child
    iseq = sample_iseq

    collect_iseq = lambda{|iseq|
      iseqs = []
      iseq.each_child{|child_iseq|
        iseqs << collect_iseq.call(child_iseq)
      }
      ["#{iseq.label}@#{iseq.first_lineno}", *iseqs.sort_by{|k, *| k}]
    }

    expected = ["<compiled>@1",
                  ["<class:C>@1",
                    ["bar@10", ["block in bar@11",
                            ["block (2 levels) in bar@12"]]],
                    ["foo@2", ["ensure in foo@2"],
                              ["rescue in foo@4"]]],
                  ["<class:D>@17"]]

    assert_equal expected, collect_iseq.call(iseq)
  end

  def test_trace_points
    collect_iseq = lambda{|iseq|
      iseqs = []
      iseq.each_child{|child_iseq|
        iseqs << collect_iseq.call(child_iseq)
      }
      [["#{iseq.label}@#{iseq.first_lineno}", iseq.trace_points], *iseqs.sort_by{|k, *| k}]
    }
    assert_equal [["<compiled>@1", [[1, :line],
                                    [17, :line]]],
                   [["<class:C>@1", [[1, :class],
                                     [2, :line],
                                     [10, :line],
                                     [16, :end]]],
                     [["bar@10", [[10, :call],
                                  [11, :line],
                                  [15, :return]]],
                         [["block in bar@11", [[11, :b_call],
                                               [12, :line],
                                               [14, :b_return]]],
                         [["block (2 levels) in bar@12", [[12, :b_call],
                                                          [13, :b_return]]]]]],
                      [["foo@2", [[2, :call],
                                  [4, :line],
                                  [7, :line],
                                  [9, :return]]],
                       [["ensure in foo@2", [[7, :line]]]],
                       [["rescue in foo@4", [[5, :line]]]]]],
                   [["<class:D>@17", [[17, :class],
                                      [18, :end]]]]], collect_iseq.call(sample_iseq)
  end

  def test_empty_iseq_lineno
    iseq = ISeq.compile(<<-EOS)
    # 1
    # 2
    def foo   # line 3 empty method
    end       # line 4
    1.time do # line 5 empty block
    end       # line 6
    class C   # line 7 empty class
    end
    EOS

    iseq.each_child{|ci|
      ary = ci.to_a
      type = ary[9]
      name = ary[5]
      line = ary[13].first
      case ary[9]
      when :method
        assert_equal "foo", name
        assert_equal 3, line
      when :class
        assert_equal '<class:C>', name
        assert_equal 7, line
      when :block
        assert_equal 'block in <compiled>', name
        assert_equal 5, line
      else
        raise "unknown ary: " + ary.inspect
      end
    }
  end

  def test_to_binary_tracepoint
    filename = "#{File.basename(__FILE__)}_#{__LINE__}"
    iseq = RubyVM::InstructionSequence.compile("x = 1\n y = 2", filename)
    iseq_bin = iseq.to_binary
    ary = []
    TracePoint.new(:line){|tp|
      next unless tp.path == filename
      ary << [tp.path, tp.lineno]
    }.enable{
      ISeq.load_from_binary(iseq_bin).eval
    }
    assert_equal [[filename, 1], [filename, 2]], ary, '[Bug #14702]'
  end
end

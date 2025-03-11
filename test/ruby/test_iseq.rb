require 'test/unit'
require 'tempfile'

class TestISeq < Test::Unit::TestCase
  ISeq = RubyVM::InstructionSequence

  def test_no_linenum
    bug5894 = '[ruby-dev:45130]'
    assert_normal_exit('p RubyVM::InstructionSequence.compile("1", "mac", "", 0).to_a', bug5894)
  end

  def compile(src, line = nil, opt = nil)
    unless line
      line = caller_locations(1).first.lineno
    end
    EnvUtil.suppress_warning do
      ISeq.new(src, __FILE__, __FILE__, line, opt)
    end
  end

  def lines src, lines = nil
    body = compile(src, lines).to_a[13]
    body.find_all{|e| e.kind_of? Integer}
  end

  def test_allocate
    assert_raise(TypeError) {ISeq.allocate}
  end

  def test_to_a_lines
    assert_equal [__LINE__+1, __LINE__+2, __LINE__+4], lines(<<-EOS, __LINE__+1)
    p __LINE__ # 1
    p __LINE__ # 2
               # 3
    p __LINE__ # 4
    EOS

    assert_equal [__LINE__+2, __LINE__+4], lines(<<-EOS, __LINE__+1)
               # 1
    p __LINE__ # 2
               # 3
    p __LINE__ # 4
               # 5
    EOS

    assert_equal [__LINE__+3, __LINE__+4, __LINE__+7, __LINE__+9], lines(<<~EOS, __LINE__+1)
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
  end

  def test_unsupported_type
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

  def test_cdhash_after_roundtrip
    # CDHASH was not built properly when loading from binary and
    # was causing opt_case_dispatch to clobber its stack canary
    # for its "leaf" instruction attribute.
    iseq = compile(<<~EOF, __LINE__+1)
      case Class.new(String).new("foo")
      when "foo"
        42
      end
    EOF
    assert_equal(42, ISeq.load_from_binary(iseq.to_binary).eval)
  end

  def test_forwardable
    iseq = compile(<<~EOF, __LINE__+1)
      Class.new {
        def bar(a, b); a + b; end
        def foo(...); bar(...); end
      }
    EOF
    assert_equal(42, ISeq.load_from_binary(iseq.to_binary).eval.new.foo(40, 2))
  end

  def test_super_with_block
    iseq = compile(<<~EOF, __LINE__+1)
      def (Object.new).touch(*) # :nodoc:
        foo { super }
      end
      42
    EOF
    assert_equal(42, ISeq.load_from_binary(iseq.to_binary).eval)
  end

  def test_super_with_block_hash_0
    iseq = compile(<<~EOF, __LINE__+1)
      # [Bug #18250] `req` specifically cause `Assertion failed: (key != 0), function hash_table_raw_insert`
      def (Object.new).touch(req, *)
        foo { super }
      end
      42
    EOF
    assert_equal(42, ISeq.load_from_binary(iseq.to_binary).eval)
  end

  def test_super_with_block_and_kwrest
    iseq = compile(<<~EOF, __LINE__+1)
      def (Object.new).touch(**) # :nodoc:
        foo { super }
      end
      42
    EOF
    assert_equal(42, ISeq.load_from_binary(iseq.to_binary).eval)
  end

  def test_lambda_with_ractor_roundtrip
    iseq = compile(<<~EOF, __LINE__+1)
      x = 42
      y = nil.instance_eval{ lambda { x } }
      Ractor.make_shareable(y)
      y.call
    EOF
    assert_equal(42, ISeq.load_from_binary(iseq.to_binary).eval)
  end

  def test_super_with_anonymous_block
    iseq = compile(<<~EOF, __LINE__+1)
      def (Object.new).touch(&) # :nodoc:
        foo { super }
      end
      42
    EOF
    assert_equal(42, ISeq.load_from_binary(iseq.to_binary).eval)
  end

  def test_ractor_unshareable_outer_variable
    name = "\u{2603 26a1}"
    y = nil.instance_eval do
      eval("proc {#{name} = nil; proc {|x| #{name} = x}}").call
    end
    assert_raise_with_message(ArgumentError, /\(#{name}\)/) do
      Ractor.make_shareable(y)
    end
    y = nil.instance_eval do
      eval("proc {#{name} = []; proc {|x| #{name}}}").call
    end
    assert_raise_with_message(Ractor::IsolationError, /'#{name}'/) do
      Ractor.make_shareable(y)
    end
    obj = Object.new
    def obj.foo(*) nil.instance_eval{ ->{super} } end
    assert_raise_with_message(Ractor::IsolationError, /refer unshareable object \[\] from variable '\*'/) do
      Ractor.make_shareable(obj.foo)
    end
  end

  def test_ractor_shareable_value_frozen_core
    iseq = RubyVM::InstructionSequence.compile(<<~'RUBY')
      # shareable_constant_value: literal
      REGEX = /#{}/ # [Bug #20569]
    RUBY
    assert_includes iseq.to_binary, "REGEX".b
  end

  def test_disasm_encoding
    src = +"\u{3042} = 1; \u{3042}; \u{3043}"
    asm = compile(src).disasm
    assert_equal(src.encoding, asm.encoding)
    assert_predicate(asm, :valid_encoding?)
    src.encode!(Encoding::Shift_JIS)
    asm = compile(src).disasm
    assert_equal(src.encoding, asm.encoding)
    assert_predicate(asm, :valid_encoding?)

    obj = Object.new
    name = "\u{2603 26a1}"
    obj.instance_eval("def #{name}; tap {}; end")
    assert_include(RubyVM::InstructionSequence.of(obj.method(name)).disasm, name)
  end

  def test_compile_file_encoding
    Tempfile.create(%w"test_iseq .rb") do |f|
      f.puts "{ '\u00de' => 'Th', '\u00df' => 'ss', '\u00e0' => 'a' }"
      f.close

      EnvUtil.with_default_external(Encoding::US_ASCII) do
        assert_warn('') {
          load f.path
        }
        assert_nothing_raised(SyntaxError) {
          RubyVM::InstructionSequence.compile_file(f.path)
        }
      end
    end
  end

  LINE_BEFORE_METHOD = __LINE__
  def method_test_line_trace

    _a = 1

    _b = 2

  end

  def test_line_trace
    iseq = compile(<<~EOF, __LINE__+1)
      a = 1
      b = 2
      c = 3
      # d = 4
      e = 5
      # f = 6
      g = 7
    EOF

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
    assert_not_predicate(s3, :frozen?)
    assert_not_predicate(s4, :frozen?)
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

    if e1.message.lines[0] == "#{__FILE__}:#{line}: syntax errors found\n"
      # Prism lays out the error messages in line with the source, so the
      # following assertions do not make sense in that context.
    else
      message = e1.message.each_line
      message.with_index(1) do |line, i|
        next if /^ / =~ line
        assert_send([line, :start_with?, __FILE__],
                    proc {message.map {|l, j| (i == j ? ">" : " ") + l}.join("")})
      end
    end
  end

  # [Bug #19173]
  def test_compile_error
    assert_raise SyntaxError do
      RubyVM::InstructionSequence.compile 'using Module.new; yield'
    end
  end

  def test_compile_file_error
    Tempfile.create(%w"test_iseq .rb") do |f|
      f.puts "end"
      f.close
      path = f.path
      assert_in_out_err(%W[- #{path}], "#{<<-"begin;"}\n#{<<-"end;"}", /unexpected 'end'/, [], success: true)
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
      assert_match(/@#{name}/, ISeq.compile("", name).inspect, name)
      m = ISeq.compile("class TestISeq::Inspect; def #{name}; end; instance_method(:#{name}); end").eval
      assert_match(/:#{name}@/, ISeq.of(m).inspect, name)
    end
  end

  def anon_star(*); end

  def test_anon_rest_param_in_disasm
    iseq = RubyVM::InstructionSequence.of(method(:anon_star))
    param_names = iseq.to_a[iseq.to_a.index(:method) + 1]
    assert_equal [:*], param_names
  end

  def anon_keyrest(**); end

  def test_anon_keyrest_param_in_disasm
    iseq = RubyVM::InstructionSequence.of(method(:anon_keyrest))
    param_names = iseq.to_a[iseq.to_a.index(:method) + 1]
    assert_equal [:**], param_names
  end

  def anon_block(&); end

  def test_anon_block_param_in_disasm
    iseq = RubyVM::InstructionSequence.of(method(:anon_block))
    param_names = iseq.to_a[iseq.to_a.index(:method) + 1]
    assert_equal [:&], param_names
  end

  def strip_lineno(source)
    source.gsub(/^.*?: /, "")
  end

  def sample_iseq
    ISeq.compile(strip_lineno(<<-EOS))
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
                    ["foo@2", ["ensure in foo@7"],
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
                       [["ensure in foo@7", [[7, :line]]]],
                       [["rescue in foo@4", [[5, :line],
                                             [5, :rescue]]]]]],
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
      case type
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

  def hexdump(bin)
    bin.unpack1("H*").gsub(/.{1,32}/) {|s|
      "#{'%04x:' % $~.begin(0)}#{s.gsub(/../, " \\&").tap{|_|_[24]&&="-"}}\n"
    }
  end

  def assert_iseq_to_binary(code, mesg = nil)
    iseq = RubyVM::InstructionSequence.compile(code)
    bin = assert_nothing_raised(mesg) do
      iseq.to_binary
    rescue RuntimeError => e
      omit e.message if /compile with coverage/ =~ e.message
      raise
    end
    10.times do
      bin2 = iseq.to_binary
      assert_equal(bin, bin2, message(mesg) {diff hexdump(bin), hexdump(bin2)})
    end
    iseq2 = RubyVM::InstructionSequence.load_from_binary(bin)
    a1 = iseq.to_a
    a2 = iseq2.to_a
    assert_equal(a1, a2, message(mesg) {diff iseq.disassemble, iseq2.disassemble})
    if iseq2.script_lines
      assert_kind_of(Array, iseq2.script_lines)
    else
      assert_nil(iseq2.script_lines)
    end
    iseq2
  end

  def test_to_binary_with_hidden_local_variables
    assert_iseq_to_binary("for _foo in bar; end")

    bin = RubyVM::InstructionSequence.compile(<<-RUBY).to_binary
      Object.new.instance_eval do
        a = []
        def self.bar; [1] end
        for foo in bar
          a << (foo * 2)
        end
        a
      end
    RUBY
    v = RubyVM::InstructionSequence.load_from_binary(bin).eval
    assert_equal([2], v)
  end

  def test_to_binary_with_objects
    assert_iseq_to_binary("[]"+100.times.map{|i|"<</#{i}/"}.join)
    assert_iseq_to_binary("@x ||= (1..2)")
  end

  def test_to_binary_pattern_matching
    code = "case foo; in []; end"
    iseq = compile(code)
    assert_include(iseq.disasm, "TypeError")
    assert_include(iseq.disasm, "NoMatchingPatternError")
    EnvUtil.suppress_warning do
      assert_iseq_to_binary(code, "[Feature #14912]")
    end
  end

  def test_to_binary_dumps_nokey
    iseq = assert_iseq_to_binary(<<-RUBY)
      o = Object.new
      class << o
        def foo(**nil); end
      end
      o
    RUBY
    assert_equal([[:nokey]], iseq.eval.singleton_method(:foo).parameters)
  end

  def test_to_binary_line_info
    assert_iseq_to_binary("#{<<~"begin;"}\n#{<<~'end;'}", '[Bug #14660]').eval
    begin;
      class P
        def p; end
        def q; end
        E = ""
        N = "#{E}"
        attr_reader :i
      end
    end;

    # cleanup
    ::Object.class_eval do
      remove_const :P
    end
  end

  def collect_from_binary_tracepoint_lines(tracepoint_type, filename)
    iseq = RubyVM::InstructionSequence.compile(strip_lineno(<<-RUBY), filename)
      class A
        class B
          2.times {
            def self.foo
              _a = 'good day'
              raise
            rescue
              'dear reader'
            end
          }
        end
        B.foo
      end
    RUBY

    iseq_bin = iseq.to_binary
    iseq = ISeq.load_from_binary(iseq_bin)
    lines = []
    TracePoint.new(tracepoint_type){|tp|
      next unless tp.path == filename
      lines << tp.lineno
    }.enable{
      EnvUtil.suppress_warning {iseq.eval}
    }

    lines
  ensure
    Object.send(:remove_const, :A) rescue nil
  end

  def test_to_binary_line_tracepoint
    filename = "#{File.basename(__FILE__)}_#{__LINE__}"
    lines = collect_from_binary_tracepoint_lines(:line, filename)

    assert_equal [1, 2, 3, 4, 4, 12, 5, 6, 8], lines, '[Bug #14702]'
  end

  def test_to_binary_class_tracepoint
    filename = "#{File.basename(__FILE__)}_#{__LINE__}"
    lines = collect_from_binary_tracepoint_lines(:class, filename)

    assert_equal [1, 2], lines, '[Bug #14702]'
  end

  def test_to_binary_end_tracepoint
    filename = "#{File.basename(__FILE__)}_#{__LINE__}"
    lines = collect_from_binary_tracepoint_lines(:end, filename)

    assert_equal [11, 13], lines, '[Bug #14702]'
  end

  def test_to_binary_return_tracepoint
    filename = "#{File.basename(__FILE__)}_#{__LINE__}"
    lines = collect_from_binary_tracepoint_lines(:return, filename)

    assert_equal [9], lines, '[Bug #14702]'
  end

  def test_to_binary_b_call_tracepoint
    filename = "#{File.basename(__FILE__)}_#{__LINE__}"
    lines = collect_from_binary_tracepoint_lines(:b_call, filename)

    assert_equal [3, 3], lines, '[Bug #14702]'
  end

  def test_to_binary_b_return_tracepoint
    filename = "#{File.basename(__FILE__)}_#{__LINE__}"
    lines = collect_from_binary_tracepoint_lines(:b_return, filename)

    assert_equal [10, 10], lines, '[Bug #14702]'
  end

  def test_iseq_of
    [
      proc{},
      method(:test_iseq_of),
      RubyVM::InstructionSequence.compile("p 1", __FILE__),
      begin; raise "error"; rescue => error; error.backtrace_locations[0]; end
    ].each{|src|
      iseq = RubyVM::InstructionSequence.of(src)
      assert_equal __FILE__, iseq.path
    }
  end

  def test_iseq_of_twice_for_same_code
    [
      proc{},
      method(:test_iseq_of_twice_for_same_code),
      RubyVM::InstructionSequence.compile("p 1"),
      begin; raise "error"; rescue => error; error.backtrace_locations[0]; end
    ].each{|src|
      iseq1 = RubyVM::InstructionSequence.of(src)
      iseq2 = RubyVM::InstructionSequence.of(src)

      # ISeq objects should be same for same src
      assert_equal iseq1.object_id, iseq2.object_id
    }
  end

  def test_iseq_builtin_to_a
    invokebuiltin = eval(EnvUtil.invoke_ruby(['-e', <<~EOS], '', true).first)
      insns = RubyVM::InstructionSequence.of([].method(:pack)).to_a.last
      p insns.find { |insn| insn.is_a?(Array) && insn[0] == :opt_invokebuiltin_delegate_leave }
    EOS
    assert_not_nil(invokebuiltin)
    assert_equal([:func_ptr, :argc, :index, :name], invokebuiltin[1].keys)
  end

  def test_iseq_builtin_load
    Tempfile.create(["builtin", ".iseq"]) do |f|
      f.binmode
      f.write(RubyVM::InstructionSequence.of(1.method(:abs)).to_binary)
      f.close
      assert_separately(["-", f.path], "#{<<~"begin;"}\n#{<<~'end;'}")
      begin;
        bin = File.binread(ARGV[0])
        assert_raise(ArgumentError) do
          RubyVM::InstructionSequence.load_from_binary(bin)
        end
      end;
    end
  end

  def test_iseq_option_debug_level
    assert_raise(TypeError) {ISeq.compile("", debug_level: "")}
    assert_ruby_status([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      RubyVM::InstructionSequence.compile("", debug_level: 5)
    end;
  end

  def test_mandatory_only
    assert_separately [], <<~RUBY
      at0 = Time.at(0)
      assert_equal at0, Time.public_send(:at, 0, 0)
    RUBY
  end

  def test_mandatory_only_redef
    assert_separately ['-W0'], <<~RUBY
      r = Ractor.new{
        Float(10)
        module Kernel
          undef Float
          def Float(n)
            :new
          end
        end
        GC.start
        Float(30)
      }
      assert_equal :new, r.take
    RUBY
  end

  def test_ever_condition_loop
    assert_ruby_status([], "BEGIN {exit}; while true && true; end")
  end

  def test_unreachable_syntax_error
    mesg = /Invalid break/
    assert_syntax_error("false and break", mesg)
    assert_syntax_error("if false and break; end", mesg)
  end

  def test_unreachable_pattern_matching
    assert_in_out_err([], "true or 1 in 1")
    assert_in_out_err([], "true or (case 1; in 1; 1; in 2; 2; end)")
  end

  def test_unreachable_pattern_matching_in_if_condition
    assert_in_out_err([], "#{<<~"begin;"}\n#{<<~'end;'}", %w[1])
    begin;
      if true or {a: 0} in {a:}
        p 1
      else
        p a
      end
    end;
  end

  def test_unreachable_next_in_block
    bug20344 = '[ruby-core:117210] [Bug #20344]'
    assert_nothing_raised(SyntaxError, bug20344) do
      compile(<<~RUBY)
        proc do
          next

          case nil
          when "a"
            next
          when "b"
          when "c"
            proc {}
          end

          next
        end
      RUBY
    end
  end

  def test_loading_kwargs_memory_leak
    assert_no_memory_leak([], "#{<<~"begin;"}", "#{<<~'end;'}", rss: true)
    a = RubyVM::InstructionSequence.compile("foo(bar: :baz)").to_binary
    begin;
      1_000_000.times do
        RubyVM::InstructionSequence.load_from_binary(a)
      end
    end;
  end

  def test_ibf_bignum
    iseq = RubyVM::InstructionSequence.compile("0x0"+"_0123_4567_89ab_cdef"*5)
    expected = iseq.eval
    result = RubyVM::InstructionSequence.load_from_binary(iseq.to_binary).eval
    assert_equal expected, result, proc {sprintf("expected: %x, result: %x", expected, result)}
  end

  def test_compile_prism_with_file
    Tempfile.create(%w"test_iseq .rb") do |f|
      f.puts "_name = 'Prism'; puts 'hello'"
      f.close

      assert_nothing_raised(TypeError) do
        RubyVM::InstructionSequence.compile_prism(f)
      end
    end
  end

  def block_using_method
    yield
  end

  def block_unused_method
  end

  def test_unused_param
    a = RubyVM::InstructionSequence.of(method(:block_using_method)).to_a

    assert_equal true, a.dig(11, :use_block)

    b = RubyVM::InstructionSequence.of(method(:block_unused_method)).to_a
    assert_equal nil, b.dig(11, :use_block)
  end

  def test_compile_prism_with_invalid_object_type
    assert_raise(TypeError) do
      RubyVM::InstructionSequence.compile_prism(Object.new)
    end
  end

  def test_load_from_binary_only_accepts_string_param
    assert_raise(TypeError) do
      var_0 = 0
      RubyVM::InstructionSequence.load_from_binary(var_0)
    end
  end

  def test_while_in_until_condition
    assert_in_out_err(["--dump=i", "-e", "until while 1; end; end"]) do |stdout, stderr, status|
      assert_include(stdout.shift, "== disasm:")
      assert_include(stdout.pop, "leave")
      assert_predicate(status, :success?)
    end
  end

  def test_compile_empty_under_gc_stress
    EnvUtil.under_gc_stress do
      RubyVM::InstructionSequence.compile_file(File::NULL)
    end
  end
end

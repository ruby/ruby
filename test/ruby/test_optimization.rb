# frozen_string_literal: false
require 'test/unit'
require 'objspace'

class TestRubyOptimization < Test::Unit::TestCase
  def assert_redefine_method(klass, method, code, msg = nil)
    assert_separately([], <<-"end;")#    do
      class #{klass}
        undef #{method}
        def #{method}(*args)
          args[0]
        end
      end
      #{code}
    end;
  end

  def disasm(name)
    RubyVM::InstructionSequence.of(method(name)).disasm
  end

  def test_fixnum_plus
    assert_equal 21, 10 + 11
    assert_redefine_method('Integer', '+', 'assert_equal 11, 10 + 11')
  end

  def test_fixnum_minus
    assert_equal 5, 8 - 3
    assert_redefine_method('Integer', '-', 'assert_equal 3, 8 - 3')
  end

  def test_fixnum_mul
    assert_equal 15, 3 * 5
    assert_redefine_method('Integer', '*', 'assert_equal 5, 3 * 5')
  end

  def test_fixnum_div
    assert_equal 3, 15 / 5
    assert_redefine_method('Integer', '/', 'assert_equal 5, 15 / 5')
  end

  def test_fixnum_mod
    assert_equal 1, 8 % 7
    assert_redefine_method('Integer', '%', 'assert_equal 7, 8 % 7')
  end

  def test_float_plus
    assert_equal 4.0, 2.0 + 2.0
    assert_redefine_method('Float', '+', 'assert_equal 2.0, 2.0 + 2.0')
  end

  def test_float_minus
    assert_equal 4.0, 2.0 + 2.0
    assert_redefine_method('Float', '+', 'assert_equal 2.0, 2.0 + 2.0')
  end

  def test_float_mul
    assert_equal 29.25, 4.5 * 6.5
    assert_redefine_method('Float', '*', 'assert_equal 6.5, 4.5 * 6.5')
  end

  def test_float_div
    assert_in_delta 0.63063063063063063, 4.2 / 6.66
    assert_redefine_method('Float', '/', 'assert_equal 6.66, 4.2 / 6.66', "[Bug #9238]")
  end

  def test_string_length
    assert_equal 6, "string".length
    assert_redefine_method('String', 'length', 'assert_nil "string".length')
  end

  def test_string_size
    assert_equal 6, "string".size
    assert_redefine_method('String', 'size', 'assert_nil "string".size')
  end

  def test_string_empty?
    assert_equal true, "".empty?
    assert_equal false, "string".empty?
    assert_redefine_method('String', 'empty?', 'assert_nil "string".empty?')
  end

  def test_string_plus
    assert_equal "", "" + ""
    assert_equal "x", "x" + ""
    assert_equal "x", "" + "x"
    assert_equal "ab", "a" + "b"
    assert_redefine_method('String', '+', 'assert_equal "b", "a" + "b"')
  end

  def test_string_succ
    assert_equal 'b', 'a'.succ
    assert_equal 'B', 'A'.succ
  end

  def test_string_format
    assert_equal '2', '%d' % 2
    assert_redefine_method('String', '%', 'assert_equal 2, "%d" % 2')
  end

  def test_string_freeze
    assert_equal "foo", "foo".freeze
    assert_equal "foo".freeze.object_id, "foo".freeze.object_id
    assert_redefine_method('String', 'freeze', 'assert_nil "foo".freeze')
  end

  def test_string_freeze_saves_memory
    n = 16384
    data = '.'.freeze
    r, w = IO.pipe
    w.write data

    s = r.readpartial(n, '')
    assert_operator ObjectSpace.memsize_of(s), :>=, n,
      'IO buffer NOT resized prematurely because will likely be reused'

    s.freeze
    assert_equal ObjectSpace.memsize_of(data), ObjectSpace.memsize_of(s),
      'buffer resized on freeze since it cannot be written to again'
  ensure
    r.close if r
    w.close if w
  end

  def test_string_eq_neq
    %w(== !=).each do |m|
      assert_redefine_method('String', m, <<-end)
        assert_equal :b, ("a" #{m} "b").to_sym
        b = 'b'
        assert_equal :b, ("a" #{m} b).to_sym
        assert_equal :b, (b #{m} "b").to_sym
      end
    end
  end

  def test_string_ltlt
    assert_equal "", "" << ""
    assert_equal "x", "x" << ""
    assert_equal "x", "" << "x"
    assert_equal "ab", "a" << "b"
    assert_redefine_method('String', '<<', 'assert_equal "b", "a" << "b"')
  end

  def test_array_plus
    assert_equal [1,2], [1]+[2]
    assert_redefine_method('Array', '+', 'assert_equal [2], [1]+[2]')
  end

  def test_array_minus
    assert_equal [2], [1,2] - [1]
    assert_redefine_method('Array', '-', 'assert_equal [1], [1,2]-[1]')
  end

  def test_array_length
    assert_equal 0, [].length
    assert_equal 3, [1,2,3].length
    assert_redefine_method('Array', 'length', 'assert_nil([].length); assert_nil([1,2,3].length)')
  end

  def test_array_empty?
    assert_equal true, [].empty?
    assert_equal false, [1,2,3].empty?
    assert_redefine_method('Array', 'empty?', 'assert_nil([].empty?); assert_nil([1,2,3].empty?)')
  end

  def test_hash_length
    assert_equal 0, {}.length
    assert_equal 1, {1=>1}.length
    assert_redefine_method('Hash', 'length', 'assert_nil({}.length); assert_nil({1=>1}.length)')
  end

  def test_hash_empty?
    assert_equal true, {}.empty?
    assert_equal false, {1=>1}.empty?
    assert_redefine_method('Hash', 'empty?', 'assert_nil({}.empty?); assert_nil({1=>1}.empty?)')
  end

  def test_hash_aref_with
    h = { "foo" => 1 }
    assert_equal 1, h["foo"]
    assert_redefine_method('Hash', '[]', <<-end)
      h = { "foo" => 1 }
      assert_equal "foo", h["foo"]
    end
  end

  def test_hash_aset_with
    h = {}
    assert_equal 1, h["foo"] = 1
    assert_redefine_method('Hash', '[]=', <<-end)
      h = {}
      assert_equal 1, h["foo"] = 1, "assignment always returns value set"
      assert_nil h["foo"]
    end
  end

  class MyObj
    def ==(other)
      true
    end
  end

  def test_eq
    assert_equal true, nil == nil
    assert_equal true, 1 == 1
    assert_equal true, 'string' == 'string'
    assert_equal true, 1 == MyObj.new
    assert_equal false, nil == MyObj.new
    assert_equal true, MyObj.new == 1
    assert_equal true, MyObj.new == nil
  end

  def self.tailcall(klass, src, file = nil, path = nil, line = nil, tailcall: true)
    unless file
      loc, = caller_locations(1, 1)
      file = loc.path
      line ||= loc.lineno
    end
    RubyVM::InstructionSequence.new("proc {|_|_.class_eval {#{src}}}",
                                    file, (path || file), line,
                                    tailcall_optimization: tailcall,
                                    trace_instruction: false)
      .eval[klass]
  end

  def tailcall(*args)
    self.class.tailcall(singleton_class, *args)
  end

  def test_tailcall
    bug4082 = '[ruby-core:33289]'

    tailcall(<<-EOF)
      def fact_helper(n, res)
        if n == 1
          res
        else
          fact_helper(n - 1, n * res)
        end
      end
      def fact(n)
        fact_helper(n, 1)
      end
    EOF
    assert_equal(9131, fact(3000).to_s.size, message(bug4082) {disasm(:fact_helper)})
  end

  def test_tailcall_with_block
    bug6901 = '[ruby-dev:46065]'

    tailcall(<<-EOF)
      def identity(val)
        val
      end

      def delay
        -> {
          identity(yield)
        }
      end
    EOF
    assert_equal(123, delay { 123 }.call, message(bug6901) {disasm(:delay)})
  end

  def just_yield
    yield
  end

  def test_tailcall_inhibited_by_block
    tailcall(<<-EOF)
      def yield_result
        just_yield {:ok}
      end
    EOF
    assert_equal(:ok, yield_result, message {disasm(:yield_result)})
  end

  def do_raise
    raise "should be rescued"
  end

  def errinfo
    $!
  end

  def test_tailcall_inhibited_by_rescue
    bug12082 = '[ruby-core:73871] [Bug #12082]'

    tailcall(<<-'end;')
      def to_be_rescued
        return do_raise
        1 + 2
      rescue
        errinfo
      end
    end;
    result = assert_nothing_raised(RuntimeError, message(bug12082) {disasm(:to_be_rescued)}) {
      to_be_rescued
    }
    assert_instance_of(RuntimeError, result, bug12082)
    assert_equal("should be rescued", result.message, bug12082)
  end

  def test_tailcall_symbol_block_arg
    bug12565 = '[ruby-core:46065]'
    tailcall(<<-EOF)
      def apply_one_and_two(&block)
        yield(1, 2)
      end

      def add_one_and_two
        apply_one_and_two(&:+)
      end
    EOF
    assert_equal(3, add_one_and_two,
                 message(bug12565) {disasm(:add_one_and_two)})
  end

  def test_tailcall_interrupted_by_sigint
    bug12576 = 'ruby-core:76327'
    script = <<EOS
RubyVM::InstructionSequence.compile_option = {
  :tailcall_optimization => true,
  :trace_instruction => false
}

eval <<EOF
def foo
  foo
end
puts("start")
STDOUT.flush
foo
EOF
EOS
    status, err = EnvUtil.invoke_ruby([], "", true, true, {}) {
      |in_p, out_p, err_p, pid|
      in_p.write(script)
      in_p.close
      out_p.gets
      sig = :INT
      begin
        Process.kill(sig, pid)
        Timeout.timeout(1) do
          *, stat = Process.wait2(pid)
          [stat, err_p.read]
        end
      rescue Timeout::Error
        if sig == :INT
          sig = :KILL
          retry
        else
          raise
        end
      end
    }
    assert_not_equal("SEGV", Signal.signame(status.termsig || 0), bug12576)
  end unless /mswin|mingw/ =~ RUBY_PLATFORM

  def test_tailcall_condition_block
    bug = '[ruby-core:78015] [Bug #12905]'

    src = "#{<<-"begin;"}\n#{<<-"end;"}"
    begin;
      def run(current, final)
        if current < final
          run(current+1, final)
        else
          nil
        end
      end
    end;

    obj = Object.new
    self.class.tailcall(obj.singleton_class, src, tailcall: false)
    e = assert_raise(SystemStackError) {
      obj.run(1, Float::INFINITY)
    }
    level = e.backtrace_locations.size
    obj = Object.new
    self.class.tailcall(obj.singleton_class, src, tailcall: true)
    level *= 2
    mesg = message {"#{bug}: #{$!.backtrace_locations.size} / #{level} stack levels"}
    assert_nothing_raised(SystemStackError, mesg) {
      obj.run(1, level)
    }
  end

  class Bug10557
    def [](_)
      block_given?
    end

    def []=(_, _)
      block_given?
    end
  end

  def test_block_given_aset_aref
    bug10557 = '[ruby-core:66595]'
    assert_equal(true, Bug10557.new.[](nil){}, bug10557)
    assert_equal(true, Bug10557.new.[](0){}, bug10557)
    assert_equal(true, Bug10557.new.[](false){}, bug10557)
    assert_equal(true, Bug10557.new.[](''){}, bug10557)
    assert_equal(true, Bug10557.new.[]=(nil, 1){}, bug10557)
    assert_equal(true, Bug10557.new.[]=(0, 1){}, bug10557)
    assert_equal(true, Bug10557.new.[]=(false, 1){}, bug10557)
    assert_equal(true, Bug10557.new.[]=('', 1){}, bug10557)
  end

  def test_string_freeze_block
    assert_separately([], <<-"end;")#    do
      class String
        undef freeze
        def freeze
          block_given?
        end
      end
      assert_equal(true, "block".freeze {})
      assert_equal(false, "block".freeze)
    end;
  end

  def test_opt_case_dispatch
    code = <<-EOF
      case foo
      when "foo" then :foo
      when true then true
      when false then false
      when :sym then :sym
      when 6 then :fix
      when nil then nil
      when 0.1 then :float
      when 0xffffffffffffffff then :big
      else
        :nomatch
      end
    EOF
    check = {
      'foo' => :foo,
      true => true,
      false => false,
      :sym => :sym,
      6 => :fix,
      nil => nil,
      0.1 => :float,
      0xffffffffffffffff => :big,
    }
    iseq = RubyVM::InstructionSequence.compile(code)
    assert_match %r{\bopt_case_dispatch\b}, iseq.disasm
    check.each do |foo, expect|
      assert_equal expect, eval("foo = #{foo.inspect}\n#{code}")
    end
    assert_equal :nomatch, eval("foo = :blah\n#{code}")
    check.each do |foo, _|
      klass = foo.class.to_s
      assert_separately([], <<-"end;") # do
        class #{klass}
          undef ===
          def ===(*args)
            false
          end
        end
        foo = #{foo.inspect}
        ret = #{code}
        assert_equal :nomatch, ret, foo.inspect
      end;
    end
  end

  def test_eqq
    [ nil, true, false, 0.1, :sym, 'str', 0xffffffffffffffff ].each do |v|
      k = v.class.to_s
      assert_redefine_method(k, '===', "assert_equal(#{v.inspect} === 0, 0)")
    end
  end

  def test_opt_case_dispatch_inf
    inf = 1.0/0.0
    result = case inf
             when 1 then 1
             when 0 then 0
             else
               inf.to_i rescue nil
             end
    assert_nil result, '[ruby-dev:49423] [Bug #11804]'
  end

  def test_nil_safe_conditional_assign
    bug11816 = '[ruby-core:74993] [Bug #11816]'
    assert_ruby_status([], 'nil&.foo &&= false', bug11816)
  end
end

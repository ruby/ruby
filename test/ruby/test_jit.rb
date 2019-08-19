# frozen_string_literal: true
require 'test/unit'
require 'tmpdir'
require_relative '../lib/jit_support'

# Test for --jit option
class TestJIT < Test::Unit::TestCase
  include JITSupport

  # trace_* insns are not compiled for now...
  TEST_PENDING_INSNS = RubyVM::INSTRUCTION_NAMES.select { |n| n.start_with?('trace_') }.map(&:to_sym) + [
    # not supported yet
    :getblockparamproxy,
    :defineclass,
    :opt_call_c_function,

    # joke
    :bitblt,
    :answer,

    # TODO: write tests for them
    :reput,
    :tracecoverage,
  ]

  def self.untested_insns
    @untested_insns ||= (RubyVM::INSTRUCTION_NAMES.map(&:to_sym) - TEST_PENDING_INSNS)
  end

  def setup
    unless JITSupport.supported?
      skip 'JIT seems not supported on this platform'
    end

    # ruby -w -Itest/lib test/ruby/test_jit.rb
    if $VERBOSE && !defined?(@@at_exit_hooked)
      at_exit do
        unless TestJIT.untested_insns.empty?
          warn "untested insns are found!: #{TestJIT.untested_insns.join(' ')}"
        end
      end
      @@at_exit_hooked = true
    end
  end

  def test_compile_insn_nop
    assert_compile_once('nil rescue true', result_inspect: 'nil', insns: %i[nop])
  end

  def test_compile_insn_local
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '1', insns: %i[setlocal_WC_0 getlocal_WC_0])
    begin;
      foo = 1
      foo
    end;

    insns = %i[setlocal getlocal setlocal_WC_0 getlocal_WC_0 setlocal_WC_1 getlocal_WC_1]
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", success_count: 3, stdout: '168', insns: insns)
    begin;
      def foo
        a = 0
        [1, 2].each do |i|
          a += i
          [3, 4].each do |j|
            a *= j
          end
        end
        a
      end

      print foo
    end;
  end

  def test_compile_insn_blockparam
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '3', success_count: 2, insns: %i[getblockparam setblockparam])
    begin;
      def foo(&b)
        a = b
        b = 2
        a.call + 2
      end

      print foo { 1 }
    end;
  end

  def test_compile_insn_getblockparamproxy
    skip "support this in mjit_compile"
  end

  def test_compile_insn_getspecial
    assert_compile_once('$1', result_inspect: 'nil', insns: %i[getspecial])
  end

  def test_compile_insn_setspecial
    verbose_bak, $VERBOSE = $VERBOSE, nil
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: 'true', insns: %i[setspecial])
    begin;
      true if nil.nil?..nil.nil?
    end;
  ensure
    $VERBOSE = verbose_bak
  end

  def test_compile_insn_instancevariable
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '1', insns: %i[getinstancevariable setinstancevariable])
    begin;
      @foo = 1
      @foo
    end;
  end

  def test_compile_insn_classvariable
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '1', success_count: 1, insns: %i[getclassvariable setclassvariable])
    begin;
      class Foo
        def self.foo
          @@foo = 1
          @@foo
        end
      end

      print Foo.foo
    end;
  end

  def test_compile_insn_constant
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '1', insns: %i[getconstant setconstant])
    begin;
      FOO = 1
      FOO
    end;
  end

  def test_compile_insn_global
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '1', insns: %i[getglobal setglobal])
    begin;
      $foo = 1
      $foo
    end;
  end

  def test_compile_insn_putnil
    assert_compile_once('nil', result_inspect: 'nil', insns: %i[putnil])
  end

  def test_compile_insn_putself
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: 'hello', success_count: 1, insns: %i[putself])
    begin;
      proc { print "hello" }.call
    end;
  end

  def test_compile_insn_putobject
    assert_compile_once('0', result_inspect: '0', insns: %i[putobject_INT2FIX_0_])
    assert_compile_once('1', result_inspect: '1', insns: %i[putobject_INT2FIX_1_])
    assert_compile_once('2', result_inspect: '2', insns: %i[putobject])
  end

  def test_compile_insn_putspecialobject_putiseq
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: 'hello', success_count: 2, insns: %i[putspecialobject putiseq])
    begin;
      print proc {
        def method_definition
          'hello'
        end
        method_definition
      }.call
    end;
  end

  def test_compile_insn_putstring_concatstrings_tostring
    assert_compile_once('"a#{}b" + "c"', result_inspect: '"abc"', insns: %i[putstring concatstrings tostring])
  end

  def test_compile_insn_freezestring
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~'end;'}", stdout: 'true', success_count: 1, insns: %i[freezestring])
    begin;
      # frozen_string_literal: true
      print proc { "#{true}".frozen? }.call
    end;
  end

  def test_compile_insn_toregexp
    assert_compile_once('/#{true}/ =~ "true"', result_inspect: '0', insns: %i[toregexp])
  end

  def test_compile_insn_newarray
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '[1, 2, 3]', insns: %i[newarray])
    begin;
      a, b, c = 1, 2, 3
      [a, b, c]
    end;
  end

  def test_compile_insn_intern_duparray
    assert_compile_once('[:"#{0}"] + [1,2,3]', result_inspect: '[:"0", 1, 2, 3]', insns: %i[intern duparray])
  end

  def test_compile_insn_expandarray
    assert_compile_once('y = [ true, false, nil ]; x, = y; x', result_inspect: 'true', insns: %i[expandarray])
  end

  def test_compile_insn_concatarray
    assert_compile_once('["t", "r", *x = "u", "e"].join', result_inspect: '"true"', insns: %i[concatarray])
  end

  def test_compile_insn_splatarray
    assert_compile_once('[*(1..2)]', result_inspect: '[1, 2]', insns: %i[splatarray])
  end

  def test_compile_insn_newhash
    assert_compile_once('a = 1; { a: a }', result_inspect: '{:a=>1}', insns: %i[newhash])
  end

  def test_compile_insn_newrange
    assert_compile_once('a = 1; 0..a', result_inspect: '0..1', insns: %i[newrange])
  end

  def test_compile_insn_pop
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '1', insns: %i[pop])
    begin;
      a = false
      b = 1
      a || b
    end;
  end

  def test_compile_insn_dup
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '3', insns: %i[dup])
    begin;
      a = 1
      a&.+(2)
    end;
  end

  def test_compile_insn_dupn
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: 'true', insns: %i[dupn])
    begin;
      klass = Class.new
      klass::X ||= true
    end;
  end

  def test_compile_insn_swap_topn
    assert_compile_once('{}["true"] = true', result_inspect: 'true', insns: %i[swap topn])
  end

  def test_compile_insn_reverse
    assert_compile_once('q, (w, e), r = 1, [2, 3], 4; [q, w, e, r]', result_inspect: '[1, 2, 3, 4]', insns: %i[reverse])
  end

  def test_compile_insn_reput
    skip "write test"
  end

  def test_compile_insn_setn
    assert_compile_once('[nil][0] = 1', result_inspect: '1', insns: %i[setn])
  end

  def test_compile_insn_adjuststack
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: 'true', insns: %i[adjuststack])
    begin;
      x = [true]
      x[0] ||= nil
      x[0]
    end;
  end

  def test_compile_insn_defined
    assert_compile_once('defined?(a)', result_inspect: 'nil', insns: %i[defined])
  end

  def test_compile_insn_checkkeyword
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: 'true', success_count: 1, insns: %i[checkkeyword])
    begin;
      def test(x: rand)
        x
      end
      print test(x: true)
    end;
  end

  def test_compile_insn_tracecoverage
    skip "write test"
  end

  def test_compile_insn_defineclass
    skip "support this in mjit_compile (low priority)"
  end

  def test_compile_insn_send
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '1', success_count: 2, insns: %i[send])
    begin;
      print proc { yield_self { 1 } }.call
    end;
  end

  def test_compile_insn_opt_str_freeze
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '"foo"', insns: %i[opt_str_freeze])
    begin;
      'foo'.freeze
    end;
  end

  def test_compile_insn_opt_str_uminus
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '"bar"', insns: %i[opt_str_uminus])
    begin;
      -'bar'
    end;
  end

  def test_compile_insn_opt_newarray_max
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '2', insns: %i[opt_newarray_max])
    begin;
      a = 1
      b = 2
      [a, b].max
    end;
  end

  def test_compile_insn_opt_newarray_min
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '1', insns: %i[opt_newarray_min])
    begin;
      a = 1
      b = 2
      [a, b].min
    end;
  end

  def test_compile_insn_opt_send_without_block
    assert_compile_once('print', result_inspect: 'nil', insns: %i[opt_send_without_block])
  end

  def test_compile_insn_invokesuper
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '3', success_count: 4, insns: %i[invokesuper])
    begin;
      mod = Module.new {
        def test
          super + 2
        end
      }
      klass = Class.new {
        prepend mod
        def test
          1
        end
      }
      print klass.new.test
    end;
  end

  def test_compile_insn_invokeblock_leave
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '2', success_count: 2, insns: %i[invokeblock leave])
    begin;
      def foo
        yield
      end
      print foo { 2 }
    end;
  end

  def test_compile_insn_throw
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '4', success_count: 2, insns: %i[throw])
    begin;
      def test
        proc do
          if 1+1 == 1
            return 3
          else
            return 4
          end
          5
        end.call
      end
      print test
    end;
  end

  def test_compile_insn_jump_branchif
    assert_compile_once("#{<<~"begin;"}\n#{<<~'end;'}", result_inspect: 'nil', insns: %i[jump branchif])
    begin;
      a = false
      1 + 1 while a
    end;
  end

  def test_compile_insn_branchunless
    assert_compile_once("#{<<~"begin;"}\n#{<<~'end;'}", result_inspect: '1', insns: %i[branchunless])
    begin;
      a = true
      if a
        1
      else
        2
      end
    end;
  end

  def test_compile_insn_branchnil
    assert_compile_once("#{<<~"begin;"}\n#{<<~'end;'}", result_inspect: '3', insns: %i[branchnil])
    begin;
      a = 2
      a&.+(1)
    end;
  end

  def test_compile_insn_checktype
    assert_compile_once("#{<<~"begin;"}\n#{<<~'end;'}", result_inspect: '"42"', insns: %i[checktype])
    begin;
      a = '2'
      "4#{a}"
    end;
  end

  def test_compile_insn_inlinecache
    assert_compile_once('Struct', result_inspect: 'Struct', insns: %i[getinlinecache setinlinecache])
  end

  def test_compile_insn_once
    assert_compile_once('/#{true}/o =~ "true" && $~.to_a', result_inspect: '["true"]', insns: %i[once])
  end

  def test_compile_insn_checkmatch_opt_case_dispatch
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '"world"', insns: %i[checkmatch opt_case_dispatch])
    begin;
      case 'hello'
      when 'hello'
        'world'
      end
    end;
  end

  def test_compile_insn_opt_calc
    assert_compile_once('4 + 2 - ((2 * 3 / 2) % 2)', result_inspect: '5', insns: %i[opt_plus opt_minus opt_mult opt_div opt_mod])
    assert_compile_once('4 + 2', result_inspect: '6')
  end

  def test_compile_insn_opt_cmp
    assert_compile_once('(1 == 1) && (1 != 2)', result_inspect: 'true', insns: %i[opt_eq opt_neq])
  end

  def test_compile_insn_opt_rel
    assert_compile_once('1 < 2 && 1 <= 1 && 2 > 1 && 1 >= 1', result_inspect: 'true', insns: %i[opt_lt opt_le opt_gt opt_ge])
  end

  def test_compile_insn_opt_ltlt
    assert_compile_once('[1] << 2', result_inspect: '[1, 2]', insns: %i[opt_ltlt])
  end

  def test_compile_insn_opt_aref
    # optimized call (optimized JIT) -> send call
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '21', success_count: 2, min_calls: 1, insns: %i[opt_aref])
    begin;
      obj = Object.new
      def obj.[](h)
        h
      end

      block = proc { |h| h[1] }
      print block.call({ 1 => 2 })
      print block.call(obj)
    end;

    # send call -> optimized call (send JIT) -> optimized call
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '122', success_count: 1, min_calls: 2)
    begin;
      obj = Object.new
      def obj.[](h)
        h
      end

      block = proc { |h| h[1] }
      print block.call(obj)
      print block.call({ 1 => 2 })
      print block.call({ 1 => 2 })
    end;
  end

  def test_compile_insn_opt_aref_with
    assert_compile_once("{ '1' => 2 }['1']", result_inspect: '2', insns: %i[opt_aref_with])
  end

  def test_compile_insn_opt_aset
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '5', insns: %i[opt_aset opt_aset_with])
    begin;
      hash = { '1' => 2 }
      (hash['2'] = 2) + (hash[1.to_s] = 3)
    end;
  end

  def test_compile_insn_opt_length_size
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '4', insns: %i[opt_length opt_size])
    begin;
      array = [1, 2]
      array.length + array.size
    end;
  end

  def test_compile_insn_opt_empty_p
    assert_compile_once('[].empty?', result_inspect: 'true', insns: %i[opt_empty_p])
  end

  def test_compile_insn_opt_succ
    assert_compile_once('1.succ', result_inspect: '2', insns: %i[opt_succ])
  end

  def test_compile_insn_opt_not
    assert_compile_once('!!true', result_inspect: 'true', insns: %i[opt_not])
  end

  def test_compile_insn_opt_regexpmatch1
    assert_compile_once("/true/ =~ 'true'", result_inspect: '0', insns: %i[opt_regexpmatch1])
  end

  def test_compile_insn_opt_regexpmatch2
    assert_compile_once("'true' =~ /true/", result_inspect: '0', insns: %i[opt_regexpmatch2])
  end

  def test_compile_insn_opt_call_c_function
    skip "support this in opt_call_c_function (low priority)"
  end

  def test_jit_output
    out, err = eval_with_jit('5.times { puts "MJIT" }', verbose: 1, min_calls: 5)
    assert_equal("MJIT\n" * 5, out)
    assert_match(/^#{JIT_SUCCESS_PREFIX}: block in <main>@-e:1 -> .+_ruby_mjit_p\d+u\d+\.c$/, err)
    assert_match(/^Successful MJIT finish$/, err)
  end

  def test_local_stack_on_exception
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '3', success_count: 2)
    begin;
      def b
        raise
      rescue
        2
      end

      def a
        # Calling #b should be vm_exec, not direct mjit_exec.
        # Otherwise `1` on local variable would be purged.
        1 + b
      end

      print a
    end;
  end

  def test_local_stack_with_sp_motion_by_blockargs
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '1', success_count: 2)
    begin;
      def b(base)
        1
      end

      # This method is simple enough to have false in catch_except_p.
      # So local_stack_p would be true in JIT compiler.
      def a
        m = method(:b)

        # ci->flag has VM_CALL_ARGS_BLOCKARG and cfp->sp is moved in vm_caller_setup_arg_block.
        # So, for this send insn, JIT-ed code should use cfp->sp instead of local variables for stack.
        Module.module_eval(&m)
      end

      print a
    end;
  end

  def test_catching_deep_exception
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '1', success_count: 4)
    begin;
      def catch_true(paths, prefixes) # catch_except_p: TRUE
        prefixes.each do |prefix| # catch_except_p: TRUE
          paths.each do |path| # catch_except_p: FALSE
            return path
          end
        end
      end

      def wrapper(paths, prefixes)
        catch_true(paths, prefixes)
      end

      print wrapper(['1'], ['2'])
    end;
  end

  def test_attr_reader
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: "4nil\nnil\n6", success_count: 2, min_calls: 2)
    begin;
      class A
        attr_reader :a, :b

        def initialize
          @a = 2
        end

        def test
          a
        end

        def undefined
          b
        end
      end

      a = A.new
      print(a.test * a.test)
      p(a.undefined)
      p(a.undefined)

      # redefinition
      class A
        def test
          3
        end
      end

      print(2 * a.test)
    end;

    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: "true", success_count: 1, min_calls: 2)
    begin;
      class Hoge
        attr_reader :foo

        def initialize
          @foo = []
          @bar = nil
        end
      end

      class Fuga < Hoge
        def initialize
          @bar = nil
          @foo = []
        end
      end

      def test(recv)
        recv.foo.empty?
      end

      hoge = Hoge.new
      fuga = Fuga.new

      test(hoge) # VM: cc set index=1
      test(hoge) # JIT: compile with index=1
      test(fuga) # JIT -> VM: cc set index=2
      print test(hoge) # JIT: should use index=1, not index=2 in cc
    end;
  end

  def test_clean_so
    Dir.mktmpdir("jit_test_clean_so_") do |dir|
      code = "x = 0; 10.times {|i|x+=i}"
      eval_with_jit({"TMPDIR"=>dir}, code)
      assert_send([Dir, :empty?, dir])
      eval_with_jit({"TMPDIR"=>dir}, code, save_temps: true)
      assert_not_send([Dir, :empty?, dir])
    end
  end

  def test_lambda_longjmp
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '5', success_count: 1)
    begin;
      fib = lambda do |x|
        return x if x == 0 || x == 1
        fib.call(x-1) + fib.call(x-2)
      end
      print fib.call(5)
    end;
  end

  private

  # The shortest way to test one proc
  def assert_compile_once(script, result_inspect:, insns: [])
    if script.match?(/\A\n.+\n\z/m)
      script = script.gsub(/^/, '  ')
    else
      script = " #{script} "
    end
    assert_eval_with_jit("p proc {#{script}}.call", stdout: "#{result_inspect}\n", success_count: 1, insns: insns, uplevel: 2)
  end

  # Shorthand for normal test cases
  def assert_eval_with_jit(script, stdout: nil, success_count:, min_calls: 1, insns: [], uplevel: 3)
    out, err = eval_with_jit(script, verbose: 1, min_calls: min_calls)
    actual = err.scan(/^#{JIT_SUCCESS_PREFIX}:/).size

    # Debugging on CI
    if err.include?("error trying to exec 'cc1': execvp: No such file or directory") && RbConfig::CONFIG['CC'].start_with?('gcc')
      $stderr.puts "\ntest/ruby/test_jit.rb: DEBUG OUTPUT:"
      cc1 = %x`gcc -print-prog-name=cc1`.rstrip
      if $?.success?
        $stderr.puts "cc1 path: #{cc1}"
        $stderr.puts "executable?: #{File.executable?(cc1)}"
        $stderr.puts "ls:\n#{IO.popen(['ls', '-la', File.dirname(cc1)], &:read)}"
      else
        $stderr.puts 'Failed to fetch cc1 path'
      end
    end

    # Make sure that the script has insns expected to be tested
    used_insns = method_insns(script)
    insns.each do |insn|
      unless used_insns.include?(insn)
        $stderr.puts
        warn "'#{insn}' insn is not included in the script. Actual insns are: #{used_insns.join(' ')}\n", uplevel: uplevel
      end
      TestJIT.untested_insns.delete(insn)
    end

    assert_equal(
      success_count, actual,
      "Expected #{success_count} times of JIT success, but succeeded #{actual} times.\n\n"\
      "script:\n#{code_block(script)}\nstderr:\n#{code_block(err)}",
    )
    if stdout
      assert_equal(stdout, out, "Expected stdout #{out.inspect} to match #{stdout.inspect} with script:\n#{code_block(script)}")
    end
    err_lines = err.lines.reject! { |l| l.chomp.empty? || l.match?(/\A#{JIT_SUCCESS_PREFIX}/) || l == "Successful MJIT finish\n" }
    unless err_lines.empty?
      warn err_lines.join(''), uplevel: uplevel
    end
  end

  # Collect block's insns or defined method's insns, which are expected to be JIT-ed.
  # Note that this intentionally excludes insns in script's toplevel because they are not JIT-ed.
  def method_insns(script)
    insns = []
    RubyVM::InstructionSequence.compile(script).to_a.last.each do |(insn, *args)|
      case insn
      when :putiseq, :send
        insns += collect_insns(args.last)
      when :defineclass
        insns += collect_insns(args[1])
      end
    end
    insns.uniq
  end

  # Recursively collect insns in iseq_array
  def collect_insns(iseq_array)
    return [] if iseq_array.nil?

    insns = iseq_array.last.select { |x| x.is_a?(Array) }.map(&:first)
    iseq_array.last.each do |(insn, *args)|
      case insn
      when :putiseq, :send
        insns += collect_insns(args.last)
      end
    end
    insns
  end

  # Run Ruby script with --jit-wait (Synchronous JIT compilation).
  # Returns [stdout, stderr]
  def eval_with_jit(env = nil, script, **opts)
    stdout, stderr, status = super
    assert_equal(true, status.success?, "Failed to run script with JIT:\n#{code_block(script)}\nstdout:\n#{code_block(stdout)}\nstderr:\n#{code_block(stderr)}")
    [stdout, stderr]
  end

  def code_block(code)
    "```\n#{code}\n```\n\n"
  end
end

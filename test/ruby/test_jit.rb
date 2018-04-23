# frozen_string_literal: true
require 'test/unit'
require_relative '../lib/jit_support'

# Test for --jit option
class TestJIT < Test::Unit::TestCase
  include JITSupport
  # Ensure all supported insns can be compiled. Only basic tests are included.
  # TODO: ensure --dump=insns includes the expected insn

  def setup
    unless JITSupport.supported?
      skip 'JIT seems not supported on this platform'
    end
  end

  def test_compile_insn_nop
    assert_compile_once('nil rescue true', result_inspect: 'nil')
  end

  def test_compile_insn_local
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '1')
    begin;
      foo = 1
      foo
    end;
  end

  def test_compile_insn_blockparam
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '3', success_count: 2)
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
    assert_compile_once('$1', result_inspect: 'nil')
  end

  def test_compile_insn_setspecial
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: 'true')
    begin;
      true if nil.nil?..nil.nil?
    end;
  end

  def test_compile_insn_instancevariable
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '1')
    begin;
      @foo = 1
      @foo
    end;
  end

  def test_compile_insn_classvariable
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '1')
    begin;
      @@foo = 1
      @@foo
    end;
  end

  def test_compile_insn_constant
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '1')
    begin;
      FOO = 1
      FOO
    end;
  end

  def test_compile_insn_global
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '1')
    begin;
      $foo = 1
      $foo
    end;
  end

  def test_compile_insn_putnil
    assert_compile_once('nil', result_inspect: 'nil')
  end

  def test_compile_insn_putself
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: 'hello', success_count: 1)
    begin;
      proc { print "hello" }.call
    end;
  end

  def test_compile_insn_putobject
    assert_compile_once('0', result_inspect: '0') # putobject_OP_INT2FIX_O_0_C_
    assert_compile_once('1', result_inspect: '1') # putobject_OP_INT2FIX_O_1_C_
    assert_compile_once('2', result_inspect: '2')
  end

  def test_compile_insn_putspecialobject_putiseq
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: 'hello', success_count: 2)
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
    assert_compile_once('"a#{}b" + "c"', result_inspect: '"abc"')
  end

  def test_compile_insn_freezestring
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~'end;'}", stdout: 'true', success_count: 1)
    begin;
      # frozen_string_literal: true
      print proc { "#{true}".frozen? }.call
    end;
  end

  def test_compile_insn_toregexp
    assert_compile_once('/#{true}/ =~ "true"', result_inspect: '0')
  end

  def test_compile_insn_newarray
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '[1, 2, 3]')
    begin;
      a, b, c = 1, 2, 3
      [a, b, c]
    end;
  end

  def test_compile_insn_intern_duparray
    assert_compile_once('[:"#{0}"] + [1,2,3]', result_inspect: '[:"0", 1, 2, 3]')
  end

  def test_compile_insn_expandarray
    assert_compile_once('y = [ true, false, nil ]; x, = y; x', result_inspect: 'true')
  end

  def test_compile_insn_concatarray
    assert_compile_once('["t", "r", *x = "u", "e"].join', result_inspect: '"true"')
  end

  def test_compile_insn_splatarray
    assert_compile_once('[*(1..2)]', result_inspect: '[1, 2]')
  end

  def test_compile_insn_newhash
    assert_compile_once('a = 1; { a: a }', result_inspect: '{:a=>1}')
  end

  def test_compile_insn_newrange
    assert_compile_once('a = 1; 0..a', result_inspect: '0..1')
  end

  def test_compile_insn_pop
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '1')
    begin;
      a = false
      b = 1
      a || b
    end;
  end

  def test_compile_insn_dup
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '3')
    begin;
      a = 1
      a&.+(2)
    end;
  end

  def test_compile_insn_dupn
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: 'true')
    begin;
      klass = Class.new
      klass::X ||= true
    end;
  end

  def test_compile_insn_swap_topn
    assert_compile_once('{}["true"] = true', result_inspect: 'true')
  end

  def test_compile_insn_reverse
    assert_compile_once('q, (w, e), r = 1, [2, 3], 4; e == 3', result_inspect: 'true')
  end

  def test_compile_insn_reput
    skip "write test"
  end

  def test_compile_insn_setn
    assert_compile_once('[nil][0] = 1', result_inspect: '1')
  end

  def test_compile_insn_adjuststack
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: 'true')
    begin;
      x = [true]
      x[0] ||= nil
      x[0]
    end;
  end

  def test_compile_insn_defined
    assert_compile_once('defined?(a)', result_inspect: 'nil')
  end

  def test_compile_insn_checkkeyword
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: 'true', success_count: 1)
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
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '1', success_count: 2)
    begin;
      print proc { yield_self { 1 } }.call
    end;
  end

  def test_compile_insn_opt_str_freeze
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '"foo"')
    begin;
      'foo'.freeze
    end;
  end

  def test_compile_insn_opt_str_uminus
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '"bar"')
    begin;
      -'bar'
    end;
  end

  def test_compile_insn_opt_newarray_max
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '2')
    begin;
      a = 1
      b = 2
      [a, b].max
    end;
  end

  def test_compile_insn_opt_newarray_min
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '1')
    begin;
      a = 1
      b = 2
      [a, b].min
    end;
  end

  def test_compile_insn_opt_send_without_block
    assert_compile_once('print', result_inspect: 'nil')
  end

  def test_compile_insn_invokesuper
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '3', success_count: 4)
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
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '2', success_count: 2)
    begin;
      def foo
        yield
      end
      print foo { 2 }
    end;
  end

  def test_compile_insn_throw
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '4', success_count: 2)
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
    assert_compile_once("#{<<~"begin;"}\n#{<<~'end;'}", result_inspect: 'nil')
    begin;
      a = false
      1 + 1 while false
    end;
  end

  def test_compile_insn_branchunless
    assert_compile_once("#{<<~"begin;"}\n#{<<~'end;'}", result_inspect: '1')
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
    assert_compile_once("#{<<~"begin;"}\n#{<<~'end;'}", result_inspect: '3')
    begin;
      a = 2
      a&.+(1)
    end;
  end

  def test_compile_insn_checktype
    assert_compile_once("#{<<~"begin;"}\n#{<<~'end;'}", result_inspect: '"42"')
    begin;
      a = '2'
      "4#{a}"
    end;
  end

  def test_compile_insn_inlinecache
    assert_compile_once('Struct', result_inspect: 'Struct')
  end

  def test_compile_insn_once
    assert_compile_once('/#{true}/o =~ "true" && $~.to_a', result_inspect: '["true"]')
  end

  def test_compile_insn_checkmatch_opt_case_dispatch
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '"world"')
    begin;
      case 'hello'
      when /hello/
        'world'
      end
    end;
  end

  def test_compile_insn_opt_calc
    assert_compile_once('4 + 2 - ((2 * 3 / 2) % 2)', result_inspect: '5')
    assert_compile_once('4 + 2', result_inspect: '6')
  end

  def test_compile_insn_opt_cmp
    assert_compile_once('(1 == 1) && (1 != 2)', result_inspect: 'true')
  end

  def test_compile_insn_opt_rel
    assert_compile_once('1 < 2 && 1 <= 1 && 2 > 1 && 1 >= 1', result_inspect: 'true')
  end

  def test_compile_insn_opt_ltlt
    assert_compile_once('[1] << 2', result_inspect: '[1, 2]')
  end

  def test_compile_insn_opt_aref
    # optimized call (optimized JIT) -> send call
    assert_eval_with_jit("#{<<~"begin;"}\n#{<<~"end;"}", stdout: '21', success_count: 2, min_calls: 1)
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

  def test_compile_insn_opt_aset
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '5')
    begin;
      hash = { '1' => 2 }
      (hash['2'] = 2) + (hash[1.to_s] = 3)
    end;
  end

  def test_compile_insn_opt_length_size
    assert_compile_once("#{<<~"begin;"}\n#{<<~"end;"}", result_inspect: '4')
    begin;
      array = [1, 2]
      array.length + array.size
    end;
  end

  def test_compile_insn_opt_empty_p
    assert_compile_once('[].empty?', result_inspect: 'true')
  end

  def test_compile_insn_opt_succ
    assert_compile_once('1.succ', result_inspect: '2')
  end

  def test_compile_insn_opt_not
    assert_compile_once('!!true', result_inspect: 'true')
  end

  def test_compile_insn_opt_regexpmatch1
    assert_compile_once("/true/ =~ 'true'", result_inspect: '0')
  end

  def test_compile_insn_opt_regexpmatch2
    assert_compile_once("'true' =~ /true/", result_inspect: '0')
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
  end

  private

  # The shortest way to test one proc
  def assert_compile_once(script, result_inspect:)
    if script.match?(/\A\n.+\n\z/m)
      script = script.gsub(/^/, '  ')
    else
      script = " #{script} "
    end
    assert_eval_with_jit("p proc {#{script}}.call", stdout: "#{result_inspect}\n", success_count: 1)
  end

  # Shorthand for normal test cases
  def assert_eval_with_jit(script, stdout: nil, success_count:, min_calls: 1)
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

    assert_equal(
      success_count, actual,
      "Expected #{success_count} times of JIT success, but succeeded #{actual} times.\n\n"\
      "script:\n#{code_block(script)}\nstderr:\n#{code_block(err)}",
    )
    if stdout
      assert_equal(stdout, out, "Expected stdout #{out.inspect} to match #{stdout.inspect} with script:\n#{code_block(script)}")
    end
  end

  # Run Ruby script with --jit-wait (Synchronous JIT compilation).
  # Returns [stdout, stderr]
  def eval_with_jit(script, **opts)
    stdout, stderr, status = super
    assert_equal(true, status.success?, "Failed to run script with JIT:\n#{code_block(script)}\nstdout:\n#{code_block(stdout)}\nstderr:\n#{code_block(stderr)}")
    [stdout, stderr]
  end

  def code_block(code)
    "```\n#{code}\n```\n\n"
  end
end

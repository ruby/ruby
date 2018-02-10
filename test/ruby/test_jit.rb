# frozen_string_literal: true
require 'test/unit'

# Test for --jit option
class TestJIT < Test::Unit::TestCase
  JIT_TIMEOUT = 600 # 10min for each...
  JIT_SUCCESS_PREFIX = 'JIT success \(\d+\.\dms\)'
  SUPPORTED_COMPILERS = [
    'gcc',
    'clang',
  ]

  # Ensure all supported insns can be compiled. Only basic tests are included.
  # TODO: ensure --dump=insns includes the expected insn
  def test_compile_insns
    skip unless jit_supported?

    # nop
    assert_compile_once('nil rescue true', result_inspect: 'nil')

    # getlocal
    # setlocal
    assert_compile_once(<<~RUBY, result_inspect: '1')
      foo = 1
      foo
    RUBY

    # getblockparam
    # setblockparam
    assert_eval_with_jit(<<~RUBY, stdout: '3', success_count: 2)
      def foo(&b)
        a = b
        b = 2
        a.call + 2
      end

      print foo { 1 }
    RUBY

    # getblockparamproxy
    # TODO: support this in mjit_compile

    # getspecial
    assert_compile_once('$1', result_inspect: 'nil')

    # setspecial
    assert_compile_once(<<~RUBY, result_inspect: 'true')
      true if nil.nil?..nil.nil?
    RUBY

    # getinstancevariable
    # setinstancevariable
    assert_compile_once(<<~RUBY, result_inspect: '1')
      @foo = 1
      @foo
    RUBY

    # getclassvariable
    # setclassvariable
    assert_compile_once(<<~RUBY, result_inspect: '1')
      @@foo = 1
      @@foo
    RUBY

    # getconstant
    # setconstant
    assert_compile_once(<<~RUBY, result_inspect: '1')
      FOO = 1
      FOO
    RUBY

    # getglobal
    # setglobal
    assert_compile_once(<<~RUBY, result_inspect: '1')
      $foo = 1
      $foo
    RUBY

    # putnil
    assert_compile_once('nil', result_inspect: 'nil')

    # putself
    assert_eval_with_jit(<<~RUBY, stdout: 'hello', success_count: 1)
      proc { print "hello" }.call
    RUBY

    # putobject
    assert_compile_once('0', result_inspect: '0') # putobject_OP_INT2FIX_O_0_C_
    assert_compile_once('1', result_inspect: '1') # putobject_OP_INT2FIX_O_1_C_
    assert_compile_once('2', result_inspect: '2')

    # putspecialobject
    # putiseq
    assert_eval_with_jit(<<~RUBY, stdout: 'hello', success_count: 2)
      print proc {
        def method_definition
          'hello'
        end
        method_definition
      }.call
    RUBY

    # putstring
    # concatstrings
    # tostring
    assert_compile_once('"a#{}b" + "c"', result_inspect: '"abc"')

    # freezestring
    assert_eval_with_jit(<<~'RUBY', stdout: 'true', success_count: 1)
      # frozen_string_literal: true
      print proc { "#{true}".frozen? }.call
    RUBY

    # toregexp
    assert_compile_once('/#{true}/ =~ "true"', result_inspect: '0')

    # intern
    # newarray
    # duparray
    assert_compile_once('[:"#{0}"] + [1,2,3]', result_inspect: '[:"0", 1, 2, 3]')

    # expandarray
    assert_compile_once('y = [ true, false, nil ]; x, = y; x', result_inspect: 'true')

    # concatarray
    assert_compile_once('["t", "r", *x = "u", "e"].join', result_inspect: '"true"')

    # splatarray
    assert_compile_once('[*(1..2)]', result_inspect: '[1, 2]')

    # newhash
    assert_compile_once('a = 1; { a: a }', result_inspect: '{:a=>1}')

    # newrange
    assert_compile_once('a = 1; 0..a', result_inspect: '0..1')

    # pop
    assert_compile_once(<<~RUBY, result_inspect: '1')
      a = false
      b = 1
      a || b
    RUBY

    # dup
    assert_compile_once(<<~RUBY, result_inspect: '3')
      a = 1
      a&.+(2)
    RUBY

    # dupn
    assert_compile_once(<<~RUBY, result_inspect: 'true')
      klass = Class.new
      klass::X ||= true
    RUBY

    # swap
    # topn
    assert_compile_once('{}["true"] = true', result_inspect: 'true')

    # reverse
    assert_compile_once('q, (w, e), r = 1, [2, 3], 4; e == 3', result_inspect: 'true')

    # reput
    # TODO: write test

    # setn
    assert_compile_once('[nil][0] = 1', result_inspect: '1')

    # adjuststack
    assert_compile_once(<<~RUBY, result_inspect: 'true')
      x = [true]
      x[0] ||= nil
      x[0]
    RUBY

    # defined
    assert_compile_once('defined?(a)', result_inspect: 'nil')

    # checkkeyword
    assert_eval_with_jit(<<~RUBY, stdout: 'true', success_count: 1)
      def test(x: rand)
        x
      end
      print test(x: true)
    RUBY

    # tracecoverage
    # TODO: write test

    # defineclass
    # TODO: support this in mjit_compile (low priority)

    # send
    assert_eval_with_jit(<<~RUBY, stdout: '1', success_count: 2)
      print proc { yield_self { 1 } }.call
    RUBY

    # opt_str_freeze
    # opt_str_uminus
    assert_compile_once(<<~RUBY, result_inspect: '"foobar"')
      'foo'.freeze + -'bar'
    RUBY

    # opt_newarray_max
    # opt_newarray_min
    assert_compile_once(<<~RUBY, result_inspect: '3')
      a = 1
      b = 2
      [a, b].max + [a, b].min
    RUBY

    # opt_send_without_block
    assert_compile_once('print', result_inspect: 'nil')

    # invokesuper
    assert_eval_with_jit(<<~RUBY, stdout: '3', success_count: 4)
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
    RUBY

    # invokeblock
    # leave
    assert_eval_with_jit(<<~RUBY, stdout: '2', success_count: 2)
      def foo
        yield
      end
      print foo { 2 }
    RUBY

    # throw
    assert_eval_with_jit(<<~RUBY, stdout: '4', success_count: 2)
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
    RUBY

    # jump
    # branchif
    assert_compile_once(<<~'RUBY', result_inspect: 'nil')
      a = false
      1 + 1 while false
    RUBY

    # branchunless
    assert_compile_once(<<~'RUBY', result_inspect: '1')
      a = true
      if a
        1
      else
        2
      end
    RUBY

    # branchnil
    assert_compile_once(<<~'RUBY', result_inspect: '3')
      a = 2
      a&.+(1)
    RUBY

    # branchiftype
    assert_compile_once(<<~'RUBY', result_inspect: '"42"')
      a = '2'
      "4#{a}"
    RUBY

    # getinlinecache
    # setinlinecache
    assert_compile_once('Struct', result_inspect: 'Struct')

    # once
    assert_compile_once('/#{true}/o =~ "true" && $~.to_a', result_inspect: '["true"]')

    # checkmatch
    # opt_case_dispatch
    assert_compile_once(<<~RUBY, result_inspect: '"world"')
      case 'hello'
      when /hello/
        'world'
      end
    RUBY

    # opt_plus
    # opt_minus
    # opt_mult
    # opt_div
    # opt_mod
    assert_compile_once('4 + 2 - ((2 * 3 / 2) % 2)', result_inspect: '5')

    # opt_eq
    # opt_neq
    assert_compile_once('(1 == 1) && (1 != 2)', result_inspect: 'true')

    # opt_lt
    # opt_le
    # opt_gt
    # opt_ge
    assert_compile_once('1 < 2 && 1 <= 1 && 2 > 1 && 1 >= 1', result_inspect: 'true')

    # opt_ltlt
    assert_compile_once('[1] << 2', result_inspect: '[1, 2]')

    # opt_aref
    # opt_aset
    # opt_aset_with
    # opt_aref_with
    assert_compile_once(<<~RUBY, result_inspect: '8')
      hash = { '1' => 2 }
      hash['1'] + hash[1.to_s] + (hash['2'] = 2) + (hash[2.to_s] = 2)
    RUBY

    # opt_length
    # opt_size
    assert_compile_once(<<~RUBY, result_inspect: '4')
      array = [1, 2]
      array.size + array.length
    RUBY

    # opt_empty_p
    assert_compile_once('[].empty?', result_inspect: 'true')

    # opt_succ
    assert_compile_once('1.succ', result_inspect: '2')

    # opt_not
    assert_compile_once('!!true', result_inspect: 'true')

    # opt_regexpmatch1
    assert_compile_once("/true/ =~ 'true'", result_inspect: '0')

    # opt_regexpmatch2
    assert_compile_once("'true' =~ /true/", result_inspect: '0')

    # opt_call_c_function
    # TODO: support this in opt_call_c_function (low priority)
  end

  def test_jit_output
    skip unless jit_supported?

    out, err = eval_with_jit('5.times { puts "MJIT" }', verbose: 1, min_calls: 5)
    assert_equal("MJIT\n" * 5, out)
    assert_match(/^#{JIT_SUCCESS_PREFIX}: block in <main>@-e:1 -> .+_ruby_mjit_p\d+u\d+\.c$/, err)
    assert_match(/^Successful MJIT finish$/, err)
  end

  private

  # The shortest way to test one proc
  def assert_compile_once(script, result_inspect:)
    assert_eval_with_jit("p proc { #{script} }.call", stdout: "#{result_inspect}\n", success_count: 1)
  end

  # Shorthand for normal test cases
  def assert_eval_with_jit(script, stdout: nil, success_count:)
    out, err = eval_with_jit(script, verbose: 1, min_calls: 1)
    if jit_supported?
      actual = err.scan(/^#{JIT_SUCCESS_PREFIX}:/).size
      assert_equal(
        success_count, actual,
        "Expected #{success_count} times of JIT success, but succeeded #{actual} times.\n\n"\
        "script:\n#{code_block(script)}\nstderr:\n#{code_block(err)}",
      )
    end
    if stdout
      assert_equal(stdout, out, "Expected stdout #{out.inspect} to match #{stdout.inspect} with script:\n#{code_block(script)}")
    end
  end

  # Run Ruby script with --jit-wait (Synchronous JIT compilation).
  # Returns [stdout, stderr]
  def eval_with_jit(script, verbose: 0, min_calls: 5, timeout: JIT_TIMEOUT)
    stdout, stderr, status = EnvUtil.invoke_ruby(
      ['--disable-gems', '--jit-wait', "--jit-verbose=#{verbose}", "--jit-min-calls=#{min_calls}", '-e', script],
      '', true, true, timeout: timeout,
    )
    assert_equal(true, status.success?, "Failed to run script with JIT:\n#{code_block(script)}\nstdout:\n#{code_block(stdout)}\nstderr:\n#{code_block(stderr)}")
    [stdout, stderr]
  end

  def code_block(code)
    "```\n#{code}\n```\n\n"
  end

  def jit_supported?
    return @jit_supported if defined?(@jit_supported)

    # Experimental. If you want to ensure JIT is working with this test, please set this for now.
    if ENV.key?('RUBY_FORCE_TEST_JIT')
      return @jit_supported = true
    end

    # Very pessimistic check. With this check, we can't ensure JIT is working.
    begin
      _, err = eval_with_jit('proc {}.call', verbose: 1, min_calls: 1, timeout: 10)
      @jit_supported = err.match?(JIT_SUCCESS_PREFIX)
    rescue Timeout::Error
      $stderr.puts "TestJIT: #jit_supported? check timed out"
      @jit_supported = false
    end
  end
end

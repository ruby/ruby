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

  def test_jit
    assert_eval_with_jit('print proc { 1 + 1 }.call', stdout: '2', success_count: 1)
  end

  def test_jit_output
    skip unless jit_supported?

    out, err = eval_with_jit('5.times { puts "MJIT" }', verbose: 1, min_calls: 5)
    assert_equal("MJIT\n" * 5, out)
    assert_match(/^#{JIT_SUCCESS_PREFIX}: block in <main>@-e:1 -> .+_ruby_mjit_p\d+u\d+\.c$/, err)
    assert_match(/^Successful MJIT finish$/, err)
  end

  private

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
      assert_match(stdout, out, "Expected stderr #{out.inspect} to match #{stdout.inspect} with script:\n#{code_block(script)}")
    end
  end

  # Run Ruby script with --jit-wait (Synchronous JIT compilation).
  # Returns [stdout, stderr]
  def eval_with_jit(script, verbose: 0, min_calls: 5)
    stdout, stderr, status = EnvUtil.invoke_ruby(
      ['--disable-gems', '--jit-wait', "--jit-verbose=#{verbose}", "--jit-min-calls=#{min_calls}", '-e', script],
      '', true, true, timeout: JIT_TIMEOUT,
    )
    assert_equal(true, status.success?, "Failed to run script with JIT:\n#{code_block(script)}")
    [stdout, stderr]
  end

  def code_block(code)
    "```\n#{code}\n```\n\n"
  end

  # If this is false, tests which require JIT should be skipped.
  # When this is not checked, probably the test expects Ruby to behave in the same way even if JIT is not supported.
  def jit_supported?
    return @jit_supported if defined?(@jit_supported)

    out = IO.popen("#{RbConfig::CONFIG['CC']} --version", err: [:child, :out], &:read)
    @jit_supported = $?.success? && SUPPORTED_COMPILERS.any? { |cc| out.match(/\b#{Regexp.escape(cc)}\b/) }
  end
end

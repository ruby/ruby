# frozen_string_literal: true
#
# This set of tests can be run with:
# make test-all TESTS=test/ruby/test_zjit.rb

require 'test/unit'
require 'envutil'
require_relative '../lib/jit_support'
return unless JITSupport.zjit_supported?

class TestZJIT < Test::Unit::TestCase
  def test_nil
    assert_compiles 'nil', %q{
      def test = nil
      test
    }
  end

  def test_putobject
    assert_compiles '1', %q{
      def test = 1
      test
    }
  end

  def test_leave_param
    assert_compiles '5', %q{
      def test(n) = n
      test(5)
    }
  end

  def test_setlocal
    assert_compiles '3', %q{
      def test(n)
        m = n
        m
      end
      test(3)
    }
  end

  def test_opt_plus_const
    assert_compiles '3', %q{
      def test = 1 + 2
      test # profile opt_plus
      test
    }, call_threshold: 2
  end

  def test_opt_plus_fixnum
    assert_compiles '3', %q{
      def test(a, b) = a + b
      test(0, 1) # profile opt_plus
      test(1, 2)
    }, call_threshold: 2
  end

  def test_opt_plus_chain
    assert_compiles '6', %q{
      def test(a, b, c) = a + b + c
      test(0, 1, 2) # profile opt_plus
      test(1, 2, 3)
    }, call_threshold: 2
  end

  # Test argument ordering
  def test_opt_minus
    assert_compiles '2', %q{
      def test(a, b) = a - b
      test(2, 1) # profile opt_minus
      test(6, 4)
    }, call_threshold: 2
  end

  private

  # Assert that every method call in `test_script` can be compiled by ZJIT
  # at a given call_threshold
  def assert_compiles(expected, test_script, call_threshold: 1)
    pipe_fd = 3

    script = <<~RUBY
      _test_proc = -> {
        RubyVM::ZJIT.assert_compiles
        #{test_script}
      }
      result = _test_proc.call
      IO.open(#{pipe_fd}).write(result.inspect)
    RUBY

    status, out, err, actual = eval_with_jit(script, call_threshold:, pipe_fd:)

    message = "exited with status #{status.to_i}"
    message << "\nstdout:\n```\n#{out}```\n" unless out.empty?
    message << "\nstderr:\n```\n#{err}```\n" unless err.empty?
    assert status.success?, message

    assert_equal expected, actual
  end

  # Run a Ruby process with ZJIT options and a pipe for writing test results
  def eval_with_jit(script, call_threshold: 1, timeout: 1000, pipe_fd:, debug: true)
    args = [
      "--disable-gems",
      "--zjit-call-threshold=#{call_threshold}",
    ]
    args << "--zjit-debug" if debug
    args << "-e" << script_shell_encode(script)
    pipe_r, pipe_w = IO.pipe
    # Separate thread so we don't deadlock when
    # the child ruby blocks writing the output to pipe_fd
    pipe_out = nil
    pipe_reader = Thread.new do
      pipe_out = pipe_r.read
      pipe_r.close
    end
    out, err, status = EnvUtil.invoke_ruby(args, '', true, true, rubybin: RbConfig.ruby, timeout: timeout, ios: { pipe_fd => pipe_w })
    pipe_w.close
    pipe_reader.join(timeout)
    [status, out, err, pipe_out]
  ensure
    pipe_reader&.kill
    pipe_reader&.join(timeout)
    pipe_r&.close
    pipe_w&.close
  end

  def script_shell_encode(s)
    # We can't pass utf-8-encoded characters directly in a shell arg. But we can use Ruby \u constants.
    s.chars.map { |c| c.ascii_only? ? c : "\\u%x" % c.codepoints[0] }.join
  end
end

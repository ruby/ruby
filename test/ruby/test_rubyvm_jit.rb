# frozen_string_literal: true
require 'test/unit'
require_relative '../lib/jit_support'

return if RbConfig::CONFIG["MJIT_SUPPORT"] == 'no'

class TestRubyVMJIT < Test::Unit::TestCase
  include JITSupport

  def setup
    unless JITSupport.supported?
      skip 'JIT seems not supported on this platform'
    end
  end

  def test_pause
    out, err = eval_with_jit(<<~'EOS', verbose: 1, min_calls: 1, wait: false)
      i = 0
      while i < 5
        eval("def mjit#{i}; end; mjit#{i}")
        i += 1
      end
      print RubyVM::MJIT.pause
      print RubyVM::MJIT.pause
      while i < 10
        eval("def mjit#{i}; end; mjit#{i}")
        i += 1
      end
      print RubyVM::MJIT.pause # no JIT here
    EOS
    assert_equal('truefalsefalse', out)
    assert_equal(
      5, err.scan(/#{JITSupport::JIT_SUCCESS_PREFIX}/).size,
      "unexpected stdout:\n```\n#{out}```\n\nstderr:\n```\n#{err}```",
    )
  end

  def test_pause_waits_until_compaction
    out, err = eval_with_jit(<<~'EOS', verbose: 1, min_calls: 1, wait: false)
      def a() end; a
      def b() end; b
      RubyVM::MJIT.pause
    EOS
    assert_equal(
      2, err.scan(/#{JITSupport::JIT_SUCCESS_PREFIX}/).size,
      "unexpected stdout:\n```\n#{out}```\n\nstderr:\n```\n#{err}```",
    )
    assert_equal(
      1, err.scan(/#{JITSupport::JIT_COMPACTION_PREFIX}/).size,
      "unexpected stdout:\n```\n#{out}```\n\nstderr:\n```\n#{err}```",
    ) unless RUBY_PLATFORM.match?(/mswin|mingw/) # compaction is not supported on Windows yet
  end

  def test_pause_does_not_hang_on_full_units
    out, _ = eval_with_jit(<<~'EOS', verbose: 1, min_calls: 1, max_cache: 10, wait: false)
      i = 0
      while i < 11
        eval("def mjit#{i}; end; mjit#{i}")
        i += 1
      end
      print RubyVM::MJIT.pause
    EOS
    assert_equal('true', out)
  end

  def test_pause_wait_false
    out, err = eval_with_jit(<<~'EOS', verbose: 1, min_calls: 1, wait: false)
      i = 0
      while i < 10
        eval("def mjit#{i}; end; mjit#{i}")
        i += 1
      end
      print RubyVM::MJIT.pause(wait: false)
      print RubyVM::MJIT.pause(wait: false)
    EOS
    assert_equal('truefalse', out)
    assert_equal(true, err.scan(/#{JITSupport::JIT_SUCCESS_PREFIX}/).size < 10)
  end

  def test_resume
    out, err = eval_with_jit(<<~'EOS', verbose: 1, min_calls: 1, wait: false)
      print RubyVM::MJIT.resume
      print RubyVM::MJIT.pause
      print RubyVM::MJIT.resume
      print RubyVM::MJIT.resume
      print RubyVM::MJIT.pause
    EOS
    assert_equal('falsetruetruefalsetrue', out)
    assert_equal(0, err.scan(/#{JITSupport::JIT_SUCCESS_PREFIX}/).size)
  end
end

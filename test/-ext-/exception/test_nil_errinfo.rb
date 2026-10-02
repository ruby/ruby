# frozen_string_literal: false
require 'test/unit'
require 'tmpdir'
require '-test-/exception'

module Bug
  class Test_ExceptionNilErrinfo < Test::Unit::TestCase
    # A native extension that runs Ruby code containing a rescue clause
    # between rb_protect() and rb_jump_tag() clears ec->errinfo,
    # losing the exception that was being raised.
    # There is nothing left to raise, so report it instead of unwinding.
    def test_rescue_cleanup_is_a_bug
      no_core = "Process.setrlimit(Process::RLIMIT_CORE, 0); " if defined?(Process.setrlimit) && defined?(Process::RLIMIT_CORE)
      src = <<~'RUBY'
        def (Bug::Exception).cleanup_with_rescue
          begin
            raise "cleanup error"
          rescue
            # entering this rescue sets ec->errinfo to Qnil
          end
        end

        Bug::Exception.raise_after_rescue_cleanup
      RUBY
      expected_stderr = [
        :*,
        /\[BUG\]\sexception object was lost during stack unwinding/,
        :*,
      ]
      Dir.mktmpdir do |tmpdir|
        args = [{"RUBY_ON_BUG" => nil, "RUBY_CRASH_REPORT" => nil}, "-r-test-/exception", "-C", tmpdir]
        # Writing the report is slow, see TestRubyOptions#assert_segv.
        assert_in_out_err(args, "#{no_core}#{src}", [], expected_stderr, encoding: "ASCII-8BIT", timeout: 60)
      end
    end

    # Without a rescue clause errinfo is not cleared,
    # so the exception raised by the cleanup code propagates as usual.
    def test_rescue_cleanup_raises_latest_error
      assert_in_out_err(["-r-test-/exception"], <<~'RUBY', [], /cleanup error \(RuntimeError\)/)
        def (Bug::Exception).cleanup_with_rescue
          raise "cleanup error"
        end

        Bug::Exception.raise_after_rescue_cleanup
      RUBY
    end
  end
end

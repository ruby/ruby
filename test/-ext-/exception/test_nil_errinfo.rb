# frozen_string_literal: false
require 'test/unit'
require '-test-/exception'

module Bug
  class Test_ExceptionNilErrinfo < Test::Unit::TestCase
    def test_rescue_cleanup_produces_diagnostic
      out, _, status = EnvUtil.invoke_ruby(%w[-W0], <<~'RUBY', true, :merge_to_stdout)
        require '-test-/exception'

        class Bug::Exception
          def self.cleanup_with_rescue
            begin
              raise "cleanup error"
            rescue
              # entering this rescue sets ec->errinfo to Qnil
            end
          end
        end

        Bug::Exception.raise_after_rescue_cleanup
      RUBY
      assert !status.signaled?, "process must not crash"
      assert_include out, "exception object was lost"
      assert_include out, "RuntimeError"
      refute_includes out, "cleanup error"
    end

    def test_rescue_cleanup_raises_latest_error
      out, _, status = EnvUtil.invoke_ruby(%w[-W0], <<~'RUBY', true, :merge_to_stdout)
        require '-test-/exception'

        class Bug::Exception
          def self.cleanup_with_rescue
            begin
              raise "cleanup error"
            # no rescue
            end
          end
        end

        Bug::Exception.raise_after_rescue_cleanup
      RUBY
      assert !status.signaled?, "process must not crash"
      refute_includes out, "exception object was lost"
      assert_include out, "RuntimeError"
      assert_include out, "cleanup error"
    end
  end
end

require "tempfile"
require_relative "../helper"

module TestIRB
  class MultiIRBTest < IntegrationTestCase
    def setup
      super

      write_ruby <<~'RUBY'
        binding.irb
      RUBY
    end

    def test_jobs_command_with_print_deprecated_warning
      out = run_ruby_file do
        type "jobs"
        type "exit"
      end

      assert_match(/Multi-irb commands are deprecated and will be removed in IRB 2\.0\.0\. Please use workspace commands instead\./, out)
      assert_match(%r|If you have any use case for multi-irb, please leave a comment at https://github.com/ruby/irb/issues/653|, out)
      assert_match(/#0->irb on main \(#<Thread:0x.+ run>: running\)/, out)
    end

    def test_irb_jobs_and_kill_commands
      out = run_ruby_file do
        type "irb"
        type "jobs"
        type "kill 1"
        type "exit"
      end

      assert_match(/#0->irb on main \(#<Thread:0x.+ sleep_forever>: stop\)/, out)
      assert_match(/#1->irb#1 on main \(#<Thread:0x.+ run>: running\)/, out)
    end

    def test_irb_fg_jobs_and_kill_commands
      out = run_ruby_file do
        type "irb"
        type "fg 0"
        type "jobs"
        type "kill 1"
        type "exit"
      end

      assert_match(/#0->irb on main \(#<Thread:0x.+ run>: running\)/, out)
      assert_match(/#1->irb#1 on main \(#<Thread:0x.+ sleep_forever>: stop\)/, out)
    end
  end
end

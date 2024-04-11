require "tempfile"
require_relative "../helper"

module TestIRB
  class HelpTest < IntegrationTestCase
    def setup
      super

      write_rc <<~'RUBY'
        IRB.conf[:USE_PAGER] = false
      RUBY

      write_ruby <<~'RUBY'
        binding.irb
      RUBY
    end

    def test_help
      out = run_ruby_file do
        type "help"
        type "exit"
      end

      assert_match(/List all available commands/, out)
      assert_match(/Start the debugger of debug\.gem/, out)
    end

    def test_command_help
      out = run_ruby_file do
        type "help ls"
        type "exit"
      end

      assert_match(/Usage: ls \[obj\]/, out)
    end

    def test_command_help_not_found
      out = run_ruby_file do
        type "help foo"
        type "exit"
      end

      assert_match(/Can't find command `foo`\. Please check the command name and try again\./, out)
    end

    def test_show_cmds
      out = run_ruby_file do
        type "help"
        type "exit"
      end

      assert_match(/List all available commands/, out)
      assert_match(/Start the debugger of debug\.gem/, out)
    end

    def test_help_lists_user_aliases
      out = run_ruby_file do
        type "help"
        type "exit"
      end

      assert_match(/\$\s+Alias for `show_source`/, out)
      assert_match(/@\s+Alias for `whereami`/, out)
    end
  end
end

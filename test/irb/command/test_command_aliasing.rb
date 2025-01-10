# frozen_string_literal: true

require "tempfile"
require_relative "../helper"

module TestIRB
  class CommandAliasingTest < IntegrationTestCase
    def setup
      super
      write_rc <<~RUBY
        IRB.conf[:COMMAND_ALIASES] = {
          :c => :conf, # alias to helper method
          :f => :foo
        }
      RUBY

      write_ruby <<~'RUBY'
        binding.irb
      RUBY
    end

    def test_aliasing_to_helper_method_triggers_warning
      out = run_ruby_file do
        type "c"
        type "exit"
      end
      assert_include(out, "Using command alias `c` for helper method `conf` is not supported.")
      assert_not_include(out, "Maybe IRB bug!")
    end

    def test_alias_to_non_existent_command_triggers_warning
      message = "You're trying to use command alias `f` for command `foo`, but `foo` does not exist."
      out = run_ruby_file do
        type "f"
        type "exit"
      end
      assert_include(out, message)
      assert_not_include(out, "Maybe IRB bug!")

      # Local variables take precedence over command aliases
      out = run_ruby_file do
        type "f = 123"
        type "f"
        type "exit"
      end
      assert_not_include(out, message)
      assert_not_include(out, "Maybe IRB bug!")
    end
  end
end

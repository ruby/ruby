# frozen_string_literal: true

require "tempfile"
require "tmpdir"

require_relative "helper"

module TestIRB
  class DebuggerIntegrationTest < IntegrationTestCase
    def setup
      super

      if RUBY_ENGINE == 'truffleruby'
        omit "This test runs with ruby/debug, which doesn't work with truffleruby"
      end

      @envs.merge!("NO_COLOR" => "true", "RUBY_DEBUG_HISTORY_FILE" => '')
    end

    def test_backtrace
      write_ruby <<~'RUBY'
        def foo
          binding.irb
        end
        foo
      RUBY

      output = run_ruby_file do
        type "backtrace"
        type "exit!"
      end

      assert_match(/irb\(main\):001> backtrace/, output)
      assert_match(/Object#foo at #{@ruby_file.to_path}/, output)
    end

    def test_debug
      write_ruby <<~'ruby'
        binding.irb
        puts "hello"
      ruby

      output = run_ruby_file do
        type "debug"
        type "next"
        type "continue"
      end

      assert_match(/irb\(main\):001> debug/, output)
      assert_match(/irb:rdbg\(main\):002> next/, output)
      assert_match(/=>   2\| puts "hello"/, output)
    end

    def test_debug_command_only_runs_once
      write_ruby <<~'ruby'
        binding.irb
      ruby

      output = run_ruby_file do
        type "debug"
        type "debug"
        type "continue"
      end

      assert_match(/irb\(main\):001> debug/, output)
      assert_match(/irb:rdbg\(main\):002> debug/, output)
      assert_match(/IRB is already running with a debug session/, output)
    end

    def test_debug_command_can_only_be_called_from_binding_irb
      write_ruby <<~'ruby'
        require "irb"
        # trick test framework
        puts "binding.irb"
        IRB.start
      ruby

      output = run_ruby_file do
        type "debug"
        type "exit"
      end

      assert_include(output, "Debugging commands are only available when IRB is started with binding.irb")
    end

    def test_next
      write_ruby <<~'ruby'
        binding.irb
        puts "hello"
      ruby

      output = run_ruby_file do
        type "next"
        type "continue"
      end

      assert_match(/irb\(main\):001> next/, output)
      assert_match(/=>   2\| puts "hello"/, output)
    end

    def test_break
      write_ruby <<~'RUBY'
        binding.irb
        puts "Hello"
      RUBY

      output = run_ruby_file do
        type "break 2"
        type "continue"
        type "continue"
      end

      assert_match(/irb\(main\):001> break/, output)
      assert_match(/=>   2\| puts "Hello"/, output)
    end

    def test_delete
      write_ruby <<~'RUBY'
        binding.irb
        puts "Hello"
        binding.irb
        puts "World"
      RUBY

      output = run_ruby_file do
        type "break 4"
        type "continue"
        type "delete 0"
        type "continue"
      end

      assert_match(/irb:rdbg\(main\):003> delete/, output)
      assert_match(/deleted: #0  BP - Line/, output)
    end

    def test_step
      write_ruby <<~'RUBY'
        def foo
          puts "Hello"
        end
        binding.irb
        foo
      RUBY

      output = run_ruby_file do
        type "step"
        type "step"
        type "continue"
      end

      assert_match(/irb\(main\):001> step/, output)
      assert_match(/=>   5\| foo/, output)
      assert_match(/=>   2\|   puts "Hello"/, output)
    end

    def test_long_stepping
      write_ruby <<~'RUBY'
        class Foo
          def foo(num)
            bar(num + 10)
          end

          def bar(num)
            num
          end
        end

        binding.irb
        Foo.new.foo(100)
      RUBY

      output = run_ruby_file do
        type "step"
        type "step"
        type "step"
        type "step"
        type "num"
        type "continue"
      end

      assert_match(/irb\(main\):001> step/, output)
      assert_match(/irb:rdbg\(main\):002> step/, output)
      assert_match(/irb:rdbg\(#<Foo:.*>\):003> step/, output)
      assert_match(/irb:rdbg\(#<Foo:.*>\):004> step/, output)
      assert_match(/irb:rdbg\(#<Foo:.*>\):005> num/, output)
      assert_match(/=> 110/, output)
    end

    def test_continue
      write_ruby <<~'RUBY'
        binding.irb
        puts "Hello"
        binding.irb
        puts "World"
      RUBY

      output = run_ruby_file do
        type "continue"
        type "continue"
      end

      assert_match(/irb\(main\):001> continue/, output)
      assert_match(/=> 3: binding.irb/, output)
      assert_match(/irb:rdbg\(main\):002> continue/, output)
    end

    def test_finish
      write_ruby <<~'RUBY'
        def foo
          binding.irb
          puts "Hello"
        end
        foo
      RUBY

      output = run_ruby_file do
        type "finish"
        type "continue"
      end

      assert_match(/irb\(main\):001> finish/, output)
      assert_match(/=>   4\| end/, output)
    end

    def test_info
      write_ruby <<~'RUBY'
        def foo
          a = "He" + "llo"
          binding.irb
        end
        foo
      RUBY

      output = run_ruby_file do
        type "info"
        type "continue"
      end

      assert_match(/irb\(main\):001> info/, output)
      assert_match(/%self = main/, output)
      assert_match(/a = "Hello"/, output)
    end

    def test_catch
      write_ruby <<~'RUBY'
        binding.irb
        1 / 0
      RUBY

      output = run_ruby_file do
        type "catch ZeroDivisionError"
        type "continue"
        type "continue"
      end

      assert_match(/irb\(main\):001> catch/, output)
      assert_match(/Stop by #0  BP - Catch  "ZeroDivisionError"/, output)
    end

    def test_exit
      write_ruby <<~'RUBY'
        binding.irb
        puts "he" + "llo"
      RUBY

      output = run_ruby_file do
        type "debug"
        type "exit"
      end

      assert_match(/irb:rdbg\(main\):002>/, output)
      assert_match(/hello/, output)
    end

    def test_force_exit
      write_ruby <<~'RUBY'
        binding.irb
        puts "he" + "llo"
      RUBY

      output = run_ruby_file do
        type "debug"
        type "exit!"
      end

      assert_match(/irb:rdbg\(main\):002>/, output)
      assert_not_match(/hello/, output)
    end

    def test_quit
      write_ruby <<~'RUBY'
        binding.irb
        puts "he" + "llo"
      RUBY

      output = run_ruby_file do
        type "debug"
        type "quit!"
      end

      assert_match(/irb:rdbg\(main\):002>/, output)
      assert_not_match(/hello/, output)
    end

    def test_prompt_line_number_continues
      write_ruby <<~'ruby'
        binding.irb
        puts "Hello"
        puts "World"
      ruby

      output = run_ruby_file do
        type "123"
        type "456"
        type "next"
        type "info"
        type "next"
        type "continue"
      end

      assert_match(/irb\(main\):003> next/, output)
      assert_match(/irb:rdbg\(main\):004> info/, output)
      assert_match(/irb:rdbg\(main\):005> next/, output)
    end

    def test_prompt_irb_name_is_kept
      write_rc <<~RUBY
        IRB.conf[:IRB_NAME] = "foo"
      RUBY

      write_ruby <<~'ruby'
        binding.irb
        puts "Hello"
      ruby

      output = run_ruby_file do
        type "next"
        type "continue"
      end

      assert_match(/foo\(main\):001> next/, output)
      assert_match(/foo:rdbg\(main\):002> continue/, output)
    end

    def test_irb_commands_are_available_after_moving_around_with_the_debugger
      write_ruby <<~'ruby'
        class Foo
          def bar
            puts "bar"
          end
        end

        binding.irb
        Foo.new.bar
      ruby

      output = run_ruby_file do
        # Due to the way IRB defines its commands, moving into the Foo instance from main is necessary for proper testing.
        type "next"
        type "step"
        type "irb_info"
        type "continue"
      end

      assert_include(output, "InputMethod: RelineInputMethod")
    end

    def test_help_command_is_delegated_to_the_debugger
      write_ruby <<~'ruby'
        binding.irb
      ruby

      output = run_ruby_file do
        type "debug"
        type "help"
        type "continue"
      end

      assert_include(output, "### Frame control")
    end

    def test_help_display_different_content_when_debugger_is_enabled
      write_ruby <<~'ruby'
        binding.irb
      ruby

      output = run_ruby_file do
        type "debug"
        type "help"
        type "continue"
      end

      # IRB's commands should still be listed
      assert_match(/help\s+List all available commands/, output)
      # debug gem's commands should be appended at the end
      assert_match(/Debugging \(from debug\.gem\)\s+### Control flow/, output)
    end

    def test_input_is_evaluated_in_the_context_of_the_current_thread
      write_ruby <<~'ruby'
        current_thread = Thread.current
        binding.irb
      ruby

      output = run_ruby_file do
        type "debug"
        type '"Threads match: #{current_thread == Thread.current}"'
        type "continue"
      end

      assert_match(/irb\(main\):001> debug/, output)
      assert_match(/Threads match: true/, output)
    end

    def test_irb_switches_debugger_interface_if_debug_was_already_activated
      write_ruby <<~'ruby'
        require 'debug'
        class Foo
          def bar
            puts "bar"
          end
        end

        binding.irb
        Foo.new.bar
      ruby

      output = run_ruby_file do
        # Due to the way IRB defines its commands, moving into the Foo instance from main is necessary for proper testing.
        type "next"
        type "step"
        type 'irb_info'
        type "continue"
      end

      assert_match(/irb\(main\):001> next/, output)
      assert_include(output, "InputMethod: RelineInputMethod")
    end

    def test_debugger_cant_be_activated_while_multi_irb_is_active
      write_ruby <<~'ruby'
        binding.irb
        a = 1
      ruby

      output = run_ruby_file do
        type "jobs"
        type "next"
        type "exit"
      end

      assert_match(/irb\(main\):001> jobs/, output)
      assert_include(output, "Can't start the debugger when IRB is running in a multi-IRB session.")
    end

    def test_multi_irb_commands_are_not_available_after_activating_the_debugger
      write_ruby <<~'ruby'
        binding.irb
        a = 1
      ruby

      output = run_ruby_file do
        type "next"
        type "jobs"
        type "continue"
      end

      assert_match(/irb\(main\):001> next/, output)
      assert_include(output, "Multi-IRB commands are not available when the debugger is enabled.")
    end

    def test_irb_passes_empty_input_to_debugger_to_repeat_the_last_command
      write_ruby <<~'ruby'
        binding.irb
        puts "foo"
        puts "bar"
        puts "baz"
      ruby

      output = run_ruby_file do
        type "next"
        type ""
        # Test that empty input doesn't repeat expressions
        type "123"
        type ""
        type "next"
        type ""
        type ""
      end

      assert_include(output, "=>   2\| puts \"foo\"")
      assert_include(output, "=>   3\| puts \"bar\"")
      assert_include(output, "=>   4\| puts \"baz\"")
    end
  end
end

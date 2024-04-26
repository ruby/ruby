# frozen_string_literal: true
require "irb"

require_relative "../helper"

module TestIRB
  class CustomCommandIntegrationTest < TestIRB::IntegrationTestCase
    def test_command_regsitration_can_happen_after_irb_require
      write_ruby <<~RUBY
        require "irb"
        require "irb/command"

        class PrintCommand < IRB::Command::Base
          category 'CommandTest'
          description 'print_command'
          def execute(*)
            puts "Hello from PrintCommand"
            nil
          end
        end

        IRB::Command.register(:print!, PrintCommand)

        binding.irb
      RUBY

      output = run_ruby_file do
        type "print!\n"
        type "exit"
      end

      assert_include(output, "Hello from PrintCommand")
    end

    def test_command_regsitration_accepts_string_too
      write_ruby <<~RUBY
        require "irb/command"

        class PrintCommand < IRB::Command::Base
          category 'CommandTest'
          description 'print_command'
          def execute(*)
            puts "Hello from PrintCommand"
            nil
          end
        end

        IRB::Command.register("print!", PrintCommand)

        binding.irb
      RUBY

      output = run_ruby_file do
        type "print!\n"
        type "exit"
      end

      assert_include(output, "Hello from PrintCommand")
    end

    def test_arguments_propogation
      write_ruby <<~RUBY
        require "irb/command"

        class PrintArgCommand < IRB::Command::Base
          category 'CommandTest'
          description 'print_command_arg'
          def execute(arg)
            $nth_execution ||= 0
            puts "\#{$nth_execution} arg=\#{arg.inspect}"
            $nth_execution += 1
            nil
          end
        end

        IRB::Command.register(:print_arg, PrintArgCommand)

        binding.irb
      RUBY

      output = run_ruby_file do
        type "print_arg\n"
        type "print_arg  \n"
        type "print_arg a r  g\n"
        type "print_arg  a r  g  \n"
        type "exit"
      end

      assert_include(output, "0 arg=\"\"")
      assert_include(output, "1 arg=\"\"")
      assert_include(output, "2 arg=\"a r  g\"")
      assert_include(output, "3 arg=\"a r  g\"")
    end

    def test_def_extend_command_still_works
      write_ruby <<~RUBY
        require "irb"

        class FooBarCommand < IRB::Command::Base
          category 'FooBarCategory'
          description 'foobar_description'
          def execute(*)
            $nth_execution ||= 1
            puts "\#{$nth_execution} FooBar executed"
            $nth_execution += 1
            nil
          end
        end

        IRB::ExtendCommandBundle.def_extend_command(:foobar, FooBarCommand, nil, [:fbalias, IRB::Command::OVERRIDE_ALL])

        binding.irb
      RUBY

      output = run_ruby_file do
        type "foobar"
        type "fbalias"
        type "help foobar"
        type "exit"
      end

      assert_include(output, "1 FooBar executed")
      assert_include(output, "2 FooBar executed")
      assert_include(output, "foobar_description")
    end
  end
end

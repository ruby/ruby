# frozen_string_literal: true
require "irb"

require_relative "../helper"

module TestIRB
  class CustomCommandIntegrationTest < TestIRB::IntegrationTestCase
    def test_command_registration_can_happen_after_irb_require
      write_ruby <<~RUBY
        require "irb"
        require "irb/command"

        class PrintCommand < IRB::Command::Base
          category 'CommandTest'
          description 'print_command'
          def execute(*)
            puts "Hello from PrintCommand"
          end
        end

        IRB::Command.register(:print!, PrintCommand)

        binding.irb
      RUBY

      output = run_ruby_file do
        type "print!"
        type "exit"
      end

      assert_include(output, "Hello from PrintCommand")
    end

    def test_command_registration_accepts_string_too
      write_ruby <<~RUBY
        require "irb/command"

        class PrintCommand < IRB::Command::Base
          category 'CommandTest'
          description 'print_command'
          def execute(*)
            puts "Hello from PrintCommand"
          end
        end

        IRB::Command.register("print!", PrintCommand)

        binding.irb
      RUBY

      output = run_ruby_file do
        type "print!"
        type "exit"
      end

      assert_include(output, "Hello from PrintCommand")
    end

    def test_arguments_propagation
      write_ruby <<~RUBY
        require "irb/command"

        class PrintArgCommand < IRB::Command::Base
          category 'CommandTest'
          description 'print_command_arg'
          def execute(arg)
            $nth_execution ||= 0
            puts "\#{$nth_execution} arg=\#{arg.inspect}"
            $nth_execution += 1
          end
        end

        IRB::Command.register(:print_arg, PrintArgCommand)

        binding.irb
      RUBY

      output = run_ruby_file do
        type "print_arg"
        type "print_arg  \n"
        type "print_arg a r  g"
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

    def test_no_meta_command_also_works
      write_ruby <<~RUBY
        require "irb/command"

        class NoMetaCommand < IRB::Command::Base
          def execute(*)
            puts "This command does not override meta attributes"
          end
        end

        IRB::Command.register(:no_meta, NoMetaCommand)

        binding.irb
      RUBY

      output = run_ruby_file do
        type "no_meta"
        type "help no_meta"
        type "exit"
      end

      assert_include(output, "This command does not override meta attributes")
      assert_include(output, "No description provided.")
      assert_not_include(output, "Maybe IRB bug")
    end
  end
end

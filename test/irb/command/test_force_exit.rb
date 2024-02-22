# frozen_string_literal: false
require 'irb'

require_relative "../helper"

module TestIRB
  class ForceExitTest < IntegrationTestCase
    def test_forced_exit_finishes_process_immediately
      write_ruby <<~'ruby'
        puts "First line"
        puts "Second line"
        binding.irb
        puts "Third line"
        binding.irb
        puts "Fourth line"
      ruby

      output = run_ruby_file do
        type "123"
        type "456"
        type "exit!"
      end

      assert_match(/First line\r\n/, output)
      assert_match(/Second line\r\n/, output)
      assert_match(/irb\(main\):001> 123/, output)
      assert_match(/irb\(main\):002> 456/, output)
      refute_match(/Third line\r\n/, output)
      refute_match(/Fourth line\r\n/, output)
    end

    def test_forced_exit_in_nested_sessions
      write_ruby <<~'ruby'
        def foo
          binding.irb
        end

        binding.irb
        binding.irb
      ruby

      output = run_ruby_file do
        type "123"
        type "foo"
        type "exit!"
      end

      assert_match(/irb\(main\):001> 123/, output)
    end

    def test_forced_exit_out_of_irb_session
      write_ruby <<~'ruby'
        at_exit { puts 'un' + 'reachable' }
        binding.irb
        exit! # this will call exit! method overrided by command
      ruby
      output = run_ruby_file do
        type "exit"
      end
      assert_not_include(output, 'unreachable')
    end
  end
end

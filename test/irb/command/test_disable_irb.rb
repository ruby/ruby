# frozen_string_literal: false
require 'irb'

require_relative "../helper"

module TestIRB
  class DisableIRBTest < IntegrationTestCase
    def test_disable_irb_disable_further_irb_breakpoints
      write_ruby <<~'ruby'
        puts "First line"
        puts "Second line"
        binding.irb
        puts "Third line"
        binding.irb
        puts "Fourth line"
      ruby

      output = run_ruby_file do
        type "disable_irb"
      end

      assert_match(/First line\r\n/, output)
      assert_match(/Second line\r\n/, output)
      assert_match(/Third line\r\n/, output)
      assert_match(/Fourth line\r\n/, output)
    end
  end
end

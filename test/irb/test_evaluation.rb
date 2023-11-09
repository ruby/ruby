# frozen_string_literal: true

require "tempfile"

require_relative "helper"

module TestIRB
  class EchoingTest < IntegrationTestCase
    def test_irb_echos_by_default
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "123123"
        type "exit"
      end

      assert_include(output, "=> 123123")
    end

    def test_irb_doesnt_echo_line_with_semicolon
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "123123;"
        type "123123   ;"
        type "123123;   "
        type <<~RUBY
          if true
            123123
          end;
        RUBY
        type "'evaluation ends'"
        type "exit"
      end

      assert_include(output, "=> \"evaluation ends\"")
      assert_not_include(output, "=> 123123")
    end
  end
end

# frozen_string_literal: true

require 'irb'

require_relative "../helper"

module TestIRB
  class CopyTest < IntegrationTestCase
    def setup
      super
      @envs['IRB_COPY_COMMAND'] = "#{EnvUtil.rubybin} -e \"puts 'foo' + STDIN.read\""
    end

    def test_copy_with_pbcopy
      write_ruby <<~'ruby'
        class Answer
          def initialize(answer)
            @answer = answer
          end
        end

        binding.irb
      ruby

      output =  run_ruby_file do
        type "copy Answer.new(42)"
        type "exit"
      end

      assert_match(/foo#<Answer:0x[0-9a-f]+ @answer=42/, output)
      assert_match(/Copied to system clipboard/, output)
    end

    # copy puts 5 should:
    # - Print value to the console
    # - Copy nil to clipboard, since that is what the puts call evaluates to
    def test_copy_when_expression_has_side_effects
      write_ruby <<~'ruby'
        binding.irb
      ruby

      output = run_ruby_file do
        type "copy puts 42"
        type "exit"
      end

      assert_match(/^42\r\n/, output)
      assert_match(/foonil/, output)
      assert_match(/Copied to system clipboard/, output)
      refute_match(/foo42/, output)
    end

    def test_copy_when_copy_command_is_invalid
      @envs['IRB_COPY_COMMAND'] = "lulz"

      write_ruby <<~'ruby'
        binding.irb
      ruby

      output = run_ruby_file do
        type "copy 42"
        type "exit"
      end

      assert_match(/No such file or directory - lulz/, output)
      assert_match(/Is IRB\.conf\[:COPY_COMMAND\] set to a bad value/, output)
      refute_match(/Copied to system clipboard/, output)
    end
  end
end

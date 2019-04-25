# frozen_string_literal: false
require 'test/unit'
require 'irb/color'

module TestIRB
  class TestColor < Test::Unit::TestCase
    CLEAR     = "\e[0m"
    BOLD      = "\e[1m"
    UNDERLINE = "\e[4m"
    RED       = "\e[31m"
    GREEN     = "\e[32m"
    BLUE      = "\e[34m"
    MAGENTA   = "\e[35m"
    CYAN      = "\e[36m"

    def test_colorize_code
      {
        "1" => "#{BLUE}#{BOLD}1#{CLEAR}",
        "2.3" => "#{MAGENTA}#{BOLD}2.3#{CLEAR}",
        "['foo', :bar]" => "[#{RED}'#{CLEAR}#{RED}foo#{CLEAR}#{RED}'#{CLEAR}, #{BLUE}#{BOLD}:#{CLEAR}#{BLUE}#{BOLD}bar#{CLEAR}]",
        "class A; end" => "#{GREEN}class#{CLEAR} #{BLUE}#{BOLD}#{UNDERLINE}A#{CLEAR}; #{GREEN}end#{CLEAR}",
        "def self.foo; bar; end" => "#{GREEN}def#{CLEAR} #{CYAN}#{BOLD}self#{CLEAR}.#{BLUE}#{BOLD}foo#{CLEAR}; bar; #{GREEN}end#{CLEAR}",
        'ERB.new("a#{nil}b", trim_mode: "-")' => "#{BLUE}#{BOLD}#{UNDERLINE}ERB#{CLEAR}.new(#{RED}\"#{CLEAR}#{RED}a#{CLEAR}#{RED}\#{#{CLEAR}#{CYAN}#{BOLD}nil#{CLEAR}#{RED}}#{CLEAR}#{RED}b#{CLEAR}#{RED}\"#{CLEAR}, #{MAGENTA}trim_mode:#{CLEAR} #{RED}\"#{CLEAR}#{RED}-#{CLEAR}#{RED}\"#{CLEAR})",
        "# comment" => "#{BLUE}#{BOLD}# comment#{CLEAR}",
      }.each do |code, result|
        assert_equal(result, IRB::Color.colorize_code(code))
      end
    end
  end
end

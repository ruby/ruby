# frozen_string_literal: false
require 'test/unit'
require 'irb/color'
require 'stringio'

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
      if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.5.0')
        assert_equal({}, IRB::Color::TOKEN_SEQ_EXPRS)
        skip "this Ripper version is not supported"
      end

      {
        "1" => "#{BLUE}#{BOLD}1#{CLEAR}",
        "2.3" => "#{MAGENTA}#{BOLD}2.3#{CLEAR}",
        "['foo', :bar]" => "[#{RED}'#{CLEAR}#{RED}foo#{CLEAR}#{RED}'#{CLEAR}, #{BLUE}#{BOLD}:#{CLEAR}#{BLUE}#{BOLD}bar#{CLEAR}]",
        "class A; end" => "#{GREEN}class#{CLEAR} #{BLUE}#{BOLD}#{UNDERLINE}A#{CLEAR}; #{GREEN}end#{CLEAR}",
        "def self.foo; bar; end" => "#{GREEN}def#{CLEAR} #{CYAN}#{BOLD}self#{CLEAR}.#{BLUE}#{BOLD}foo#{CLEAR}; bar; #{GREEN}end#{CLEAR}",
        'ERB.new("a#{nil}b", trim_mode: "-")' => "#{BLUE}#{BOLD}#{UNDERLINE}ERB#{CLEAR}.new(#{RED}\"#{CLEAR}#{RED}a#{CLEAR}#{RED}\#{#{CLEAR}#{CYAN}#{BOLD}nil#{CLEAR}#{RED}}#{CLEAR}#{RED}b#{CLEAR}#{RED}\"#{CLEAR}, #{MAGENTA}trim_mode:#{CLEAR} #{RED}\"#{CLEAR}#{RED}-#{CLEAR}#{RED}\"#{CLEAR})",
        "# comment" => "#{BLUE}#{BOLD}# comment#{CLEAR}",
        "yield(hello)" => "#{GREEN}yield#{CLEAR}(hello)",
        '"##@var]"' => "#{RED}\"#{CLEAR}#{RED}##{CLEAR}#{RED}##{CLEAR}@var#{RED}]#{CLEAR}#{RED}\"#{CLEAR}",
        '"foo#{a} #{b}"' => "#{RED}\"#{CLEAR}#{RED}foo#{CLEAR}#{RED}\#{#{CLEAR}a#{RED}}#{CLEAR}#{RED} #{CLEAR}#{RED}\#{#{CLEAR}b#{RED}}#{CLEAR}#{RED}\"#{CLEAR}",
        '/r#{e}g/' => "#{RED}#{BOLD}/#{CLEAR}#{RED}r#{CLEAR}#{RED}\#{#{CLEAR}e#{RED}}#{CLEAR}#{RED}g#{CLEAR}#{RED}#{BOLD}/#{CLEAR}",
        "'a\nb'" => "#{RED}'#{CLEAR}#{RED}a#{CLEAR}\n#{RED}b#{CLEAR}#{RED}'#{CLEAR}",
        "4.5.6" => "4.5.6",
        "[1]]]" => "[1]]]",
        "\e[0m\n" => "^[[#{BLUE}#{BOLD}0#{CLEAR}m\n",
      }.each do |code, result|
        actual = with_term { IRB::Color.colorize_code(code) }
        assert_equal(result, actual, "Case: colorize_code(#{code.dump})\nResult: #{humanized_literal(actual)}")
      end
    end

    def test_inspect_colorable
      {
        1 => true,
        2.3 => true,
        ['foo', :bar] => true,
        { a: 4 } => true,
        /reg/ => true,
        (1..3) => true,
        Object.new => false,
        Struct => true,
        Test => true,
        Struct.new(:a) => false,
        Struct.new(:a).new(1) => false,
      }.each do |object, result|
        assert_equal(result, IRB::Color.inspect_colorable?(object), "Case: inspect_colorable?(#{object.inspect})")
      end
    end

    private

    def with_term
      stdout = $stdout
      io = StringIO.new
      def io.tty?; true; end
      $stdout = io

      env = ENV.to_h.dup
      ENV['TERM'] = 'xterm-256color'

      yield
    ensure
      $stdout = stdout
      ENV.replace(env) if env
    end

    def humanized_literal(str)
      str
        .gsub(CLEAR, '@@@{CLEAR}')
        .gsub(BOLD, '@@@{BOLD}')
        .gsub(UNDERLINE, '@@@{UNDERLINE}')
        .gsub(RED, '@@@{RED}')
        .gsub(GREEN, '@@@{GREEN}')
        .gsub(BLUE, '@@@{BLUE}')
        .gsub(MAGENTA, '@@@{MAGENTA}')
        .gsub(CYAN, '@@@{CYAN}')
        .dump.gsub(/@@@/, '#')
    end
  end
end

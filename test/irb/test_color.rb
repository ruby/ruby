# frozen_string_literal: false
require 'test/unit'
require 'irb/color'
require 'rubygems'
require 'stringio'

module TestIRB
  class TestColor < Test::Unit::TestCase
    CLEAR     = "\e[0m"
    BOLD      = "\e[1m"
    UNDERLINE = "\e[4m"
    REVERSE   = "\e[7m"
    RED       = "\e[31m"
    GREEN     = "\e[32m"
    YELLOW    = "\e[33m"
    BLUE      = "\e[34m"
    MAGENTA   = "\e[35m"
    CYAN      = "\e[36m"

    def test_colorize_code
      # Common behaviors. Warn parser error, but do not warn compile error.
      tests = {
        "1" => "#{BLUE}#{BOLD}1#{CLEAR}",
        "2.3" => "#{MAGENTA}#{BOLD}2.3#{CLEAR}",
        "7r" => "#{BLUE}#{BOLD}7r#{CLEAR}",
        "8i" => "#{BLUE}#{BOLD}8i#{CLEAR}",
        "['foo', :bar]" => "[#{RED}'#{CLEAR}#{RED}foo#{CLEAR}#{RED}'#{CLEAR}, #{YELLOW}:#{CLEAR}#{YELLOW}bar#{CLEAR}]",
        "class A; end" => "#{GREEN}class#{CLEAR} #{BLUE}#{BOLD}#{UNDERLINE}A#{CLEAR}; #{GREEN}end#{CLEAR}",
        "def self.foo; bar; end" => "#{GREEN}def#{CLEAR} #{CYAN}#{BOLD}self#{CLEAR}.#{BLUE}#{BOLD}foo#{CLEAR}; bar; #{GREEN}end#{CLEAR}",
        'erb = ERB.new("a#{nil}b", trim_mode: "-")' => "erb = #{BLUE}#{BOLD}#{UNDERLINE}ERB#{CLEAR}.new(#{RED}\"#{CLEAR}#{RED}a#{CLEAR}#{RED}\#{#{CLEAR}#{CYAN}#{BOLD}nil#{CLEAR}#{RED}}#{CLEAR}#{RED}b#{CLEAR}#{RED}\"#{CLEAR}, #{MAGENTA}trim_mode:#{CLEAR} #{RED}\"#{CLEAR}#{RED}-#{CLEAR}#{RED}\"#{CLEAR})",
        "# comment" => "#{BLUE}#{BOLD}# comment#{CLEAR}",
        "yield(hello)" => "#{GREEN}yield#{CLEAR}(hello)",
        '"##@var]"' => "#{RED}\"#{CLEAR}#{RED}##{CLEAR}#{RED}##{CLEAR}@var#{RED}]#{CLEAR}#{RED}\"#{CLEAR}",
        '"foo#{a} #{b}"' => "#{RED}\"#{CLEAR}#{RED}foo#{CLEAR}#{RED}\#{#{CLEAR}a#{RED}}#{CLEAR}#{RED} #{CLEAR}#{RED}\#{#{CLEAR}b#{RED}}#{CLEAR}#{RED}\"#{CLEAR}",
        '/r#{e}g/' => "#{RED}#{BOLD}/#{CLEAR}#{RED}r#{CLEAR}#{RED}\#{#{CLEAR}e#{RED}}#{CLEAR}#{RED}g#{CLEAR}#{RED}#{BOLD}/#{CLEAR}",
        "'a\nb'" => "#{RED}'#{CLEAR}#{RED}a#{CLEAR}\n#{RED}b#{CLEAR}#{RED}'#{CLEAR}",
        "[1]]]\u0013" => "[1]]]^S",
        "%w[a b]" => "#{RED}%w[#{CLEAR}#{RED}a#{CLEAR} #{RED}b#{CLEAR}#{RED}]#{CLEAR}",
        "%i[c d]" => "#{RED}%i[#{CLEAR}#{RED}c#{CLEAR} #{RED}d#{CLEAR}#{RED}]#{CLEAR}",
        "{'a': 1}" => "{#{RED}'#{CLEAR}#{RED}a#{CLEAR}#{RED}':#{CLEAR} #{BLUE}#{BOLD}1#{CLEAR}}",
        ":Struct" => "#{YELLOW}:#{CLEAR}#{YELLOW}Struct#{CLEAR}",
        '"#{}"' => "#{RED}\"#{CLEAR}#{RED}\#{#{CLEAR}#{RED}}#{CLEAR}#{RED}\"#{CLEAR}",
        ':"a#{}b"' => "#{YELLOW}:\"#{CLEAR}#{YELLOW}a#{CLEAR}#{YELLOW}\#{#{CLEAR}#{YELLOW}}#{CLEAR}#{YELLOW}b#{CLEAR}#{YELLOW}\"#{CLEAR}",
        ':"a#{ def b; end; \'c\' + "#{ :d }" }e"' => "#{YELLOW}:\"#{CLEAR}#{YELLOW}a#{CLEAR}#{YELLOW}\#{#{CLEAR} #{GREEN}def#{CLEAR} #{BLUE}#{BOLD}b#{CLEAR}; #{GREEN}end#{CLEAR}; #{RED}'#{CLEAR}#{RED}c#{CLEAR}#{RED}'#{CLEAR} + #{RED}\"#{CLEAR}#{RED}\#{#{CLEAR} #{YELLOW}:#{CLEAR}#{YELLOW}d#{CLEAR} #{RED}}#{CLEAR}#{RED}\"#{CLEAR} #{YELLOW}}#{CLEAR}#{YELLOW}e#{CLEAR}#{YELLOW}\"#{CLEAR}",
        "[__FILE__, __LINE__]" => "[#{CYAN}#{BOLD}__FILE__#{CLEAR}, #{CYAN}#{BOLD}__LINE__#{CLEAR}]",
        ":self" => "#{YELLOW}:#{CLEAR}#{YELLOW}self#{CLEAR}",
        ":class" => "#{YELLOW}:#{CLEAR}#{YELLOW}class#{CLEAR}",
        "[:end, 2]" => "[#{YELLOW}:#{CLEAR}#{YELLOW}end#{CLEAR}, #{BLUE}#{BOLD}2#{CLEAR}]",
        "[:>, 3]" => "[#{YELLOW}:#{CLEAR}#{YELLOW}>#{CLEAR}, #{BLUE}#{BOLD}3#{CLEAR}]",
        ":Hello ? world : nil" => "#{YELLOW}:#{CLEAR}#{YELLOW}Hello#{CLEAR} ? world : #{CYAN}#{BOLD}nil#{CLEAR}",
        'raise "foo#{bar}baz"' => "raise #{RED}\"#{CLEAR}#{RED}foo#{CLEAR}#{RED}\#{#{CLEAR}bar#{RED}}#{CLEAR}#{RED}baz#{CLEAR}#{RED}\"#{CLEAR}",
        '["#{obj.inspect}"]' => "[#{RED}\"#{CLEAR}#{RED}\#{#{CLEAR}obj.inspect#{RED}}#{CLEAR}#{RED}\"#{CLEAR}]",
        'URI.parse "#{}"' => "#{BLUE}#{BOLD}#{UNDERLINE}URI#{CLEAR}.parse #{RED}\"#{CLEAR}#{RED}\#{#{CLEAR}#{RED}}#{CLEAR}#{RED}\"#{CLEAR}",
        "begin\nrescue\nend" => "#{GREEN}begin#{CLEAR}\n#{GREEN}rescue#{CLEAR}\n#{GREEN}end#{CLEAR}",
        "foo %w[bar]" => "foo #{RED}%w[#{CLEAR}#{RED}bar#{CLEAR}#{RED}]#{CLEAR}",
        "foo %i[bar]" => "foo #{RED}%i[#{CLEAR}#{RED}bar#{CLEAR}#{RED}]#{CLEAR}",
        "foo :@bar, baz, :@@qux, :$quux" => "foo #{YELLOW}:#{CLEAR}#{YELLOW}@bar#{CLEAR}, baz, #{YELLOW}:#{CLEAR}#{YELLOW}@@qux#{CLEAR}, #{YELLOW}:#{CLEAR}#{YELLOW}$quux#{CLEAR}",
        "`echo`" => "#{RED}`#{CLEAR}#{RED}echo#{CLEAR}#{RED}`#{CLEAR}",
        "\t" => "\t", # not ^I
        "foo(*%W(bar))" => "foo(*#{RED}%W(#{CLEAR}#{RED}bar#{CLEAR}#{RED})#{CLEAR})",
        "$stdout" => "#{GREEN}#{BOLD}$stdout#{CLEAR}",
      }

      # specific to Ruby 2.7+
      if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.7.0')
        tests.merge!({
          "4.5.6" => "#{MAGENTA}#{BOLD}4.5#{CLEAR}#{RED}#{REVERSE}.6#{CLEAR}",
          "\e[0m\n" => "#{RED}#{REVERSE}^[#{CLEAR}[#{BLUE}#{BOLD}0#{CLEAR}#{RED}#{REVERSE}m#{CLEAR}\n",
          "<<EOS\nhere\nEOS" => "#{RED}<<EOS#{CLEAR}\n#{RED}here#{CLEAR}\n#{RED}EOS#{CLEAR}",
          ":@1" => "#{YELLOW}:#{CLEAR}#{RED}#{REVERSE}@1#{CLEAR}",
          "@@1" => "#{RED}#{REVERSE}@@1#{CLEAR}",
        })
      end

      tests.each do |code, result|
        if colorize_code_supported?
          actual = with_term { IRB::Color.colorize_code(code, complete: true) }
          assert_equal(result, actual, "Case: colorize_code(#{code.dump}, complete: true)\nResult: #{humanized_literal(actual)}")

          actual = with_term { IRB::Color.colorize_code(code, complete: false) }
          assert_equal(result, actual, "Case: colorize_code(#{code.dump}, complete: false)\nResult: #{humanized_literal(actual)}")
        else
          actual = with_term { IRB::Color.colorize_code(code) }
          assert_equal(code, actual)
        end
      end
    end

    def test_colorize_code_complete_true
      unless complete_option_supported?
        skip '`complete: true` is the same as `complete: false` in Ruby 2.6-'
      end

      # `complete: true` behaviors. Warn end-of-file.
      {
        "'foo' + 'bar" => "#{RED}'#{CLEAR}#{RED}foo#{CLEAR}#{RED}'#{CLEAR} + #{RED}'#{CLEAR}#{RED}#{REVERSE}bar#{CLEAR}",
        "('foo" => "(#{RED}'#{CLEAR}#{RED}#{REVERSE}foo#{CLEAR}",
      }.each do |code, result|
        actual = with_term { IRB::Color.colorize_code(code, complete: true) }
        assert_equal(result, actual, "Case: colorize_code(#{code.dump}, complete: true)\nResult: #{humanized_literal(actual)}")
      end
    end

    def test_colorize_code_complete_false
      # `complete: false` behaviors. Do not warn end-of-file.
      {
        "'foo' + 'bar" => "#{RED}'#{CLEAR}#{RED}foo#{CLEAR}#{RED}'#{CLEAR} + #{RED}'#{CLEAR}#{RED}bar#{CLEAR}",
        "('foo" => "(#{RED}'#{CLEAR}#{RED}foo#{CLEAR}",
      }.each do |code, result|
        if colorize_code_supported?
          actual = with_term { IRB::Color.colorize_code(code, complete: false) }
          assert_equal(result, actual, "Case: colorize_code(#{code.dump}, complete: false)\nResult: #{humanized_literal(actual)}")

          unless complete_option_supported?
            actual = with_term { IRB::Color.colorize_code(code, complete: true) }
            assert_equal(result, actual, "Case: colorize_code(#{code.dump}, complete: false)\nResult: #{humanized_literal(actual)}")
          end
        else
          actual = with_term { IRB::Color.colorize_code(code) }
          assert_equal(code, actual)
        end
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

    # `#colorize_code` is supported only for Ruby 2.5+. It just returns the original code in 2.4-.
    def colorize_code_supported?
      Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.5.0')
    end

    # `complete: true` is the same as `complete: false` in Ruby 2.6-
    def complete_option_supported?
      Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.7.0')
    end

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
        .gsub(REVERSE, '@@@{REVERSE}')
        .gsub(RED, '@@@{RED}')
        .gsub(GREEN, '@@@{GREEN}')
        .gsub(YELLOW, '@@@{YELLOW}')
        .gsub(BLUE, '@@@{BLUE}')
        .gsub(MAGENTA, '@@@{MAGENTA}')
        .gsub(CYAN, '@@@{CYAN}')
        .dump.gsub(/@@@/, '#')
    end
  end
end

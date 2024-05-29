# frozen_string_literal: true

require_relative "test_helper"

return if RUBY_VERSION < "3.1.0"

module Prism
  class UnescapeTest < TestCase
    module Context
      class Base
        attr_reader :left, :right

        def initialize(left, right)
          @left = left
          @right = right
        end

        def name
          "#{left}#{right}".delete("\n")
        end

        private

        def code(escape)
          "#{left}\\#{escape}#{right}".b
        end

        def ruby(escape)
          previous, $VERBOSE = $VERBOSE, nil

          begin
            yield eval(code(escape))
          rescue SyntaxError
            :error
          ensure
            $VERBOSE = previous
          end
        end

        def prism(escape)
          result = Prism.parse(code(escape), encoding: "binary")

          if result.success?
            yield result.statement
          else
            :error
          end
        end

        def `(command)
          command
        end
      end

      class List < Base
        def ruby_result(escape)
          ruby(escape) { |value| value.first.to_s }
        end

        def prism_result(escape)
          prism(escape) { |node| node.elements.first.unescaped }
        end
      end

      class Symbol < Base
        def ruby_result(escape)
          ruby(escape, &:to_s)
        end

        def prism_result(escape)
          prism(escape, &:unescaped)
        end
      end

      class String < Base
        def ruby_result(escape)
          ruby(escape, &:itself)
        end

        def prism_result(escape)
          prism(escape, &:unescaped)
        end
      end

      class Heredoc < Base
        def ruby_result(escape)
          ruby(escape, &:itself)
        end

        def prism_result(escape)
          prism(escape) do |node|
            case node.type
            when :interpolated_string_node, :interpolated_x_string_node
              node.parts.flat_map(&:unescaped).join
            else
              node.unescaped
            end
          end
        end
      end

      class RegExp < Base
        def ruby_result(escape)
          ruby(escape, &:source)
        end

        def prism_result(escape)
          prism(escape, &:unescaped)
        end
      end
    end

    def test_char; assert_context(Context::String.new("?", "")); end
    def test_sqte; assert_context(Context::String.new("'", "'")); end
    def test_dqte; assert_context(Context::String.new("\"", "\"")); end
    def test_lwrq; assert_context(Context::String.new("%q[", "]")); end
    def test_uprq; assert_context(Context::String.new("%Q[", "]")); end
    def test_dstr; assert_context(Context::String.new("%[", "]")); end
    def test_xstr; assert_context(Context::String.new("`", "`")); end
    def test_lwrx; assert_context(Context::String.new("%x[", "]")); end
    def test_h0_1; assert_context(Context::String.new("<<H\n", "\nH")); end
    def test_h0_2; assert_context(Context::String.new("<<'H'\n", "\nH")); end
    def test_h0_3; assert_context(Context::String.new("<<\"H\"\n", "\nH")); end
    def test_h0_4; assert_context(Context::String.new("<<`H`\n", "\nH")); end
    def test_hd_1; assert_context(Context::String.new("<<-H\n", "\nH")); end
    def test_hd_2; assert_context(Context::String.new("<<-'H'\n", "\nH")); end
    def test_hd_3; assert_context(Context::String.new("<<-\"H\"\n", "\nH")); end
    def test_hd_4; assert_context(Context::String.new("<<-`H`\n", "\nH")); end
    def test_ht_1; assert_context(Context::Heredoc.new("<<~H\n", "\nH")); end
    def test_ht_2; assert_context(Context::Heredoc.new("<<~'H'\n", "\nH")); end
    def test_ht_3; assert_context(Context::Heredoc.new("<<~\"H\"\n", "\nH")); end
    def test_ht_4; assert_context(Context::Heredoc.new("<<~`H`\n", "\nH")); end
    def test_pw_1; assert_context(Context::List.new("%w[", "]")); end
    def test_pw_2; assert_context(Context::List.new("%w<", ">")); end
    def test_uprw; assert_context(Context::List.new("%W[", "]")); end
    def test_lwri; assert_context(Context::List.new("%i[", "]")); end
    def test_upri; assert_context(Context::List.new("%I[", "]")); end
    def test_lwrs; assert_context(Context::Symbol.new("%s[", "]")); end
    def test_sym1; assert_context(Context::Symbol.new(":'", "'")); end
    def test_sym2; assert_context(Context::Symbol.new(":\"", "\"")); end
    def test_reg1; assert_context(Context::RegExp.new("/", "/")); end
    def test_reg2; assert_context(Context::RegExp.new("%r[", "]")); end
    def test_reg3; assert_context(Context::RegExp.new("%r<", ">")); end
    def test_reg4; assert_context(Context::RegExp.new("%r{", "}")); end
    def test_reg5; assert_context(Context::RegExp.new("%r(", ")")); end
    def test_reg6; assert_context(Context::RegExp.new("%r|", "|")); end

    private

    def assert_context(context)
      octal = [*("0".."7")]
      hex = [*("a".."f"), *("A".."F"), *("0".."9")]

      (0...256).each do |ord|
        # I think this might be a bug in Ruby.
        next if context.name == "?" && ord == 0xFF

        # We don't currently support scanning for the number of capture groups
        # to validate backreferences so these are all going to fail.
        next if (context.name == "//" || context.name.start_with?("%r")) && ord.chr.start_with?(/\d/)

        # \a \b \c ...
        assert_unescape(context, ord.chr)
      end

      # \\r\n
      assert_unescape(context, "\r\n")

      # We don't currently support scanning for the number of capture groups to
      # validate backreferences so these are all going to fail.
      if context.name != "//" && !context.name.start_with?("%r")
        # \00 \01 \02 ...
        octal.product(octal).each { |digits| assert_unescape(context, digits.join) }

        # \000 \001 \002 ...
        octal.product(octal).product(octal).each { |digits| assert_unescape(context, digits.join) }
      end

      # \x0 \x1 \x2 ...
      hex.each { |digit| assert_unescape(context, "x#{digit}") }

      # \x00 \x01 \x02 ...
      hex.product(hex).each { |digits| assert_unescape(context, "x#{digits.join}") }

      # \u0000 \u0001 \u0002 ...
      assert_unescape(context, "u#{["5"].concat(hex.sample(3)).join}")

      # The behavior of whitespace in the middle of these escape sequences
      # changed in Ruby 3.3.0, so we only want to test against latest.
      if RUBY_VERSION >= "3.3.0"
        # \u{00  00} ...
        assert_unescape(context, "u{00#{["5"].concat(hex.sample(3)).join} \t\v 00#{["5"].concat(hex.sample(3)).join}}")
      end

      (0...128).each do |ord|
        chr = ord.chr
        next if chr == "\\" || !chr.match?(/[[:print:]]/)

        # \C-a \C-b \C-c ...
        assert_unescape(context, "C-#{chr}")

        # \ca \cb \cc ...
        assert_unescape(context, "c#{chr}")

        # \M-a \M-b \M-c ...
        assert_unescape(context, "M-#{chr}")

        # \M-\C-a \M-\C-b \M-\C-c ...
        assert_unescape(context, "M-\\C-#{chr}")

        # \M-\ca \M-\cb \M-\cc ...
        assert_unescape(context, "M-\\c#{chr}")

        # \c\M-a \c\M-b \c\M-c ...
        assert_unescape(context, "c\\M-#{chr}")
      end
    end

    def assert_unescape(context, escape)
      expected = context.ruby_result(escape)
      actual = context.prism_result(escape)

      message = -> do
        "Expected #{context.name} to unescape #{escape.inspect} to " \
          "#{expected.inspect}, but got #{actual.inspect}"
      end

      if expected == :error || actual == :error
        assert_equal expected, actual, message
      else
        assert_equal expected.bytes, actual.bytes, message
      end
    end
  end
end

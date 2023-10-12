# frozen_string_literal: true

require_relative "test_helper"

return if Prism::BACKEND == :FFI

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
          result = Prism.parse(code(escape))

          if result.success?
            yield result.value.statements.body.first
          else
            :error
          end
        end

        def `(command)
          command
        end
      end

      class List < Base
        def ruby_result(escape) = ruby(escape) { |value| value.first.to_s }
        def prism_result(escape) = prism(escape) { |node| node.elements.first.unescaped }
      end

      class Symbol < Base
        def ruby_result(escape) = ruby(escape, &:to_s)
        def prism_result(escape) = prism(escape, &:unescaped)
      end

      class String < Base
        def ruby_result(escape) = ruby(escape, &:itself)
        def prism_result(escape) = prism(escape, &:unescaped)
      end

      class Heredoc < Base
        def ruby_result(escape) = ruby(escape, &:itself)
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
        def ruby_result(escape) = ruby(escape, &:source)
        def prism_result(escape) = prism(escape, &:unescaped)
      end
    end

    ascii = (0...128).map(&:chr)
    ascii8 = (128...256).map(&:chr)
    newlines = ["\r\n"]

    octal = [*("0".."7")]
    octal = octal.product(octal).map(&:join).concat(octal.product(octal).product(octal).map(&:join))

    hex2 = [*("a".."f"), *("A".."F"), *("0".."9")]
    hex2 = hex2.map { |h| "x#{h}" }.concat(hex2.product(hex2).map { |h| "x#{h.join}" })

    hex4 = [*("a".."f"), *("A".."F"), *("0".."9")]
    hex4 = ["5", "6"].product(hex4.sample(4)).product(hex4.sample(4)).product(hex4.sample(4)).map { |h| "u#{h.join}" }

    hex6 = [*("a".."f"), *("A".."F"), *("0".."9")]
    hex6 = ["5", "6"].product(hex6.sample(2)).product(hex6.sample(2)).product(hex6.sample(2)).map { |h| "u{00#{h.join}}" }

    ctrls = (ascii.grep(/[[:print:]]/) - ["\\"]).flat_map { |c| ["C-#{c}", "c#{c}", "M-#{c}", "M-\\C-#{c}", "M-\\c#{c}", "c\\M-#{c}"] }

    escapes = [*ascii, *ascii8, *newlines, *octal, *hex2, *hex4, *hex6, *ctrls]

    contexts = [
      Context::String.new("?", ""),
      Context::String.new("'", "'"),
      Context::String.new("\"", "\""),
      Context::String.new("%q[", "]"),
      Context::String.new("%Q[", "]"),
      Context::String.new("%[", "]"),
      Context::String.new("`", "`"),
      Context::String.new("%x[", "]"),
      Context::String.new("<<H\n", "\nH"),
      Context::String.new("<<'H'\n", "\nH"),
      Context::String.new("<<\"H\"\n", "\nH"),
      Context::String.new("<<`H`\n", "\nH"),
      Context::String.new("<<-H\n", "\nH"),
      Context::String.new("<<-'H'\n", "\nH"),
      Context::String.new("<<-\"H\"\n", "\nH"),
      Context::String.new("<<-`H`\n", "\nH"),
      Context::Heredoc.new("<<~H\n", "\nH"),
      Context::Heredoc.new("<<~'H'\n", "\nH"),
      Context::Heredoc.new("<<~\"H\"\n", "\nH"),
      Context::Heredoc.new("<<~`H`\n", "\nH"),
      Context::List.new("%w[", "]"),
      Context::List.new("%w<", ">"),
      Context::List.new("%W[", "]"),
      Context::List.new("%i[", "]"),
      Context::List.new("%I[", "]"),
      Context::Symbol.new("%s[", "]"),
      Context::Symbol.new(":'", "'"),
      Context::Symbol.new(":\"", "\""),
      Context::RegExp.new("/", "/"),
      Context::RegExp.new("%r[", "]"),
      Context::RegExp.new("%r<", ">"),
      Context::RegExp.new("%r{", "}"),
      Context::RegExp.new("%r(", ")"),
      Context::RegExp.new("%r|", "|"),
    ]

    contexts.each do |context|
      escapes.each do |escape|
        # I think this might be a bug in Ruby.
        next if context.name == "?" && escape == "\xFF".b

        # We don't currently support scanning for the number of capture groups,
        # so these are all going to fail.
        next if (context.name == "//" || context.name.start_with?("%r")) && escape.start_with?(/\d/)

        define_method(:"test_#{context.name}_#{escape.inspect}") do
          assert_unescape(context, escape)
        end
      end
    end

    private

    def assert_unescape(context, escape)
      expected = context.ruby_result(escape)
      actual = context.prism_result(escape)

      message = -> do
        "Expected #{context.name} to unescape #{escape.inspect} to #{expected.inspect}, but got #{actual.inspect}"
      end

      if expected == :error || actual == :error
        assert_equal expected, actual, message
      else
        assert_equal expected.bytes, actual.bytes, message
      end
    end
  end
end

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
      [Context::String.new("?", ""),             escapes],
      [Context::String.new("'", "'"),            escapes],
      [Context::String.new("\"", "\""),          escapes],
      [Context::String.new("%q[", "]"),          escapes],
      [Context::String.new("%Q[", "]"),          escapes],
      [Context::String.new("%[", "]"),           escapes],
      [Context::String.new("`", "`"),            escapes],
      [Context::String.new("%x[", "]"),          escapes],
      # [Context::String.new("<<~H\n", "\nH"),     escapes],
      # [Context::String.new("<<~'H'\n", "\nH"),   escapes],
      # [Context::String.new("<<~\"H\"\n", "\nH"), escapes],
      # [Context::String.new("<<~`H`\n", "\nH"),   escapes],
      [Context::List.new("%w[", "]"),            escapes],
      [Context::List.new("%W[", "]"),            escapes],
      [Context::List.new("%i[", "]"),            escapes],
      [Context::List.new("%I[", "]"),            escapes],
      # [Context::Symbol.new("%s[", "]"),          escapes],
      # [Context::Symbol.new(":'", "'"),           escapes],
      # [Context::Symbol.new(":\"", "\""),         escapes],
      # [Context::RegExp.new("/", "/"),            escapes],
      # [Context::RegExp.new("%r[", "]"),          escapes]
    ]

    contexts.each do |(context, escapes)|
      escapes.each do |escape|
        next if context.name == "?" && escape == "\xFF".b # wat?

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

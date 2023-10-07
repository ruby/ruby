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
          yield eval(code(escape))
        rescue SyntaxError
          :error
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

    octal = [*("0".."7")]
    octal = octal.product(octal).map(&:join).concat(octal.product(octal).product(octal).map(&:join))

    hex = [*("a".."f"), *("A".."F"), *("0".."9")]
    hex = hex.map { |h| "x#{h}" }.concat(hex.product(hex).map { |h| "x#{h.join}" }).concat(["5", "6"].product(hex.sample(4)).product(hex.sample(4)).product(hex.sample(4)).map { |h| "u#{h.join}" })

    hexes = [*("a".."f"), *("A".."F"), *("0".."9")]
    hexes = ["5", "6"].product(hexes.sample(2)).product(hexes.sample(2)).product(hexes.sample(2)).map { |h| "u{00#{h.join}}" }

    ctrls = ascii.grep(/[[:print:]]/).flat_map { |c| ["C-#{c}", "c#{c}", "M-#{c}", "M-\\C-#{c}", "M-\\c#{c}", "c\\M-#{c}"] }

    contexts = [
      Context::String.new("?", ""),
      Context::String.new("'", "'"),
      Context::String.new("\"", "\""),
      Context::String.new("%q[", "]"),
      Context::String.new("%Q[", "]"),
      Context::String.new("%[", "]"),
      Context::String.new("`", "`"),
      Context::String.new("<<~H\n", "\nH"),
      Context::String.new("<<~'H'\n", "\nH"),
      Context::String.new("<<~\"H\"\n", "\nH"),
      Context::String.new("<<~`H`\n", "\nH"),
      Context::List.new("%w[", "]"),
      Context::List.new("%W[", "]"),
      Context::List.new("%i[", "]"),
      Context::List.new("%I[", "]"),
      Context::Symbol.new("%s[", "]"),
      Context::Symbol.new(":'", "'"),
      Context::Symbol.new(":\"", "\""),
      Context::RegExp.new("/", "/"),
      Context::RegExp.new("%r[", "]")
    ]

    escapes = [*ascii, *ascii8, *octal, *hex, *hexes, *ctrls]

    contexts.each do |context|
      escapes.each do |escape|
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

      if expected == :error
        assert_equal expected, actual, message
      else
        assert_equal expected.bytes, actual.bytes, message
      end
    end
  end
end

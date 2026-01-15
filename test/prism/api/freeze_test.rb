# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class FreezeTest < TestCase
    def test_parse
      assert_frozen(Prism.parse("1 + 2; %i{foo} + %i{bar}", freeze: true))
    end

    def test_lex
      assert_frozen(Prism.lex("1 + 2; %i{foo} + %i{bar}", freeze: true))
    end

    def test_parse_lex
      assert_frozen(Prism.parse_lex("1 + 2; %i{foo} + %i{bar}", freeze: true))
      assert_frozen(Prism.parse_lex("# encoding: euc-jp\n%i{foo}", freeze: true))
    end

    def test_parse_comments
      assert_frozen(Prism.parse_comments("# comment", freeze: true))
    end

    def test_parse_stream
      assert_frozen(Prism.parse_stream(StringIO.new("1 + 2; %i{foo} + %i{bar}"), freeze: true))
    end

    if !ENV["PRISM_BUILD_MINIMAL"]
      def test_dump
        assert_frozen(Prism.dump("1 + 2; %i{foo} + %i{bar}", freeze: true))
      end
    end

    private

    def assert_frozen_each(value)
      assert_predicate value, :frozen?

      value.instance_variables.each do |name|
        case (child = value.instance_variable_get(name))
        when Array
          child.each { |item| assert_frozen_each(item) }
        when Hash
          child.each { |key, item| assert_frozen_each(key); assert_frozen_each(item) }
        else
          assert_frozen_each(child)
        end
      end
    end

    if defined?(Ractor.shareable?)
      def assert_frozen(value)
        assert_frozen_each(value)
        assert Ractor.shareable?(value), -> { binding.irb }
      end
    else
      alias assert_frozen assert_frozen_each
    end
  end
end

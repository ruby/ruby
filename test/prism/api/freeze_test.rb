# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
  class FreezeTest < TestCase
    def test_parse
      assert_frozen(Ruby::Prism.parse("1 + 2; %i{foo} + %i{bar}", freeze: true))
    end

    def test_offsets_usable
      node = Ruby::Prism.parse_statement("1 + 2", freeze: true)
      assert_equal(1, node.start_line)
    end

    def test_lex
      assert_frozen(Ruby::Prism.lex("1 + 2; %i{foo} + %i{bar}", freeze: true))
    end

    def test_parse_lex
      assert_frozen(Ruby::Prism.parse_lex("1 + 2; %i{foo} + %i{bar}", freeze: true))
      assert_frozen(Ruby::Prism.parse_lex("# encoding: euc-jp\n%i{foo}", freeze: true))
    end

    def test_parse_comments
      assert_frozen(Ruby::Prism.parse_comments("# comment", freeze: true))
    end

    def test_parse_stream
      assert_frozen(Ruby::Prism.parse_stream(StringIO.new("1 + 2; %i{foo} + %i{bar}"), freeze: true))
    end

    if !ENV["PRISM_BUILD_MINIMAL"]
      def test_dump
        assert_frozen(Ruby::Prism.dump("1 + 2; %i{foo} + %i{bar}", freeze: true))
      end
    end

    private

    # Sources and the locations within them refer to each other, so each object
    # is only checked the first time it is reached.
    def assert_frozen_each(value, seen = {}.compare_by_identity)
      return if seen.key?(value)
      seen[value] = true

      assert_predicate value, :frozen?

      value.instance_variables.each do |name|
        case (child = value.instance_variable_get(name))
        when Array
          child.each { |item| assert_frozen_each(item, seen) }
        when Hash
          child.each { |key, item| assert_frozen_each(key, seen); assert_frozen_each(item, seen) }
        else
          assert_frozen_each(child, seen)
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

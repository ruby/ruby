# frozen_string_literal: true

return unless defined?(Ractor) && Process.respond_to?(:fork)

require_relative "test_helper"

module Prism
  class RactorTest < TestCase
    def test_version
      assert_match(/\A\d+\.\d+\.\d+\z/, with_ractor { Prism::VERSION })
    end

    def test_parse_file
      assert_equal("Prism::ParseResult", with_ractor(__FILE__) { |filepath| Prism.parse_file(filepath).class })
    end

    def test_lex_file
      assert_equal("Prism::LexResult", with_ractor(__FILE__) { |filepath| Prism.lex_file(filepath).class })
    end

    def test_parse_file_comments
      assert_equal("Array", with_ractor(__FILE__) { |filepath| Prism.parse_file_comments(filepath).class })
    end

    def test_parse_lex_file
      assert_equal("Prism::ParseLexResult", with_ractor(__FILE__) { |filepath| Prism.parse_lex_file(filepath).class })
    end

    def test_parse_success
      assert_equal("true", with_ractor("1 + 1") { |source| Prism.parse_success?(source) })
    end

    def test_parse_failure
      assert_equal("true", with_ractor("1 +") { |source| Prism.parse_failure?(source) })
    end

    def test_string_query_local
      assert_equal("true", with_ractor("foo") { |source| StringQuery.local?(source) })
    end

    def test_string_query_constant
      assert_equal("true", with_ractor("FOO") { |source| StringQuery.constant?(source) })
    end

    def test_string_query_method_name
      assert_equal("true", with_ractor("foo?") { |source| StringQuery.method_name?(source) })
    end

    if !ENV["PRISM_BUILD_MINIMAL"]
      def test_dump_file
        result = with_ractor(__FILE__) { |filepath| Prism.dump_file(filepath) }
        assert_operator(result, :start_with?, "PRISM")
      end
    end

    private

    # Note that this must be done in a subprocess, otherwise it can mess up
    # CRuby's test suite.
    def with_ractor(*arguments, &block)
      IO.popen("-") do |reader|
        if reader
          reader.gets.chomp
        else
          ractor = ignore_warnings { Ractor.new(*arguments, &block) }

          # Somewhere in the Ruby 3.5.* series, Ractor#take was removed and
          # Ractor#value was added.
          puts(ractor.respond_to?(:value) ? ractor.value : ractor.take)
        end
      end
    end
  end
end

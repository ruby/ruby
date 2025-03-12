# frozen_string_literal: true

return unless defined?(Ractor)

require_relative "test_helper"

module Prism
  class RactorTest < TestCase
    def test_version
      refute_nil(with_ractor { Prism::VERSION })
    end

    def test_parse_file
      assert_kind_of(Prism::Result, with_ractor(__FILE__) { |filepath| Prism.parse_file(filepath) })
    end

    def test_lex_file
      assert_kind_of(Prism::Result, with_ractor(__FILE__) { |filepath| Prism.lex_file(filepath) })
    end

    def test_parse_file_comments
      assert_kind_of(Array, with_ractor(__FILE__) { |filepath| Prism.parse_file_comments(filepath) })
    end

    def test_parse_lex_file
      assert_kind_of(Prism::Result, with_ractor(__FILE__) { |filepath| Prism.parse_lex_file(filepath) })
    end

    def test_parse_success
      assert(with_ractor("1 + 1") { |source| Prism.parse_success?(source) })
    end

    def test_parse_failure
      assert(with_ractor("1 +") { |source| Prism.parse_failure?(source) })
    end

    def test_string_query_local
      assert(with_ractor("foo") { |source| StringQuery.local?(source) })
    end

    def test_string_query_constant
      assert(with_ractor("FOO") { |source| StringQuery.constant?(source) })
    end

    def test_string_query_method_name
      assert(with_ractor("foo?") { |source| StringQuery.method_name?(source) })
    end

    if !ENV["PRISM_BUILD_MINIMAL"]
      def test_dump_file
        assert_kind_of(String, with_ractor(__FILE__) { |filepath| Prism.dump_file(filepath) })
      end
    end

    private

    def with_ractor(*arguments, &block)
      ignore_warnings { Ractor.new(*arguments, &block) }.take
    end
  end
end

# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
  class StringQueryTest < TestCase
    def test_local?
      assert_predicate StringQuery.new("a"), :local?
      assert_predicate StringQuery.new("a1"), :local?
      assert_predicate StringQuery.new("self"), :local?

      assert_predicate StringQuery.new("_a"), :local?
      assert_predicate StringQuery.new("_1"), :local?

      assert_predicate StringQuery.new("😀"), :local?
      assert_predicate StringQuery.new("ア".encode("Windows-31J")), :local?

      refute_predicate StringQuery.new("1"), :local?
      refute_predicate StringQuery.new("A"), :local?
    end

    def test_constant?
      assert_predicate StringQuery.new("A"), :constant?
      assert_predicate StringQuery.new("A1"), :constant?
      assert_predicate StringQuery.new("A_B"), :constant?
      assert_predicate StringQuery.new("BEGIN"), :constant?

      assert_predicate StringQuery.new("À"), :constant?
      assert_predicate StringQuery.new("A".encode("US-ASCII")), :constant?

      refute_predicate StringQuery.new("a"), :constant?
      refute_predicate StringQuery.new("1"), :constant?
    end

    def test_method_name?
      assert_predicate StringQuery.new("a"), :method_name?
      assert_predicate StringQuery.new("A"), :method_name?
      assert_predicate StringQuery.new("__FILE__"), :method_name?

      assert_predicate StringQuery.new("a?"), :method_name?
      assert_predicate StringQuery.new("a!"), :method_name?
      assert_predicate StringQuery.new("a="), :method_name?

      assert_predicate StringQuery.new("+"), :method_name?
      assert_predicate StringQuery.new("<<"), :method_name?
      assert_predicate StringQuery.new("==="), :method_name?

      assert_predicate StringQuery.new("_0"), :method_name?

      refute_predicate StringQuery.new("1"), :method_name?
      refute_predicate StringQuery.new("_1"), :method_name?
    end

    KEYWORDS = %w[
      __ENCODING__ __LINE__ __FILE__ BEGIN END alias and begin break case
      class def defined? do else elsif end ensure false for if in module next
      nil not or redo rescue retry return self super then true undef unless
      until when while yield
    ]

    def test_keyword?
      KEYWORDS.each do |keyword|
        assert StringQuery.keyword?(keyword), "expected #{keyword.inspect} to be a keyword"
      end

      assert_predicate StringQuery.new("end"), :keyword?
      assert_predicate StringQuery.new("end".encode("US-ASCII")), :keyword?

      refute_predicate StringQuery.new(""), :keyword?
      refute_predicate StringQuery.new("foo"), :keyword?
      refute_predicate StringQuery.new("defined"), :keyword?
      refute_predicate StringQuery.new("__END__"), :keyword?
      refute_predicate StringQuery.new("__end__"), :keyword?
      refute_predicate StringQuery.new("End"), :keyword?
      refute_predicate StringQuery.new("ends"), :keyword?
      refute_predicate StringQuery.new("do?"), :keyword?
      refute_predicate StringQuery.new("then!"), :keyword?
    end

    def test_keyword_variants
      KEYWORDS.each do |keyword|
        variants = [
          "#{keyword}x",
          "x#{keyword}",
          keyword[0...-1],
          keyword.upcase,
          keyword.capitalize
        ]

        variants.each do |variant|
          assert_equal KEYWORDS.include?(variant), StringQuery.keyword?(variant), "unexpected result for #{variant.inspect}"
        end
      end
    end

    def test_invalid_encoding
      assert_raise ArgumentError do
        StringQuery.new("A".encode("UTF-16LE")).local?
      end

      assert_raise ArgumentError do
        StringQuery.new("end".encode("UTF-16LE")).keyword?
      end
    end

    if BACKEND == :FFI
      # Ruby strings always have a readable byte after their contents, so call
      # the C functions directly with a slice that is immediately followed by a
      # method name suffix. That byte is outside the slice and must be ignored.
      def test_does_not_read_past_slice
        local = FFI::MemoryPointer.from_string("foo?")
        assert_equal :PM_STRING_QUERY_TRUE, LibRubyParser.pm_string_query_local(local, 3, "UTF-8")
        assert_equal :PM_STRING_QUERY_TRUE, LibRubyParser.pm_string_query_method_name(local, 3, "UTF-8")

        constant = FFI::MemoryPointer.from_string("Foo=")
        assert_equal :PM_STRING_QUERY_TRUE, LibRubyParser.pm_string_query_constant(constant, 3, "UTF-8")
      end
    end
  end
end

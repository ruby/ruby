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

    # Ruby 3.3 and 3.4 use Unicode 15.0.0, and Ruby 4.0 and 4.1 use Unicode
    # 17.0.0, in which the Garay capital letters are uppercase.
    def test_version
      garay = [0x10D50].pack("U")

      refute StringQuery.constant?(garay, version: "3.3")
      assert StringQuery.local?(garay, version: "3.4")
      assert StringQuery.constant?(garay, version: "4.0")
      refute StringQuery.local?(garay, version: "4.1")
      assert StringQuery.constant?(garay, version: "latest")
      assert StringQuery.constant?(garay, version: "4.0.1")

      assert StringQuery.new(garay).constant?(version: "4.0")
      assert StringQuery.new(garay).local?(version: "3.4")
      assert StringQuery.new("end").keyword?(version: "3.3")
      assert StringQuery.new("a?").method_name?(version: "3.3")
    end
  end
end

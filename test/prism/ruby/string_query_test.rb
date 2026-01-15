# frozen_string_literal: true

require_relative "../test_helper"

module Prism
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

    def test_invalid_encoding
      assert_raise ArgumentError do
        StringQuery.new("A".encode("UTF-16LE")).local?
      end
    end
  end
end

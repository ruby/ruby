# frozen_string_literal: false
require 'test/unit'
require '-test-/hash'

class Test_Hash < Test::Unit::TestCase
  class TestDeleteAt < Test::Unit::TestCase
    def test_delete_at
      original = { a: "a", b: "b", c: "c" }

      assert_equal ["a", "c", nil], original.delete_at(:a, :c, :c)
      assert_equal({ b: "b" }, original)
    end

    def test_delete_at_with_block
      original = {}

      assert_equal [0], original.delete_at(:a) { 0 }
      assert_empty original
    end

    def test_delete_at_missing_key_with_default_value
      original = Hash.new(0)

      assert_equal [0], original.delete_at(:a)
      assert_empty original
    end

    def test_delete_at_missing_key_with_default_block
      original = Hash.new { 0 }

      assert_equal [0], original.delete_at(:a)
      assert_empty original
    end
  end
end

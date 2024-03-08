# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class StaticLiteralsTest < TestCase
    def test_static_literals
      assert_warning("1")
      assert_warning("0xA", "10")
      assert_warning("0o10", "8")
      assert_warning("0b10", "2")
      assert_warning("1_000")
      assert_warning((2**32).to_s(10), "0x#{(2**32).to_s(16)}")
      assert_warning((2**64).to_s(10), "0x#{(2**64).to_s(16)}")

      refute_warning("1", "-1")
      refute_warning((2**32).to_s(10), "-0x#{(2**32).to_s(16)}")
      refute_warning((2**64).to_s(10), "-0x#{(2**64).to_s(16)}")

      assert_warning("__LINE__", "2")
      assert_warning("3", "__LINE__")

      assert_warning("1.0")
      assert_warning("1e2", "100.0")

      assert_warning("1r")
      assert_warning("1.0r")

      assert_warning("1i")
      assert_warning("1.0i")

      assert_warning("1ri")
      assert_warning("1.0ri")

      assert_warning("\"#{__FILE__}\"")
      assert_warning("\"foo\"")
      assert_warning("\"#{__FILE__}\"", "__FILE__")

      assert_warning("/foo/")

      refute_warning("/foo/", "/foo/i")

      assert_warning(":foo")
      assert_warning("%s[foo]")

      assert_warning("true")
      assert_warning("false")
      assert_warning("nil")
      assert_warning("__ENCODING__")
    end

    private

    def parse_warnings(left, right)
      warnings = []

      warnings << Prism.parse(<<~RUBY, filepath: __FILE__).warnings.first
        {
          #{left} => 1,
          #{right} => 2
        }
      RUBY

      warnings << Prism.parse(<<~RUBY, filepath: __FILE__).warnings.first
        case foo
        when #{left}
        when #{right}
        end
      RUBY

      warnings
    end

    def assert_warning(left, right = left)
      hash_keys, when_clauses = parse_warnings(left, right)

      assert_include hash_keys.message, left
      assert_include hash_keys.message, "line 3"
      assert_include when_clauses.message, "line 3"
    end

    def refute_warning(left, right)
      assert_empty parse_warnings(left, right).compact
    end
  end
end

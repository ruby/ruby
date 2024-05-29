# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class StaticLiteralsTest < TestCase
    def test_static_literals
      assert_warning("1")
      assert_warning("0xA", "10", "10")
      assert_warning("0o10", "8", "8")
      assert_warning("0b10", "2", "2")
      assert_warning("1_000", "1000", "1000")
      assert_warning((2**32).to_s(10), "0x#{(2**32).to_s(16)}", (2**32).to_s(10))
      assert_warning((2**64).to_s(10), "0x#{(2**64).to_s(16)}", (2**64).to_s(10))

      refute_warning("1", "-1")
      refute_warning((2**32).to_s(10), "-0x#{(2**32).to_s(16)}")
      refute_warning((2**64).to_s(10), "-0x#{(2**64).to_s(16)}")

      assert_warning("__LINE__", "2", "2")
      assert_warning("3", "__LINE__", "3")

      assert_warning("1.0")
      assert_warning("1e2", "100.0", "100.0")

      assert_warning("1r", "1r", "(1/1)")
      assert_warning("1.0r", "1.0r", "(1/1)")

      assert_warning("1i", "1i", "(0+1i)")
      assert_warning("1.0i", "1.0i", "(0+1.0i)")

      assert_warning("1ri", "1ri", "(0+(1/1)*i)")
      assert_warning("1.0ri", "1.0ri", "(0+(1/1)*i)")

      assert_warning("__FILE__", "\"#{__FILE__}\"", __FILE__)
      assert_warning("\"#{__FILE__}\"")
      assert_warning("\"foo\"")

      assert_warning("/foo/")

      refute_warning("/foo/", "/foo/i")

      assert_warning(":foo")
      assert_warning("%s[foo]", ":foo", ":foo")

      assert_warning("true")
      assert_warning("false")
      assert_warning("nil")
      assert_warning("__ENCODING__", "__ENCODING__", "#<Encoding:UTF-8>")
    end

    private

    class NullWarning
      def message
        ""
      end
    end

    def parse_warnings(left, right)
      warnings = []

      warnings << (Prism.parse(<<~RUBY, filepath: __FILE__).warnings.first || NullWarning.new)
        {
          #{left} => 1,
          #{right} => 2
        }
      RUBY

      warnings << (Prism.parse(<<~RUBY, filepath: __FILE__).warnings.first || NullWarning.new)
        case foo
        when #{left}
        when #{right}
        end
      RUBY

      warnings
    end

    def assert_warning(left, right = left, message = left)
      hash_keys, when_clauses = parse_warnings(left, right)

      assert_include hash_keys.message, message
      assert_include hash_keys.message, "line 3"
      assert_include when_clauses.message, "line 3"
    end

    def refute_warning(left, right)
      assert_empty parse_warnings(left, right).grep_v(NullWarning)
    end
  end
end

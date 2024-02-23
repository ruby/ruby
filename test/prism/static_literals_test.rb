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

    def parse_warning(left, right)
      source = <<~RUBY
        {
          #{left} => 1,
          #{right} => 2
        }
      RUBY

      Prism.parse(source, filepath: __FILE__).warnings.first
    end

    def assert_warning(left, right = left)
      assert_match %r{key #{Regexp.escape(left)} .+ line 3}, parse_warning(left, right)&.message
    end

    def refute_warning(left, right)
      assert_nil parse_warning(left, right)
    end
  end
end

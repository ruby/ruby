# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
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

    def test_float_key_inspect
      {
        "1.23456789" => "1.23456789",
        "1e-4" => "0.0001",
        "1e-5" => "1.0e-05",
        "1e6" => "1000000.0",
        "1e15" => "1.0e+15",
        "1000000000000000.2" => "1000000000000000.2",
        "1e23" => "1.0e+23",
        "2.98023223876953125e-8" => "2.9802322387695312e-08",
        "4.89298916017815570e-296" => "4.8929891601781557e-296",
        "5764607523034235e24" => "5.764607523034235e+39",
        "5e-324" => "5.0e-324",
        "2.2250738585072014e-308" => "2.2250738585072014e-308",
        "1.7976931348623157e308" => "1.7976931348623157e+308",
        "-0.0" => "-0.0",
        "0.0i" => "(0+0.0i)",
        "-0.0i" => "(0-0.0i)",
        "1e999i" => "(0+Infinity*i)",
        "-1e999i" => "(0-Infinity*i)"
      }.each do |literal, expected|
        result = Ruby::Prism.parse("{ #{literal} => 1, #{literal} => 2 }")
        warning = result.warnings.find { |item| item.type == :duplicated_hash_key }
        assert_equal "key #{expected} is duplicated and overwritten on line 1", warning&.message, literal
      end
    end

    private

    class NullWarning
      def message
        ""
      end
    end

    def parse_warnings(left, right)
      warnings = []

      warnings << (Ruby::Prism.parse(<<~RUBY, filepath: __FILE__).warnings.first || NullWarning.new)
        {
          #{left} => 1,
          #{right} => 2
        }
      RUBY

      warnings << (Ruby::Prism.parse(<<~RUBY, filepath: __FILE__).warnings.first || NullWarning.new)
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

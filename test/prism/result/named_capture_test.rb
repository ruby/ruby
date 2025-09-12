# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class NamedCaptureTest < TestCase
    def test_hex_escapes
      assert_equal :😀, parse_name("\\xf0\\x9f\\x98\\x80")
    end

    def test_unicode_escape
      assert_equal :し, parse_name("\\u3057")
    end

    def test_unicode_escapes_bracess
      assert_equal :😀, parse_name("\\u{1f600}")
    end

    def test_octal_escapes
      assert_equal :😀, parse_name("\\xf0\\x9f\\x98\\200")
    end

    private

    def parse_name(content)
      Prism.parse_statement("/(?<#{content}>)/ =~ ''").targets.first.name
    end
  end
end

# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
  class StaticLiteralFlagTest < TestCase
    # A regular expression or symbol that interpolates only strings whose values
    # are known while parsing is a static literal. Whether those strings are
    # frozen does not matter, since only their values are interpolated.
    def test_interpolated_strings_with_known_values
      [
        '/a#{"b" "c"}/', '/a#{"b#{"c"}"}/', ':"a#{"b" "c"}"', ':"a#{"b#{"c"}"}"'
      ].each do |source|
        assert_static_literal(true, source)
      end
    end

    def test_interpolated_strings_with_unknown_values
      ['/a#{"b#{1}"}/', '/a#{1}/', ':"a#{"b#{1}"}"'].each do |source|
        assert_static_literal(false, source)
      end
    end

    private

    def assert_static_literal(expected, source)
      ["", "# frozen_string_literal: true\n"].each do |magic_comment|
        node = Ruby::Prism.parse_statement("#{magic_comment}#{source}")
        assert_equal expected, node.static_literal?, "#{magic_comment}#{source}"
      end
    end
  end
end

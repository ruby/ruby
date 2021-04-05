require "test/unit"
require "rexml/document"

module REXMLTests
  class TestParseElement < Test::Unit::TestCase
    def parse(xml)
      REXML::Document.new(xml)
    end

    class TestInvalid < self
      def test_top_level_end_tag
        exception = assert_raise(REXML::ParseException) do
          parse("</a>")
        end
        assert_equal(<<-DETAIL.chomp, exception.to_s)
Unexpected top-level end tag (got 'a')
Line: 1
Position: 4
Last 80 unconsumed characters:

        DETAIL
      end

      def test_no_end_tag
        exception = assert_raise(REXML::ParseException) do
          parse("<a></")
        end
        assert_equal(<<-DETAIL.chomp, exception.to_s)
Missing end tag for 'a'
Line: 1
Position: 5
Last 80 unconsumed characters:
</
        DETAIL
      end

      def test_empty_namespace_attribute_name
        exception = assert_raise(REXML::ParseException) do
          parse("<x :a=\"\"></x>")
        end
        assert_equal(<<-DETAIL.chomp, exception.to_s)
Invalid attribute name: <:a="">
Line: 1
Position: 13
Last 80 unconsumed characters:

        DETAIL
      end

      def test_garbage_less_than_before_root_element_at_line_start
        exception = assert_raise(REXML::ParseException) do
          parse("<\n<x/>")
        end
        assert_equal(<<-DETAIL.chomp, exception.to_s)
malformed XML: missing tag start
Line: 2
Position: 6
Last 80 unconsumed characters:
< <x/>
        DETAIL
      end

      def test_garbage_less_than_slash_before_end_tag_at_line_start
        exception = assert_raise(REXML::ParseException) do
          parse("<x></\n</x>")
        end
        assert_equal(<<-DETAIL.chomp, exception.to_s)
Missing end tag for 'x'
Line: 2
Position: 10
Last 80 unconsumed characters:
</ </x>
        DETAIL
      end
    end
  end
end

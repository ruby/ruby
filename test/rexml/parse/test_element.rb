require "test/unit"
require "rexml/document"

module REXMLTests
  class TestParseElement < Test::Unit::TestCase
    def parse(xml)
      REXML::Document.new(xml)
    end

    class TestInvalid < self
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
Position: 9
Last 80 unconsumed characters:

        DETAIL
      end
    end
  end
end

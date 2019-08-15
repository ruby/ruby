require "test/unit"
require "rexml/document"

module REXMLTests
  class TestParseProcessinInstruction < Test::Unit::TestCase
    def parse(xml)
      REXML::Document.new(xml)
    end

    class TestInvalid < self
      def test_no_name
        exception = assert_raise(REXML::ParseException) do
          parse("<??>")
        end
        assert_equal(<<-DETAIL.chomp, exception.to_s)
Invalid processing instruction node
Line: 1
Position: 4
Last 80 unconsumed characters:
<??>
        DETAIL
      end
    end
  end
end

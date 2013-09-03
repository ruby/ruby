require "test/unit"
require "rexml/document"
require "rexml/parsers/treeparser"

class TestTreeParser < Test::Unit::TestCase
  class TestInvalid < self
    def test_parse_exception
      xml = "<root></not-root>"
      exception = assert_raise(REXML::ParseException) do
        parse(xml)
      end
      assert_equal(<<-MESSAGE, exception.to_s)
Missing end tag for 'root' (got "not-root")
Line: 1
Position: 17
Last 80 unconsumed characters:
      MESSAGE
    end

    private
    def parse(xml)
      document = REXML::Document.new
      parser = REXML::Parsers::TreeParser.new(xml, document)
      parser.parse
    end
  end
end

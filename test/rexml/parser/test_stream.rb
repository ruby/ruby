require "test/unit"
require "rexml/document"
require "rexml/streamlistener"

module REXMLTests
  class TestStreamParser < Test::Unit::TestCase
    class NullListener
      include REXML::StreamListener
    end

    class TestInvalid < self
      def test_no_end_tag
        xml = "<root><sub>"
        exception = assert_raise(REXML::ParseException) do
          parse(xml)
        end
        assert_equal(<<-MESSAGE, exception.to_s)
Missing end tag for '/root/sub'
Line: 1
Position: #{xml.bytesize}
Last 80 unconsumed characters:
        MESSAGE
      end

      private
      def parse(xml, listener=nil)
        listener ||= NullListener.new
        REXML::Document.parse_stream(xml, listener)
      end
    end
  end
end

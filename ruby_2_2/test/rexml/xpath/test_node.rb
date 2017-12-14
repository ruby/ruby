# -*- coding: utf-8 -*-

require_relative "../rexml_test_utils"

require "rexml/document"

module REXMLTests
  class TestXPathNode < Test::Unit::TestCase
    def matches(xml, xpath)
      document = REXML::Document.new(xml)
      REXML::XPath.each(document, xpath).collect(&:to_s)
    end

    class TestQName < self
      def test_ascii
        xml = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <ascii>
    <child>child</child>
  </ascii>
</root>
        XML
        assert_equal(["<child>child</child>"],
                     matches(xml, "/root/ascii/child"))
      end

      def test_non_ascii
        xml = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <non-àscii>
    <child>child</child>
  </non-àscii>
</root>
        XML
        assert_equal(["<child>child</child>"],
                     matches(xml, "/root/non-àscii/child"))
      end
    end
  end
end

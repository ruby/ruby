# frozen_string_literal: false

require_relative "../rexml_test_utils"

require "rexml/document"

module REXMLTests
  class TestXPathNodeSet < Test::Unit::TestCase
    def match(xml, xpath)
      document = REXML::Document.new(xml)
      REXML::XPath.match(document, xpath)
    end

    def test_boolean_true
      xml = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <child/>
  <child/>
</root>
      XML
      assert_equal([true],
                   match(xml, "/root/child=true()"))
    end

    def test_boolean_false
      xml = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<root>
</root>
      XML
      assert_equal([false],
                   match(xml, "/root/child=true()"))
    end

    def test_number_true
      xml = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <child>100</child>
  <child>200</child>
</root>
      XML
      assert_equal([true],
                   match(xml, "/root/child=100"))
    end

    def test_number_false
      xml = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <child>100</child>
  <child>200</child>
</root>
      XML
      assert_equal([false],
                   match(xml, "/root/child=300"))
    end

    def test_string_true
      xml = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <child>text</child>
  <child>string</child>
</root>
      XML
      assert_equal([true],
                   match(xml, "/root/child='string'"))
    end

    def test_string_false
      xml = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <child>text</child>
  <child>string</child>
</root>
      XML
      assert_equal([false],
                   match(xml, "/root/child='nonexistent'"))
    end
  end
end

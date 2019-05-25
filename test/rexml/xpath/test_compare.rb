# frozen_string_literal: false

require_relative "../rexml_test_utils"

require "rexml/document"

module REXMLTests
  class TestXPathCompare < Test::Unit::TestCase
    def match(xml, xpath)
      document = REXML::Document.new(xml)
      REXML::XPath.match(document, xpath)
    end

    class TestEqual < self
      class TestNodeSet < self
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

      class TestBoolean < self
        def test_number_true
          xml = "<root/>"
          assert_equal([true],
                       match(xml, "true()=1"))
        end

        def test_number_false
          xml = "<root/>"
          assert_equal([false],
                       match(xml, "true()=0"))
        end

        def test_string_true
          xml = "<root/>"
          assert_equal([true],
                       match(xml, "true()='string'"))
        end

        def test_string_false
          xml = "<root/>"
          assert_equal([false],
                       match(xml, "true()=''"))
        end
      end

      class TestNumber < self
        def test_string_true
          xml = "<root/>"
          assert_equal([true],
                       match(xml, "1='1'"))
        end

        def test_string_false
          xml = "<root/>"
          assert_equal([false],
                       match(xml, "1='2'"))
        end
      end
    end

    class TestGreaterThan < self
      class TestNodeSet < self
        def test_boolean_truex
          xml = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <child/>
</root>
          XML
          assert_equal([true],
                       match(xml, "/root/child>false()"))
        end

        def test_boolean_false
          xml = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <child/>
</root>
        XML
          assert_equal([false],
                       match(xml, "/root/child>true()"))
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
                       match(xml, "/root/child>199"))
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
                       match(xml, "/root/child>200"))
        end

        def test_string_true
          xml = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <child>100</child>
  <child>200</child>
</root>
          XML
          assert_equal([true],
                       match(xml, "/root/child>'199'"))
        end

        def test_string_false
          xml = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <child>100</child>
  <child>200</child>
</root>
          XML
          assert_equal([false],
                       match(xml, "/root/child>'200'"))
        end
      end

      class TestBoolean < self
        def test_string_true
          xml = "<root/>"
          assert_equal([true],
                       match(xml, "true()>'0'"))
        end

        def test_string_false
          xml = "<root/>"
          assert_equal([false],
                       match(xml, "true()>'1'"))
        end
      end

      class TestNumber < self
        def test_boolean_true
          xml = "<root/>"
          assert_equal([true],
                       match(xml, "true()>0"))
        end

        def test_number_false
          xml = "<root/>"
          assert_equal([false],
                       match(xml, "true()>1"))
        end

        def test_string_true
          xml = "<root/>"
          assert_equal([true],
                       match(xml, "1>'0'"))
        end

        def test_string_false
          xml = "<root/>"
          assert_equal([false],
                       match(xml, "1>'1'"))
        end
      end

      class TestString < self
        def test_string_true
          xml = "<root/>"
          assert_equal([true],
                       match(xml, "'1'>'0'"))
        end

        def test_string_false
          xml = "<root/>"
          assert_equal([false],
                       match(xml, "'1'>'1'"))
        end
      end
    end
  end
end

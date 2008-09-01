require "rexml/document"
require "test/unit"

class REXML::TestDocument < Test::Unit::TestCase
  def test_new
    doc = REXML::Document.new(<<EOF)
<?xml version="1.0" encoding="UTF-8"?>
<message>Hello world!</message>
EOF
    assert_equal("Hello world!", doc.root.children.first.value)
  end

  def test_entity_expansion_limit
    xml = <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE member [
  <!ENTITY a "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">
  <!ENTITY b "&c;&c;&c;&c;&c;&c;&c;&c;&c;&c;">
  <!ENTITY c "&d;&d;&d;&d;&d;&d;&d;&d;&d;&d;">
  <!ENTITY d "&e;&e;&e;&e;&e;&e;&e;&e;&e;&e;">
  <!ENTITY e "&f;&f;&f;&f;&f;&f;&f;&f;&f;&f;">
  <!ENTITY f "&g;&g;&g;&g;&g;&g;&g;&g;&g;&g;">
  <!ENTITY g "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx">
]>
<member>
&a;
</member>
EOF
    doc = REXML::Document.new(xml)
    assert_raise(RuntimeError) do
      doc.root.children.first.value
    end
    REXML::Document.entity_expansion_limit = 100
    assert_equal(100, REXML::Document.entity_expansion_limit)
    doc = REXML::Document.new(xml)
    assert_raise(RuntimeError) do
      doc.root.children.first.value
    end
    assert_equal(101, doc.entity_expansion_count)
  end
end
require "rexml/document"
require "test/unit"

class REXML::TestDocument < Test::Unit::TestCase
  def test_new
    doc = REXML::Document.new(<<EOF)
<?xml version="1.0" encoding="UTF-8"?>
<message>Hello world!</message>
EOF
    assert_equal("Hello world!", doc.root.children.first.value)
  end

  XML_WITH_NESTED_ENTITY = <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE member [
  <!ENTITY a "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">
  <!ENTITY b "&c;&c;&c;&c;&c;&c;&c;&c;&c;&c;">
  <!ENTITY c "&d;&d;&d;&d;&d;&d;&d;&d;&d;&d;">
  <!ENTITY d "&e;&e;&e;&e;&e;&e;&e;&e;&e;&e;">
  <!ENTITY e "&f;&f;&f;&f;&f;&f;&f;&f;&f;&f;">
  <!ENTITY f "&g;&g;&g;&g;&g;&g;&g;&g;&g;&g;">
  <!ENTITY g "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx">
]>
<member>
&a;
</member>
EOF

  def test_entity_expansion_limit
    doc = REXML::Document.new(XML_WITH_NESTED_ENTITY)
    assert_raise(RuntimeError) do
      doc.root.children.first.value
    end
    REXML::Document.entity_expansion_limit = 100
    assert_equal(100, REXML::Document.entity_expansion_limit)
    doc = REXML::Document.new(XML_WITH_NESTED_ENTITY)
    assert_raise(RuntimeError) do
      doc.root.children.first.value
    end
    assert_equal(101, doc.entity_expansion_count)
  end
end

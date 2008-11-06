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

  XML_WITH_4_ENTITY_EXPANSION = <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE member [
  <!ENTITY a "a">
  <!ENTITY a2 "&a; &a;">
]>
<member>
&a;
&a2;
&lt;
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

    REXML::Document.entity_expansion_limit = 4
    doc = REXML::Document.new(XML_WITH_4_ENTITY_EXPANSION)
    assert_equal("\na\na a\n<\n", doc.root.children.first.value)
    REXML::Document.entity_expansion_limit = 3
    doc = REXML::Document.new(XML_WITH_4_ENTITY_EXPANSION)
    assert_raise(RuntimeError) do
      doc.root.children.first.value
    end
  ensure
    REXML::Document.entity_expansion_limit = 10000
  end
end

require "test/unit"
require "rexml/document"

module REXMLTests
  class TestParseDocumentTypeDeclaration < Test::Unit::TestCase
    private
    def xml(internal_subset)
      <<-XML
<!DOCTYPE r SYSTEM "urn:x-rexml:test" [
#{internal_subset}
]>
<r/>
      XML
    end

    def parse(internal_subset)
      REXML::Document.new(xml(internal_subset)).doctype
    end

    class TestMixed < self
      def test_entity_element
        doctype = parse(<<-INTERNAL_SUBSET)
<!ENTITY entity-name "entity content">
<!ELEMENT element-name EMPTY>
        INTERNAL_SUBSET
        assert_equal([REXML::Entity, REXML::ElementDecl],
                     doctype.children.collect(&:class))
      end

      def test_attlist_entity
        doctype = parse(<<-INTERNAL_SUBSET)
<!ATTLIST attribute-list-name attribute-name CDATA #REQUIRED>
<!ENTITY entity-name "entity content">
        INTERNAL_SUBSET
        assert_equal([REXML::AttlistDecl, REXML::Entity],
                     doctype.children.collect(&:class))
      end

      def test_notation_attlist
        doctype = parse(<<-INTERNAL_SUBSET)
<!NOTATION notation-name SYSTEM "system-literal">
<!ATTLIST attribute-list-name attribute-name CDATA #REQUIRED>
        INTERNAL_SUBSET
        assert_equal([REXML::NotationDecl, REXML::AttlistDecl],
                     doctype.children.collect(&:class))
      end
    end
  end
end

# frozen_string_literal: false
require "test/unit"
require "rexml/parsers/ultralightparser"

module REXMLTests
class TestUltraLightParser < Test::Unit::TestCase
  class TestDocumentTypeDeclaration < self
    def test_entity_declaration
      assert_equal([
                     [
                       :start_doctype,
                       :parent,
                       "root",
                       "SYSTEM",
                       "urn:x-test",
                       nil,
                       [:entitydecl, "name", "value"]
                     ],
                     [:start_element, :parent, "root", {}],
                     [:text, "\n"],
                   ],
                   parse(<<-INTERNAL_SUBSET))
<!ENTITY name "value">
      INTERNAL_SUBSET
    end

    private
    def xml(internal_subset)
      <<-XML
<!DOCTYPE root SYSTEM "urn:x-test" [
#{internal_subset}
]>
<root/>
      XML
    end

    def parse(internal_subset)
      parser = REXML::Parsers::UltraLightParser.new(xml(internal_subset))
      normalize(parser.parse)
    end

    def normalize(root)
      root.collect do |child|
        normalize_child(child)
      end
    end

    def normalize_child(child)
      tag = child.first
      case tag
      when :start_doctype
        normalized_parent = :parent
        normalized_doctype = child.dup
        normalized_doctype[1] = normalized_parent
        normalized_doctype
      when :start_element
        tag, _parent, name, attributes, *children = child
        normalized_parent = :parent
        normalized_children = children.collect do |sub_child|
          normalize_child(sub_child)
        end
        [tag, normalized_parent, name, attributes, *normalized_children]
      else
        child
      end
    end
  end
end
end

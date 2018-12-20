# frozen_string_literal: false
#
#  Created by Henrik Mårtensson on 2007-02-18.
#  Copyright (c) 2007. All rights reserved.

require "rexml/document"
require "test/unit"

module REXMLTests
  class TestXmlDeclaration < Test::Unit::TestCase
    def setup
      xml = <<-XML
      <?xml encoding= 'UTF-8' standalone='yes'?>
      <root>
      </root>
      XML
      @doc = REXML::Document.new xml
      @root = @doc.root
      @xml_declaration = @doc.children[0]
    end

    def test_is_first_child
      assert_kind_of(REXML::XMLDecl, @xml_declaration)
    end

    def test_has_document_as_parent
     assert_kind_of(REXML::Document, @xml_declaration.parent)
    end

    def test_has_sibling
      assert_kind_of(REXML::XMLDecl, @root.previous_sibling.previous_sibling)
      assert_kind_of(REXML::Element, @xml_declaration.next_sibling.next_sibling)
    end

    def test_write_prologue_quote
      @doc.context[:prologue_quote] = :quote
      assert_equal("<?xml version=\"1.0\" " +
                   "encoding=\"UTF-8\" standalone=\"yes\"?>",
                   @xml_declaration.to_s)
    end
  end
end

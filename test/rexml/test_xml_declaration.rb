# -*- coding: utf-8 -*-
#
#  Created by Henrik Mårtensson on 2007-02-18.
#  Copyright (c) 2007. All rights reserved.

require "rexml/document"
require "test/unit"

class TestXmlDeclaration < Test::Unit::TestCase
  def setup
    @xml = <<-'END_XML'
    <?xml encoding= 'UTF-8' standalone='yes'?>
    <root>
    </root>
    END_XML
    @doc = REXML::Document.new @xml
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

  def test_uses_xml_doc_context_to_write_attributes
    # use single quotes if no context specified
    s = ''
    @xml_declaration.write s
    assert_equal %q(<?xml version='1.0' encoding='UTF-8' standalone='yes'?>), s

    # use double quotes if specified to use them
    s = ''
    REXML::Document.new(@xml, :attribute_quote => :quote).children[0].write s
    assert_equal %q(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>), s

    # use single quotes if xmldecl is not a child of xml document
    s = ''
    REXML::XMLDecl.new.write s
    assert_equal %q(<?xml version='1.0'?>), s
  end
end

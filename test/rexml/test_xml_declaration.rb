#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
#
#  Created by Henrik Mårtensson on 2007-02-18.
#  Copyright (c) 2007. All rights reserved.

require "rexml/document"
require "test/unit"

class TestXmlDeclaration < Test::Unit::TestCase
  def setup
    xml = <<-'END_XML'
    <?xml encoding= 'UTF-8' standalone='yes'?>
    <root>
    </root>
    END_XML
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

  def test_equal
    lower_encoding_xml_decl = REXML::XMLDecl.new("1.0", "utf-8")
    upper_encoding_xml_decl = REXML::XMLDecl.new("1.0", "UTF-8")
    assert_equal(lower_encoding_xml_decl, upper_encoding_xml_decl)
  end

  def test_encoding_is_not_normalized
    lower_encoding_xml_decl = REXML::XMLDecl.new("1.0", "utf-8")
    assert_equal("<?xml version='1.0' encoding='utf-8'?>",
                 lower_encoding_xml_decl.to_s)
  end
end

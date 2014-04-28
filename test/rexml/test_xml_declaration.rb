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

  # Using single quotes is default behavior of existing code for XMLDecl.
  # (Although DocType uses double quotes as default)
  def test_uses_single_quotes_as_default_if_no_option_specified
    output = ''
    xml = %q(<?xml encoding="UTF-8" standalone="yes"?>)
    REXML::Document.new(xml).xml_decl.write output
    assert_equal %q(<?xml version='1.0' encoding='UTF-8' standalone='yes'?>), output
  end

  def test_uses_double_quotes_if_specified
    output = ''
    xml = %q(<?xml encoding='UTF-8' standalone='yes'?>)
    REXML::Document.new(xml, :xml_prologue_quote => :quote).xml_decl.write output
    assert_equal %q(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>), output
  end

  def test_uses_single_quotes_if_specified
    output = ''
    xml = %q(<?xml encoding="UTF-8" standalone="yes"?>)
    REXML::Document.new(xml, :xml_prologue_quote => :apos).xml_decl.write output
    assert_equal %q(<?xml version='1.0' encoding='UTF-8' standalone='yes'?>), output
  end

  def test_uses_single_quotes_if_unsupported_option_specified
    output = ''
    xml = %q(<?xml encoding="UTF-8" standalone="yes"?>)
    REXML::Document.new(xml, :xml_prologue_quote => :accent).xml_decl.write output
    assert_equal %q(<?xml version='1.0' encoding='UTF-8' standalone='yes'?>), output
  end

  def test_uses_single_quotes_as_default_if_orphan
    # use single quotes if xmldecl is not a child of xml document
    output = ''
    REXML::XMLDecl.new.write output
    assert_equal %q(<?xml version='1.0'?>), output
  end

end

# frozen_string_literal: false

require "test/unit"
require "rexml/document"
require "rexml/functions"

module REXMLTests
  class TestFunctionsLocalName < Test::Unit::TestCase
    def setup
      REXML::Functions.context = nil
    end

    def test_one
      document = REXML::Document.new(<<-XML)
<root xmlns:x="http://example.com/x/">
  <x:child/>
</root>
      XML
      node_set = document.root.children
      assert_equal("child", REXML::Functions.local_name(node_set))
    end

    def test_multiple
      document = REXML::Document.new(<<-XML)
<root xmlns:x="http://example.com/x/">
  <x:child1/>
  <x:child2/>
</root>
      XML
      node_set = document.root.children
      assert_equal("child1", REXML::Functions.local_name(node_set))
    end

    def test_nonexistent
      assert_equal("", REXML::Functions.local_name([]))
    end

    def test_context
      document = REXML::Document.new("<root/>")
      REXML::Functions.context = {node: document.root}
      assert_equal("root", REXML::Functions.local_name())
    end
  end
end

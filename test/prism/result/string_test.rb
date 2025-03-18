# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class StringTest < TestCase
    def test_regular_expression_node_unescaped_frozen
      node = Prism.parse_statement("/foo/")
      assert_predicate node.unescaped, :frozen?
    end

    def test_source_file_node_filepath_frozen
      node = Prism.parse_statement("__FILE__")
      assert_predicate node.filepath, :frozen?
    end

    def test_string_node_unescaped_frozen
      node = Prism.parse_statement('"foo"')
      assert_predicate node.unescaped, :frozen?
    end

    def test_symbol_node_unescaped_frozen
      node = Prism.parse_statement(":foo")
      assert_predicate node.unescaped, :frozen?
    end

    def test_xstring_node_unescaped_frozen
      node = Prism.parse_statement("`foo`")
      assert_predicate node.unescaped, :frozen?
    end
  end
end

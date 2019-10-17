# frozen_string_literal: true
require_relative 'helper'

module Psych
  class TestTreeBuilder < TestCase
    def setup
      super
      @parser = Psych::Parser.new TreeBuilder.new
      @parser.parse(<<-eoyml)
%YAML 1.1
---
- foo
- {
  bar : &A !!str baz,
  boo : *A
}
- *A
      eoyml
      @tree = @parser.handler.root
    end

    def test_stream
      assert_instance_of Nodes::Stream, @tree
      assert_location 0, 0, 8, 0, @tree
    end

    def test_documents
      assert_equal 1, @tree.children.length
      assert_instance_of Nodes::Document, @tree.children.first
      doc = @tree.children.first

      assert_equal [1,1], doc.version
      assert_equal [], doc.tag_directives
      assert_equal false, doc.implicit
      assert_location 0, 0, 8, 0, doc
    end

    def test_sequence
      doc = @tree.children.first
      assert_equal 1, doc.children.length

      seq = doc.children.first
      assert_instance_of Nodes::Sequence, seq
      assert_nil seq.anchor
      assert_nil seq.tag
      assert_equal true, seq.implicit
      assert_equal Nodes::Sequence::BLOCK, seq.style
      assert_location 2, 0, 8, 0, seq
    end

    def test_scalar
      doc = @tree.children.first
      seq = doc.children.first

      assert_equal 3, seq.children.length
      scalar = seq.children.first
      assert_instance_of Nodes::Scalar, scalar
      assert_equal 'foo', scalar.value
      assert_nil scalar.anchor
      assert_nil scalar.tag
      assert_equal true, scalar.plain
      assert_equal false, scalar.quoted
      assert_equal Nodes::Scalar::PLAIN, scalar.style
      assert_location 2, 2, 2, 5, scalar
    end

    def test_mapping
      doc = @tree.children.first
      seq = doc.children.first
      map = seq.children[1]

      assert_instance_of Nodes::Mapping, map
      assert_location 3, 2, 6, 1, map
    end

    def test_alias
      doc = @tree.children.first
      seq = doc.children.first
      assert_equal 3, seq.children.length
      al  = seq.children[2]
      assert_instance_of Nodes::Alias, al
      assert_equal 'A', al.anchor
      assert_location 7, 2, 7, 4, al
    end

    private
    def assert_location(start_line, start_column, end_line, end_column, node)
      assert_equal start_line, node.start_line
      assert_equal start_column, node.start_column
      assert_equal end_line, node.end_line
      assert_equal end_column, node.end_column
    end
  end
end

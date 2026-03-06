# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class BreadthFirstSearchTest < TestCase
    def test_breadth_first_search
      result = Prism.parse("[1 + 2, 2]")
      found =
        result.value.breadth_first_search do |node|
          node.is_a?(IntegerNode) && node.value == 2
        end

      refute_nil found
      assert_equal 8, found.start_offset
    end

    def test_breadth_first_search_all
      result = Prism.parse("[1 + 2, 2]")
      found_nodes =
        result.value.breadth_first_search_all do |node|
          node.is_a?(IntegerNode)
        end

      assert_equal 3, found_nodes.size
      assert_equal 8, found_nodes[0].start_offset
    end
  end
end

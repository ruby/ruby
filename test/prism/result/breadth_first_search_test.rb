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
  end
end

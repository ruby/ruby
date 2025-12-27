# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Counterexamples
    # @rbs generic E < Object -- Type of an element
    class Node
      attr_reader :elem #: E
      attr_reader :next_node #: Node[E]?

      # @rbs [E < Object] (Node[E] node) -> Array[E]
      def self.to_a(node)
        a = [] # steep:ignore UnannotatedEmptyCollection

        while (node)
          a << node.elem
          node = node.next_node
        end

        a
      end

      # @rbs (E elem, Node[E]? next_node) -> void
      def initialize(elem, next_node)
        @elem = elem
        @next_node = next_node
      end
    end
  end
end

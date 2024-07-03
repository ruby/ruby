# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class NodeIdTest < TestCase
    Fixture.each do |fixture|
      define_method(fixture.test_name) { assert_node_ids(fixture.read) }
    end

    private

    def assert_node_ids(source)
      queue = [Prism.parse(source).value]
      node_ids = []

      while (node = queue.shift)
        node_ids << node.node_id
        queue.concat(node.compact_child_nodes)
      end

      node_ids.sort!
      refute_includes node_ids, 0
      assert_equal node_ids, node_ids.uniq
    end
  end
end

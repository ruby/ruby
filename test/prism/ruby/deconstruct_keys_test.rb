# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class DeconstructKeysTest < TestCase
    def test_deconstruct_keys
      node = Prism.parse_statement("1.to_s")

      deconstruct_all = node.deconstruct_keys(nil)
      assert_equal deconstruct_all[:node_id], node.node_id
      assert_equal deconstruct_all[:message], "to_s"

      deconstruct_receiver = node.deconstruct_keys([:receiver])
      assert_equal 1, deconstruct_receiver[:receiver].value
      refute_includes deconstruct_receiver.keys, :message

      deconstruct_invalid = node.deconstruct_keys([:invalid])
      refute_includes deconstruct_invalid.keys, :invalid
    end
  end
end

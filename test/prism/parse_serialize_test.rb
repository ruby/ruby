# frozen_string_literal: true

require_relative "test_helper"

return if Prism::BACKEND == :FFI

module Prism
  class ParseSerializeTest < TestCase
    def test_parse_serialize
      dumped = Debug.parse_serialize_file(__FILE__)
      result = Prism.load(File.read(__FILE__), dumped)

      assert_kind_of ParseResult, result, "Expected the return value to be a ParseResult"
      assert_equal __FILE__, find_file_node(result)&.filepath, "Expected the filepath to be set correctly"
    end

    def test_parse_serialize_with_locals
      filepath = __FILE__
      metadata = [filepath.bytesize, filepath.b, 1, 1, 1, "foo".b].pack("LA*LLLA*")

      dumped = Debug.parse_serialize_file_metadata(filepath, metadata)
      result = Prism.load(File.read(__FILE__), dumped)

      assert_kind_of ParseResult, result, "Expected the return value to be a ParseResult"
    end

    private

    def find_file_node(result)
      queue = [result.value]

      while (node = queue.shift)
        return node if node.is_a?(SourceFileNode)
        queue.concat(node.compact_child_nodes)
      end
    end
  end
end

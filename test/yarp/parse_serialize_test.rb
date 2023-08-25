# frozen_string_literal: true

require_relative "test_helper"

return if YARP::BACKEND == :FFI

class ParseSerializeTest < Test::Unit::TestCase
  def test_parse_serialize
    dumped = YARP.const_get(:Debug).parse_serialize_file(__FILE__)
    result = YARP.load(File.read(__FILE__), dumped)

    assert_kind_of YARP::ParseResult, result, "Expected the return value to be a ParseResult"
    assert_equal __FILE__, find_file_node(result)&.filepath, "Expected the filepath to be set correctly"
  end

  private

  def find_file_node(result)
    queue = [result.value]

    while (node = queue.shift)
      return node if node.is_a?(YARP::SourceFileNode)
      queue.concat(node.child_nodes.compact)
    end
  end
end

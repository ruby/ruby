# frozen_string_literal: true

require_relative "test_helper"

return if YARP::BACKEND == :FFI

class MemsizeTest < Test::Unit::TestCase
  def test_memsize
    result = YARP.const_get(:Debug).memsize("2 + 3")

    assert_equal 5, result[:length]
    assert_kind_of Integer, result[:memsize]
    assert_equal 6, result[:node_count]
  end
end

# frozen_string_literal: true

require "test_helper"

class MemsizeTest < Test::Unit::TestCase
  test "memsize" do
    result = YARP.memsize("2 + 3")

    assert_equal 5, result[:length]
    assert_kind_of Integer, result[:memsize]
    assert_equal 7, result[:node_count]
  end
end

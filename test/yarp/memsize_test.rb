# frozen_string_literal: true

require "yarp_test_helper"

class MemsizeTest < Test::Unit::TestCase
  def test_memsize
    result = YARP.memsize("2 + 3")

    assert_equal 5, result[:length]
    assert_kind_of Integer, result[:memsize]
    assert_equal 6, result[:node_count]
  end
end

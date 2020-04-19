require "test_helper"

class Ruby::Signature::BufferTest < Minitest::Test
  Buffer = Ruby::Signature::Buffer

  def test_buffer
    buffer = Buffer.new(name: Pathname("foo.rbs"), content: <<-CONTENT)
123
abc
    CONTENT

    assert_equal ["123\n", "abc\n"], buffer.lines
    assert_equal [0...4, 4...8], buffer.ranges

    assert_equal [1, 0], buffer.pos_to_loc(0)
    assert_equal [1, 1], buffer.pos_to_loc(1)
    assert_equal [1, 2], buffer.pos_to_loc(2)
    assert_equal [1, 3], buffer.pos_to_loc(3)
    assert_equal [2, 0], buffer.pos_to_loc(4)
    assert_equal [2, 1], buffer.pos_to_loc(5)
    assert_equal [2, 2], buffer.pos_to_loc(6)
    assert_equal [2, 3], buffer.pos_to_loc(7)
    assert_equal [3, 0], buffer.pos_to_loc(8)

    assert_equal 0, buffer.loc_to_pos([1, 0])
    assert_equal 1, buffer.loc_to_pos([1, 1])
    assert_equal 2, buffer.loc_to_pos([1, 2])
    assert_equal 3, buffer.loc_to_pos([1, 3])
    assert_equal 4, buffer.loc_to_pos([2, 0])
    assert_equal 5, buffer.loc_to_pos([2, 1])
    assert_equal 6, buffer.loc_to_pos([2, 2])
    assert_equal 7, buffer.loc_to_pos([2, 3])
    assert_equal 8, buffer.loc_to_pos([3, 0])

    assert_equal "123", buffer.content[buffer.loc_to_pos([1,0])...buffer.loc_to_pos([1,3])]
    assert_equal "123\n", buffer.content[buffer.loc_to_pos([1,0])...buffer.loc_to_pos([2,0])]

    assert_equal 8, buffer.last_position
  end
end

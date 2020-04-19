require "test_helper"

class Ruby::Signature::LocationTest < Minitest::Test
  Buffer = Ruby::Signature::Buffer
  Location = Ruby::Signature::Location

  def test_location_source
    buffer = Buffer.new(name: Pathname("foo.rbs"), content: <<-CONTENT)
123
abc
    CONTENT

    Location.new(buffer: buffer, start_pos: 0, end_pos: 4).yield_self do |location|
      assert_equal 1, location.start_line
      assert_equal 0, location.start_column
      assert_equal 2, location.end_line
      assert_equal 0, location.end_column
      assert_equal "123\n", location.source
    end

    Location.new(buffer: buffer, start_pos: 4, end_pos: 8).yield_self do |location|
      assert_equal 2, location.start_line
      assert_equal 0, location.start_column
      assert_equal 3, location.end_line
      assert_equal 0, location.end_column
      assert_equal "abc\n", location.source
    end
  end

  def test_location_plus
    buffer = Buffer.new(name: Pathname("foo.rbs"), content: <<-CONTENT)
123
abc
    CONTENT

    loc1 = Location.new(buffer: buffer, start_pos: 0, end_pos: 3)
    loc2 = Location.new(buffer: buffer, start_pos: 4, end_pos: 7)

    loc = loc1 + loc2

    assert_equal 0, loc.start_pos
    assert_equal 7, loc.end_pos
    assert_equal "123\nabc", loc.source
  end
end

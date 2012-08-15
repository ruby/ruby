require 'test/unit'
require "-test-/printf"

class Test_SPrintf < Test::Unit::TestCase
  def to_s
    "#{self.class}:#{object_id}"
  end

  def inspect
    "<#{self.class}:#{object_id}>"
  end

  def test_int
    assert_match(/\A<-?\d+>\z/, Bug::Printf.i(self))
  end

  def test_to_str
    assert_equal("<#{self.class}:#{object_id}>", Bug::Printf.s(self))
  end

  def test_inspect
    assert_equal("{<#{self.class}:#{object_id}>}", Bug::Printf.v(self))
  end

  def test_encoding
    def self.to_s
      "\u{3042 3044 3046 3048 304a}"
    end
    assert_equal("<\u{3042 3044 3046 3048 304a}>", Bug::Printf.s(self))
  end
end

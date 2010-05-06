require_relative 'helper'

class TestFiddle < Fiddle::TestCase
  def test_constants_match
    [
      :TYPE_VOID,
      :TYPE_VOIDP,
      :TYPE_CHAR,
      :TYPE_SHORT,
      :TYPE_INT,
      :TYPE_LONG,
      :TYPE_LONG_LONG,
      :TYPE_FLOAT,
      :TYPE_DOUBLE,
    ].each do |name|
      assert_equal(DL.const_get(name), Fiddle.const_get(name))
    end
  end
end

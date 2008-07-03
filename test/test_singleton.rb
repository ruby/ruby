require 'test/unit'
require 'singleton'

class TestSingleton < Test::Unit::TestCase
  class C
    include Singleton
  end

  def test_marshal
    o1 = C.instance
    m = Marshal.dump(o1)
    o2 = Marshal.load(m)
    assert_same(o1, o2)
  end
end

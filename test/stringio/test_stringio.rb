require 'test/unit'
require 'stringio'

class TestStringIO < Test::Unit::TestCase
  def test_empty_file
    f = StringIO.new("")
    assert_equal("", f.read(0))
    assert_equal("", f.read)
    assert_equal(nil, f.read(0))
    f = StringIO.new("")
    assert_equal(nil, f.read(1))
    assert_equal(nil, f.read)
    assert_equal(nil, f.read(1))
  end
end

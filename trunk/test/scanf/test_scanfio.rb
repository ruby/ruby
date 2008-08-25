# $Id$
#
# scanf for Ruby
#
# Ad hoc tests of IO#scanf (needs to be expanded)


require "scanf"

class TestScanfIO
  def test_io
    fh = File.new(File.join(File.dirname(__FILE__), "data.txt"), "r")
    assert_equal(0, fh.pos)
    assert_equal(["this", "is"], fh.scanf("%s%s"))
    assert_equal([33, "littel"], fh.scanf("%da fun%s"))
    #p fh.pos
  end
end


# frozen_string_literal: false
# $Id$
#
# scanf for Ruby
#
# Ad hoc tests of IO#scanf (needs to be expanded)

require 'test/unit'
require 'scanf'

class TestScanfIO < Test::Unit::TestCase
  def test_io
    File.open(File.join(File.dirname(__FILE__), "data.txt"), "r") do |fh|
      assert_equal(0, fh.pos)
      assert_equal(["this", "is"], fh.scanf("%s%s"))
      assert_equal([33, "little"], fh.scanf("%da fun%s"))
    end
  end

  def test_pipe_scanf
    IO.pipe do |r, w|
      w.write('a')
      w.close
      assert_equal([], r.scanf('a'))
    end
  end
end


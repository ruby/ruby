require 'rubygems'
require 'minitest/autorun'
require 'rdoc/markup'
require 'rdoc/markup/to_test'

class TestRDocMarkup < MiniTest::Unit::TestCase

  def test_convert
    str = <<-STR
now is
the time

  hello
  dave

1. l1
2. l2
    STR

    m = RDoc::Markup.new
    out = m.convert str, RDoc::Markup::ToTest.new

    expected = [
      "now is the time",
      "\n",
      "  hello\n  dave\n",
      "1: ",
      "l1",
      "1: ",
      "l2",
    ]

    assert_equal expected, out
  end

end


require 'test/unit'
begin
  require 'iconv'
rescue LoadError
end

class TestIConv < Test::Unit::TestCase
  ASCII = "ascii"
  def test_simple
    c = Iconv.open(ASCII, ASCII)
    ref = '[ruby-core:17092]'
  rescue
    return
  else
    assert_equal("abc", c.iconv("abc"))
    assert_equal("c",   c.iconv("abc", 2),     "#{ref}: with start")
    assert_equal("c",   c.iconv("abc", 2, 1),  "#{ref}: with start, length")
    assert_equal("c",   c.iconv("abc", 2, 5),  "#{ref}: with start, longer length")
    assert_equal("bc",  c.iconv("abc", -2),    "#{ref}: with nagative start")
    assert_equal("b",   c.iconv("abc", -2, 1), "#{ref}: with nagative start, length")
    assert_equal("bc",  c.iconv("abc", -2, 5), "#{ref}: with nagative start, longer length")
    assert_equal("",    c.iconv("abc", 5),     "#{ref}: with OOB")
    assert_equal("",    c.iconv("abc", 5, 2),  "#{ref}: with OOB, length")
  ensure
    c.close if c
  end
end if defined?(::Iconv)
